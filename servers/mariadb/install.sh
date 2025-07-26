#!/bin/bash
#
# File: install.sh
# Description: Install latest MariaDB server with secure configuration
# Author: Bashmin Project
# Usage: ./install.sh [OPTIONS]
#
# Options:
#   -h, --help      Show this help message
#   -v, --verbose   Enable verbose output
#   -n, --dry-run   Show what would be done without executing
#   --root-password Set root password (prompted if not provided)
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/system.sh"

# Constants
readonly MARIADB_SERVICE="mariadb"
readonly MARIADB_CONFIG_SOURCE="$PROJECT_ROOT/system/etc/mysql/mariadb.conf.d/50-server.cnf"
readonly MARIADB_CONFIG_TARGET="/etc/mysql/mariadb.conf.d/50-server.cnf"
readonly DEFAULT_ROOT_PASSWORD=""

# Configuration
VERBOSE=false
DRY_RUN=false
ROOT_PASSWORD=""

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install latest MariaDB server with secure configuration.

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output  
    -n, --dry-run           Show what would be done without executing
    --root-password PASS    Set root password (prompted if not provided)

Examples:
    $0                      Install with prompted root password
    $0 -v                   Install with verbose output
    $0 --root-password secret123    Install with specified password
    $0 -n                   Dry run to see what would be installed

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --root-password)
                ROOT_PASSWORD="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to validate prerequisites
validate_prerequisites() {
    print_info "Validating prerequisites..."
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. This is not recommended for security reasons."
    elif ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        exit 1
    fi
    
    # Check if MariaDB is already installed
    if is_package_installed "mariadb-server"; then
        print_warning "MariaDB server is already installed"
        local status
        status=$(get_service_status "$MARIADB_SERVICE")
        print_info "Current MariaDB service status: $status"
        
        read -p "Continue with installation? This will update existing installation. (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled by user"
            exit 0
        fi
    fi
    
    print_success "Prerequisites validated"
}

