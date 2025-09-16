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
#   -f, --force     Force installation even if already installed
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
FORCE_INSTALL=false
ROOT_PASSWORD=""
ADMIN_USERNAME="devops"
ADMIN_PASSWORD=""

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install latest MariaDB server with secure configuration.

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -n, --dry-run           Show what would be done without executing
    -f, --force             Force installation even if already installed
    --root-password PASS    Set root password (prompted if not provided)

Examples:
    $0                      Install with prompted root password
    $0 -v                   Install with verbose output
    $0 --root-password secret123    Install with specified password
    $0 -f                   Force install even if already installed
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
            -f|--force)
                FORCE_INSTALL=true
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
        
        if [[ "$FORCE_INSTALL" != "true" ]]; then
            read -p "Continue with installation? This will update existing installation. (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Installation cancelled by user"
                exit 0
            fi
        else
            print_info "Force install enabled, proceeding with installation"
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

# Function to prompt for admin user details
prompt_admin_user() {
    print_info "Setting up alternative MariaDB admin user..."

    # Prompt for username
    read -p "Enter admin username (default: devops): " ADMIN_USERNAME
    if [[ -z "$ADMIN_USERNAME" ]]; then
        ADMIN_USERNAME="devops"
    fi

    # Validate username (basic validation)
    if [[ ! "$ADMIN_USERNAME" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        print_error "Invalid username. Must start with a letter and contain only letters, numbers, and underscores."
        exit 1
    fi

    print_success "Admin username set: $ADMIN_USERNAME"

    # Check if admin user already exists
    local admin_exists=false
    if [[ -n "$ROOT_PASSWORD" ]]; then
        if sudo mysql -u root -p"$ROOT_PASSWORD" -e "SELECT User FROM mysql.user WHERE User='$ADMIN_USERNAME' LIMIT 1;" 2>/dev/null | grep -q "$ADMIN_USERNAME"; then
            admin_exists=true
        fi
    else
        if sudo mysql -u root -e "SELECT User FROM mysql.user WHERE User='$ADMIN_USERNAME' LIMIT 1;" 2>/dev/null | grep -q "$ADMIN_USERNAME"; then
            admin_exists=true
        fi
    fi

    if [[ "$admin_exists" == "true" ]]; then
        print_info "Admin user '$ADMIN_USERNAME' already exists"
        read -p "Update $ADMIN_USERNAME user password? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping $ADMIN_USERNAME user password update"
            return 0
        fi
    fi

    print_info "Setting up MariaDB $ADMIN_USERNAME user password..."
    while true; do
        read -s -p "Enter MariaDB $ADMIN_USERNAME user password: " ADMIN_PASSWORD
        echo
        if [[ ${#ADMIN_PASSWORD} -lt 8 ]]; then
            print_warning "Password should be at least 8 characters long"
            continue
        fi

        read -s -p "Confirm MariaDB $ADMIN_USERNAME user password: " confirm_password
        echo
        if [[ "$ADMIN_PASSWORD" == "$confirm_password" ]]; then
            break
        else
            print_warning "Passwords do not match. Please try again."
        fi
    done
    print_success "$ADMIN_USERNAME user password set"
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
    echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PASSWORD';"
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

# Function to create admin user
create_admin_user() {
    # Skip if admin password was not set (user chose not to update existing user)
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        print_info "Skipping $ADMIN_USERNAME user creation (no password provided)"
        return 0
    fi

    print_info "Creating/updating $ADMIN_USERNAME user with administrative privileges..."

    # Create temporary SQL script for admin user
    local admin_script="/tmp/mariadb_create_admin.sql"

    cat > "$admin_script" << EOF
-- Create or update admin user
CREATE USER IF NOT EXISTS '$ADMIN_USERNAME'@'localhost' IDENTIFIED BY '$ADMIN_PASSWORD';
CREATE USER IF NOT EXISTS '$ADMIN_USERNAME'@'127.0.0.1' IDENTIFIED BY '$ADMIN_PASSWORD';
CREATE USER IF NOT EXISTS '$ADMIN_USERNAME'@'::1' IDENTIFIED BY '$ADMIN_PASSWORD';

-- Update password for existing users
ALTER USER '$ADMIN_USERNAME'@'localhost' IDENTIFIED BY '$ADMIN_PASSWORD';
ALTER USER '$ADMIN_USERNAME'@'127.0.0.1' IDENTIFIED BY '$ADMIN_PASSWORD';
ALTER USER '$ADMIN_USERNAME'@'::1' IDENTIFIED BY '$ADMIN_PASSWORD';

-- Grant all privileges to admin user
GRANT ALL PRIVILEGES ON *.* TO '$ADMIN_USERNAME'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO '$ADMIN_USERNAME'@'127.0.0.1' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO '$ADMIN_USERNAME'@'::1' WITH GRANT OPTION;

-- Reload privilege tables
FLUSH PRIVILEGES;
EOF

    # Execute the admin user creation script
    if [[ -n "$ROOT_PASSWORD" ]]; then
        execute_command "sudo mysql -u root -p'$ROOT_PASSWORD' < '$admin_script'" "Creating/updating $ADMIN_USERNAME user"
    else
        execute_command "sudo mysql -u root < '$admin_script'" "Creating/updating $ADMIN_USERNAME user"
    fi

    # Clean up temporary script
    execute_command "sudo rm -f '$admin_script'" "Cleaning up temporary files"

    print_success "$ADMIN_USERNAME user created/updated with full administrative privileges"
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
    echo
    echo -e "${GREEN}=== MariaDB Installation Complete ===${NC}"
    echo
    echo "MariaDB has been successfully installed and secured."
    echo
    echo -e "${BLUE}Service Information:${NC}"
    echo "- Service: $MARIADB_SERVICE"
    echo "- Status: $(get_service_status "$MARIADB_SERVICE")"
    echo "- Config: $MARIADB_CONFIG_TARGET"
    echo
    echo -e "${BLUE}Connection Information:${NC}"
    echo "- Host: localhost (127.0.0.1)"
    echo "- Port: 3306"
    echo "- Root User: root (local access only)"
    echo "- Admin User: $ADMIN_USERNAME (alternative admin account)"
    echo "- Socket: /var/run/mysqld/mysqld.sock"
    echo
    echo -e "${BLUE}Common Commands:${NC}"
    echo "- Connect as root:       sudo mysql -u root -p"
    echo "- Connect as admin:      mysql -u $ADMIN_USERNAME -p"
    echo "- Service status:        sudo systemctl status $MARIADB_SERVICE"
    echo "- Service restart:       sudo systemctl restart $MARIADB_SERVICE"
    echo "- Service logs:          sudo journalctl -u $MARIADB_SERVICE"
    echo
    echo -e "${BLUE}Security Notes:${NC}"
    echo "- Anonymous users have been removed"
    echo "- Root remote access has been disabled"
    echo "- Test database has been removed"
    echo "- Root password has been set (local access only)"
    echo "- $ADMIN_USERNAME user created as alternative admin account"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Create additional database users as needed"
    echo "2. Create application databases"
    echo "3. Configure firewall rules if needed"
    echo "4. Set up regular backups"
    echo
}

# Main installation function
main() {
    print_info "Starting MariaDB installation..."
    
    parse_arguments "$@"
    validate_prerequisites
    prompt_root_password
    prompt_admin_user
    update_repository
    install_mariadb
    configure_mariadb
    start_mariadb_service
    secure_mariadb_installation
    create_admin_user
    
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