# Function to prompt for root password
prompt_root_password() {
    if [[ -z "$ROOT_PASSWORD" ]]; then
        print_info "Setting up MariaDB root password..."
        while true; do
            read -s -p "Enter MariaDB root password: " ROOT_PASSWORD
            echo
            if [[ ${#ROOT_PASSWORD} -lt 8 ]]; then
                print_warning "Password should be at least 8 characters long"
                continue
            fi
            
            read -s -p "Confirm MariaDB root password: " confirm_password
            echo
            if [[ "$ROOT_PASSWORD" == "$confirm_password" ]]; then
                break
            else
                print_warning "Passwords do not match. Please try again."
            fi
        done
        print_success "Root password set"
    fi
}

# Function to update package repository
update_repository() {
    print_info "Updating package repository..."
    execute_command "sudo apt update" "Updating package lists"
}

# Function to install MariaDB server
install_mariadb() {
    print_info "Installing MariaDB server..."
    
    # Set debconf selections for unattended installation
    if [[ -n "$ROOT_PASSWORD" ]]; then
        execute_command "sudo debconf-set-selections <<< 'mariadb-server mysql-server/root_password password $ROOT_PASSWORD'" "Setting root password for unattended installation"
        execute_command "sudo debconf-set-selections <<< 'mariadb-server mysql-server/root_password_again password $ROOT_PASSWORD'" "Confirming root password for unattended installation"
    fi
    
    # Install packages
    local packages=(
        "mariadb-server"
        "mariadb-client" 
        "mariadb-common"
        "mariadb-server-core-10.6"
    )
    
    install_packages "${packages[@]}"
    
    print_success "MariaDB server installed"
}

# Function to configure MariaDB
configure_mariadb() {
    print_info "Configuring MariaDB..."
    
    # Copy optimized configuration if it exists
    if [[ -f "$MARIADB_CONFIG_SOURCE" ]]; then
        execute_command "sudo cp '$MARIADB_CONFIG_SOURCE' '$MARIADB_CONFIG_TARGET'" "Copying optimized MariaDB configuration"
        execute_command "sudo chown root:root '$MARIADB_CONFIG_TARGET'" "Setting configuration file ownership"
        execute_command "sudo chmod 644 '$MARIADB_CONFIG_TARGET'" "Setting configuration file permissions"
        print_success "Applied optimized MariaDB configuration"
    else
        print_warning "Optimized configuration file not found at $MARIADB_CONFIG_SOURCE"
    fi
}

# Function to start and enable MariaDB service
start_mariadb_service() {
    print_info "Starting and enabling MariaDB service..."
    
    execute_command "sudo systemctl start $MARIADB_SERVICE" "Starting MariaDB service"
    execute_command "sudo systemctl enable $MARIADB_SERVICE" "Enabling MariaDB service to start on boot"
    
    # Wait a moment for service to fully start
    sleep 2
    
    local status
    status=$(get_service_status "$MARIADB_SERVICE")
    if [[ "$status" == "active" ]]; then
        print_success "MariaDB service is running"
    else
        print_error "MariaDB service failed to start. Status: $status"
        exit 1
    fi
}

# Function to run mysql_secure_installation equivalent
secure_mariadb_installation() {
    print_info "Securing MariaDB installation..."
    
    # Create temporary SQL script for secure installation
    local secure_script="/tmp/mariadb_secure_install.sql"
    
    cat > "$secure_script" << EOF
-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Disallow root login remotely
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove test database and access to it
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Update root password if provided
$(if [[ -n "$ROOT_PASSWORD" ]]; then
    echo "UPDATE mysql.user SET Password=PASSWORD('$ROOT_PASSWORD') WHERE User='root';"
    echo "UPDATE mysql.user SET plugin='mysql_native_password' WHERE User='root';"
fi)

-- Reload privilege tables
FLUSH PRIVILEGES;
EOF

    # Execute the secure installation script
    if [[ -n "$ROOT_PASSWORD" ]]; then
        execute_command "sudo mysql -u root -p'$ROOT_PASSWORD' < '$secure_script'" "Applying security configurations"
    else
        execute_command "sudo mysql -u root < '$secure_script'" "Applying security configurations"
    fi
    
    # Clean up temporary script
    execute_command "sudo rm -f '$secure_script'" "Cleaning up temporary files"
    
    print_success "MariaDB installation secured"
}

# Function to verify installation
verify_installation() {
    print_info "Verifying MariaDB installation..."
    
    # Check service status
    local status
    status=$(get_service_status "$MARIADB_SERVICE")
    if [[ "$status" != "active" ]]; then
        print_error "MariaDB service is not running"
        return 1
    fi
    
    # Test database connection
    if [[ -n "$ROOT_PASSWORD" ]]; then
        if sudo mysql -u root -p"$ROOT_PASSWORD" -e "SELECT VERSION();" >/dev/null 2>&1; then
            print_success "Database connection test passed"
        else
            print_error "Database connection test failed"
            return 1
        fi
    else
        if sudo mysql -u root -e "SELECT VERSION();" >/dev/null 2>&1; then
            print_success "Database connection test passed"
        else
            print_error "Database connection test failed"
            return 1
        fi
    fi
    
    # Get version info
    local version
    if [[ -n "$ROOT_PASSWORD" ]]; then
        version=$(sudo mysql -u root -p"$ROOT_PASSWORD" -e "SELECT VERSION();" -s -N 2>/dev/null)
    else
        version=$(sudo mysql -u root -e "SELECT VERSION();" -s -N 2>/dev/null)
    fi
    
    print_success "MariaDB $version installed and running"
    return 0
}

# Function to display post-installation information
show_post_install_info() {
    cat << EOF

${GREEN}=== MariaDB Installation Complete ===${NC}

MariaDB has been successfully installed and secured.

${BLUE}Service Information:${NC}
- Service: $MARIADB_SERVICE
- Status: $(get_service_status "$MARIADB_SERVICE")
- Config: $MARIADB_CONFIG_TARGET

${BLUE}Connection Information:${NC}
- Host: localhost (127.0.0.1)
- Port: 3306
- Root User: root
- Socket: /var/run/mysqld/mysqld.sock

${BLUE}Common Commands:${NC}
- Connect to MariaDB:    sudo mysql -u root -p
- Service status:        sudo systemctl status $MARIADB_SERVICE
- Service restart:       sudo systemctl restart $MARIADB_SERVICE
- Service logs:          sudo journalctl -u $MARIADB_SERVICE

${BLUE}Security Notes:${NC}
- Anonymous users have been removed
- Root remote access has been disabled
- Test database has been removed
- Root password has been set (if provided)

${YELLOW}Next Steps:${NC}
1. Create additional database users as needed
2. Create application databases
3. Configure firewall rules if needed
4. Set up regular backups

EOF
}

# Main installation function
main() {
    print_info "Starting MariaDB installation..."
    
    parse_arguments "$@"
    validate_prerequisites
    prompt_root_password
    update_repository
    install_mariadb
    configure_mariadb
    start_mariadb_service
    secure_mariadb_installation
    
    if verify_installation; then
        show_post_install_info
        print_success "MariaDB installation completed successfully!"
    else
        print_error "MariaDB installation verification failed"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
