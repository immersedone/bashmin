#!/bin/bash
#
# Script: servers/mongodb/install.sh
# Description: Install MongoDB with secure configuration
# Usage: ./install.sh [OPTIONS]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly MONGODB_SERVICE="mongod"
readonly MONGODB_CONFIG_SOURCE="$PROJECT_ROOT/system/etc/mongodb.conf"
readonly MONGODB_CONFIG_TARGET="/etc/mongodb.conf"
readonly MONGODB_DEFAULT_VERSION="7.0"
readonly MONGODB_DATA_DIR="/var/lib/mongodb"
readonly MONGODB_LOG_DIR="/var/log/mongodb"
readonly MONGODB_USER="mongodb"

# Configuration
MONGODB_VERSION=""
ENABLE_AUTH=true
ADMIN_USERNAME="admin"
ADMIN_PASSWORD=""
DATABASE_NAME=""
APP_USERNAME=""
APP_PASSWORD=""
BIND_IP="127.0.0.1"
PORT="27017"
ENABLE_SSL=false
VERBOSE=false
DRY_RUN=false
FORCE_REINSTALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            MONGODB_VERSION="$2"
            shift 2
            ;;
        --no-auth)
            ENABLE_AUTH=false
            shift
            ;;
        --admin-user)
            ADMIN_USERNAME="$2"
            shift 2
            ;;
        --admin-password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --app-db)
            DATABASE_NAME="$2"
            shift 2
            ;;
        --app-user)
            APP_USERNAME="$2"
            shift 2
            ;;
        --app-password)
            APP_PASSWORD="$2"
            shift 2
            ;;
        --bind-ip)
            BIND_IP="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --ssl)
            ENABLE_SSL=true
            shift
            ;;
        --force)
            FORCE_REINSTALL=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Install MongoDB with secure configuration.

OPTIONS:
    --version VERSION       MongoDB version to install (default: $MONGODB_DEFAULT_VERSION)
    --no-auth              Disable authentication (not recommended)
    --admin-user USER      Admin username (default: $ADMIN_USERNAME)
    --admin-password PASS  Admin password (prompted if not provided)
    --app-db DATABASE      Create application database
    --app-user USER        Create application user
    --app-password PASS    Application user password
    --bind-ip IP           Bind IP address (default: $BIND_IP)
    --port PORT            MongoDB port (default: $PORT)
    --ssl                  Enable SSL/TLS (requires certificates)
    --force                Force reinstallation
    --verbose              Enable verbose output
    --dry-run              Show what would be done without executing
    -h, --help             Show this help message

EXAMPLES:
    $0                                      # Basic installation with auth
    $0 --version 6.0                        # Install specific version
    $0 --no-auth                           # Install without authentication
    $0 --app-db myapp --app-user appuser   # Create application database
    $0 --bind-ip 0.0.0.0 --port 27018     # Custom network settings
    $0 --ssl                               # Enable SSL/TLS
    $0 --dry-run --verbose                 # Test installation

NOTES:
    - Requires sudo privileges
    - Authentication is enabled by default for security
    - Admin user is created with full privileges
    - Application users have database-specific permissions
    - SSL requires certificate configuration

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. This is not recommended for security reasons."
    elif ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. Please enter your password when prompted."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges"
            exit 1
        fi
    fi
    
    # Check Ubuntu/Debian system
    if ! command -v apt &> /dev/null; then
        print_error "This script requires apt package manager (Ubuntu/Debian-based systems)"
        exit 1
    fi
    
    # Check if MongoDB is already installed
    if [[ -f "/usr/bin/mongod" && "$FORCE_REINSTALL" == false ]]; then
        local current_version
        current_version=$(/usr/bin/mongod --version | head -1 | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        print_warning "MongoDB is already installed: $current_version"
        if ! confirm_action "Reinstall MongoDB?"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    print_success "Prerequisites check completed"
}

# Function to setup defaults
setup_defaults() {
    # Set default MongoDB version
    if [[ -z "$MONGODB_VERSION" ]]; then
        MONGODB_VERSION="$MONGODB_DEFAULT_VERSION"
    fi
    
    # Prompt for admin password if auth enabled and not provided
    if [[ "$ENABLE_AUTH" == true && -z "$ADMIN_PASSWORD" ]]; then
        while true; do
            read -s -p "Enter admin password: " ADMIN_PASSWORD
            echo
            read -s -p "Confirm admin password: " confirm_password
            echo
            
            if [[ "$ADMIN_PASSWORD" == "$confirm_password" ]]; then
                break
            else
                print_error "Passwords do not match. Please try again."
            fi
        done
        
        if [[ ${#ADMIN_PASSWORD} -lt 8 ]]; then
            print_error "Password must be at least 8 characters long"
            exit 1
        fi
    fi
    
    # Prompt for application database details if specified
    if [[ -n "$DATABASE_NAME" && -z "$APP_USERNAME" ]]; then
        read -p "Enter application username: " APP_USERNAME
    fi
    
    if [[ -n "$APP_USERNAME" && -z "$APP_PASSWORD" ]]; then
        while true; do
            read -s -p "Enter application user password: " APP_PASSWORD
            echo
            read -s -p "Confirm application user password: " confirm_password
            echo
            
            if [[ "$APP_PASSWORD" == "$confirm_password" ]]; then
                break
            else
                print_error "Passwords do not match. Please try again."
            fi
        done
    fi
}

# Function to add MongoDB repository
add_mongodb_repository() {
    print_info "Adding MongoDB repository..."
    
    # Import MongoDB public GPG key
    execute_command "curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg" "Importing MongoDB GPG key"
    
    # Add MongoDB repository
    local ubuntu_codename
    ubuntu_codename=$(lsb_release -cs 2>/dev/null || echo "jammy")
    
    execute_command "echo 'deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu ${ubuntu_codename}/mongodb-org/${MONGODB_VERSION} multiverse' | sudo tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list" "Adding MongoDB repository"
    
    # Update package lists
    execute_command "sudo apt update" "Updating package lists"
    
    print_success "MongoDB repository added successfully"
}

# Function to install MongoDB packages
install_mongodb_packages() {
    print_info "Installing MongoDB packages..."
    
    local packages=(
        "mongodb-org"
        "mongodb-org-database"
        "mongodb-org-server"
        "mongodb-org-mongos"
        "mongodb-org-tools"
    )
    
    # Hold packages to prevent automatic updates
    execute_command "sudo apt install -y ${packages[*]}" "Installing MongoDB packages"
    execute_command "sudo apt-mark hold ${packages[*]}" "Holding MongoDB packages"
    
    print_success "MongoDB packages installed successfully"
}

# Function to create directories and set permissions
setup_directories() {
    print_info "Setting up MongoDB directories..."
    
    local directories=(
        "$MONGODB_DATA_DIR"
        "$MONGODB_LOG_DIR"
        "/etc/mongodb"
    )
    
    for dir in "${directories[@]}"; do
        execute_command "sudo mkdir -p '$dir'" "Creating directory: $dir"
    done
    
    # Set proper ownership
    execute_command "sudo chown -R $MONGODB_USER:$MONGODB_USER '$MONGODB_DATA_DIR'" "Setting data directory ownership"
    execute_command "sudo chown -R $MONGODB_USER:$MONGODB_USER '$MONGODB_LOG_DIR'" "Setting log directory ownership"
    
    # Set proper permissions
    execute_command "sudo chmod 755 '$MONGODB_DATA_DIR'" "Setting data directory permissions"
    execute_command "sudo chmod 755 '$MONGODB_LOG_DIR'" "Setting log directory permissions"
    
    print_success "Directories setup completed"
}

# Function to install configuration
install_configuration() {
    print_info "Installing MongoDB configuration..."
    
    # Create modern YAML configuration
    local config_content="# MongoDB Configuration File
# Network interfaces
net:
  port: $PORT
  bindIp: $BIND_IP

# Storage settings
storage:
  dbPath: $MONGODB_DATA_DIR
  journal:
    enabled: true

# Logging
systemLog:
  destination: file
  logAppend: true
  path: $MONGODB_LOG_DIR/mongod.log
  logRotate: reopen

# Process management
processManagement:
  fork: true
  pidFilePath: /var/run/mongodb/mongod.pid
  timeZoneInfo: /usr/share/zoneinfo

# Security settings"

    if [[ "$ENABLE_AUTH" == true ]]; then
        config_content="$config_content
security:
  authorization: enabled"
    fi

    if [[ "$ENABLE_SSL" == true ]]; then
        config_content="$config_content
  
# SSL/TLS settings
net:
  ssl:
    mode: requireSSL
    PEMKeyFile: /etc/mongodb/ssl/mongodb.pem
    CAFile: /etc/mongodb/ssl/ca.pem"
    fi

    config_content="$config_content

# Operation profiling
operationProfiling:
  slowOpThresholdMs: 100

# Replication (comment out for standalone)
#replication:
#  replSetName: rs0

# Sharding (comment out for standalone)
#sharding:
#  clusterRole: configsvr"
    
    # Write configuration file
    if [[ "$DRY_RUN" == false ]]; then
        echo "$config_content" | sudo tee /etc/mongod.conf > /dev/null
        sudo chown root:root /etc/mongod.conf
        sudo chmod 644 /etc/mongod.conf
        print_success "MongoDB configuration installed"
    else
        echo "[DRY-RUN] Would create /etc/mongod.conf with MongoDB configuration"
    fi
    
    # Also install the legacy configuration for compatibility
    if [[ -f "$MONGODB_CONFIG_SOURCE" ]]; then
        execute_command "sudo cp '$MONGODB_CONFIG_SOURCE' '$MONGODB_CONFIG_TARGET'" "Installing legacy configuration"
        execute_command "sudo chown root:root '$MONGODB_CONFIG_TARGET'" "Setting config file ownership"
        execute_command "sudo chmod 644 '$MONGODB_CONFIG_TARGET'" "Setting config file permissions"
    fi
}

# Function to start and enable MongoDB service
start_mongodb_service() {
    print_info "Starting MongoDB service..."
    
    # Reload systemd
    execute_command "sudo systemctl daemon-reload" "Reloading systemd"
    
    # Enable MongoDB service
    execute_command "sudo systemctl enable $MONGODB_SERVICE" "Enabling MongoDB service"
    
    # Start MongoDB service
    execute_command "sudo systemctl start $MONGODB_SERVICE" "Starting MongoDB service"
    
    # Wait for service to start
    if [[ "$DRY_RUN" == false ]]; then
        print_info "Waiting for MongoDB to start..."
        sleep 5
        
        # Check service status
        if sudo systemctl is-active --quiet $MONGODB_SERVICE; then
            print_success "MongoDB service is running"
        else
            print_error "MongoDB service failed to start"
            print_info "Check logs: sudo journalctl -u $MONGODB_SERVICE -f"
            exit 1
        fi
    fi
}

# Function to setup authentication
setup_authentication() {
    if [[ "$ENABLE_AUTH" == false ]]; then
        print_info "Skipping authentication setup (--no-auth specified)"
        return 0
    fi
    
    print_info "Setting up MongoDB authentication..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create admin user: $ADMIN_USERNAME"
        if [[ -n "$DATABASE_NAME" && -n "$APP_USERNAME" ]]; then
            echo "[DRY-RUN] Would create application user: $APP_USERNAME in database: $DATABASE_NAME"
        fi
        return 0
    fi
    
    # Create admin user
    print_info "Creating admin user..."
    local admin_script="db.getSiblingDB('admin').createUser({
        user: '$ADMIN_USERNAME',
        pwd: '$ADMIN_PASSWORD',
        roles: [
            { role: 'userAdminAnyDatabase', db: 'admin' },
            { role: 'readWriteAnyDatabase', db: 'admin' },
            { role: 'dbAdminAnyDatabase', db: 'admin' },
            { role: 'clusterAdmin', db: 'admin' }
        ]
    })"
    
    if mongosh --eval "$admin_script" > /dev/null 2>&1; then
        print_success "Admin user created successfully"
    else
        print_error "Failed to create admin user"
        exit 1
    fi
    
    # Create application database and user if specified
    if [[ -n "$DATABASE_NAME" && -n "$APP_USERNAME" ]]; then
        print_info "Creating application database and user..."
        
        local app_script="db.getSiblingDB('$DATABASE_NAME').createUser({
            user: '$APP_USERNAME',
            pwd: '$APP_PASSWORD',
            roles: [
                { role: 'readWrite', db: '$DATABASE_NAME' }
            ]
        })"
        
        if mongosh -u "$ADMIN_USERNAME" -p "$ADMIN_PASSWORD" --authenticationDatabase admin --eval "$app_script" > /dev/null 2>&1; then
            print_success "Application user created successfully"
        else
            print_error "Failed to create application user"
            exit 1
        fi
    fi
    
    # Restart MongoDB with authentication enabled
    print_info "Restarting MongoDB with authentication..."
    execute_command "sudo systemctl restart $MONGODB_SERVICE" "Restarting MongoDB service"
    
    # Wait for restart
    sleep 5
    
    # Test authentication
    if mongosh -u "$ADMIN_USERNAME" -p "$ADMIN_PASSWORD" --authenticationDatabase admin --eval "db.runCommand('ping')" > /dev/null 2>&1; then
        print_success "Authentication setup completed successfully"
    else
        print_error "Authentication test failed"
        exit 1
    fi
}

# Function to setup SSL if enabled
setup_ssl() {
    if [[ "$ENABLE_SSL" == false ]]; then
        return 0
    fi
    
    print_info "Setting up SSL/TLS configuration..."
    
    # Create SSL directory
    execute_command "sudo mkdir -p /etc/mongodb/ssl" "Creating SSL directory"
    
    print_warning "SSL is enabled but certificates need to be configured manually"
    print_info "Place your certificates in /etc/mongodb/ssl/"
    print_info "  - mongodb.pem (server certificate and key)"
    print_info "  - ca.pem (certificate authority)"
    
    # Set proper permissions for SSL directory
    execute_command "sudo chown -R $MONGODB_USER:$MONGODB_USER /etc/mongodb/ssl" "Setting SSL directory ownership"
    execute_command "sudo chmod 700 /etc/mongodb/ssl" "Setting SSL directory permissions"
    
    print_info "SSL directory created. Configure certificates and restart MongoDB."
}

# Function to create database backup script
create_backup_script() {
    print_info "Creating database backup script..."
    
    local backup_script="/usr/local/bin/mongodb-backup"
    
    execute_command "sudo tee '$backup_script' > /dev/null" "Creating backup script" <<EOF
#!/bin/bash
#
# MongoDB Backup Script
# Created by MongoDB installation script
#

BACKUP_DIR="/var/backups/mongodb"
DATE=\$(date +"%Y%m%d_%H%M%S")
MONGODB_HOST="$BIND_IP"
MONGODB_PORT="$PORT"

# Create backup directory
mkdir -p "\$BACKUP_DIR"

# Backup command
if [[ "$ENABLE_AUTH" == true ]]; then
    mongodump --host "\$MONGODB_HOST:\$MONGODB_PORT" \\
              --username "$ADMIN_USERNAME" \\
              --password "$ADMIN_PASSWORD" \\
              --authenticationDatabase admin \\
              --out "\$BACKUP_DIR/backup_\$DATE"
else
    mongodump --host "\$MONGODB_HOST:\$MONGODB_PORT" \\
              --out "\$BACKUP_DIR/backup_\$DATE"
fi

# Compress backup
tar -czf "\$BACKUP_DIR/backup_\$DATE.tar.gz" -C "\$BACKUP_DIR" "backup_\$DATE"
rm -rf "\$BACKUP_DIR/backup_\$DATE"

echo "Backup completed: \$BACKUP_DIR/backup_\$DATE.tar.gz"
EOF
    
    execute_command "sudo chmod +x '$backup_script'" "Making backup script executable"
    
    print_success "Backup script created at: $backup_script"
}

# Function to show post-installation instructions
show_post_install_instructions() {
    echo
    print_info "=== MongoDB Installation Complete! ==="
    echo
    
    cat << EOF
MongoDB Configuration:
  Version:         $MONGODB_VERSION
  Service:         $MONGODB_SERVICE
  Config File:     /etc/mongod.conf
  Data Directory:  $MONGODB_DATA_DIR
  Log Directory:   $MONGODB_LOG_DIR
  Bind IP:         $BIND_IP
  Port:           $PORT
  Authentication:  $(if [[ "$ENABLE_AUTH" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
  SSL/TLS:        $(if [[ "$ENABLE_SSL" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)

Service Management:
  sudo systemctl status mongod        # Check service status
  sudo systemctl start mongod         # Start service
  sudo systemctl stop mongod          # Stop service
  sudo systemctl restart mongod       # Restart service

Connection Examples:
EOF

    if [[ "$ENABLE_AUTH" == true ]]; then
        cat << EOF
  # Connect as admin
  mongosh -u $ADMIN_USERNAME -p --authenticationDatabase admin

  # Connect to application database
$(if [[ -n "$DATABASE_NAME" && -n "$APP_USERNAME" ]]; then cat <<EOL
  mongosh -u $APP_USERNAME -p --authenticationDatabase $DATABASE_NAME $DATABASE_NAME
EOL
fi)

  # Connection string format
  mongodb://$ADMIN_USERNAME:PASSWORD@$BIND_IP:$PORT/admin
$(if [[ -n "$DATABASE_NAME" && -n "$APP_USERNAME" ]]; then cat <<EOL
  mongodb://$APP_USERNAME:PASSWORD@$BIND_IP:$PORT/$DATABASE_NAME
EOL
fi)
EOF
    else
        cat << EOF
  # Connect without authentication
  mongosh --host $BIND_IP --port $PORT

  # Connection string format
  mongodb://$BIND_IP:$PORT/
EOF
    fi

    cat << EOF

Backup and Maintenance:
  mongodb-backup                      # Run backup script
  sudo tail -f $MONGODB_LOG_DIR/mongod.log  # View logs
  sudo du -sh $MONGODB_DATA_DIR       # Check database size

Security Notes:
$(if [[ "$ENABLE_AUTH" == false ]]; then cat <<EOL
  ⚠️  Authentication is DISABLED - this is not recommended for production!
  ⚠️  Enable authentication by removing --no-auth and restarting MongoDB
EOL
else cat <<EOL
  ✅ Authentication is enabled
  ✅ Admin user created: $ADMIN_USERNAME
$(if [[ -n "$DATABASE_NAME" && -n "$APP_USERNAME" ]]; then echo "  ✅ Application user created: $APP_USERNAME"; fi)
EOL
fi)
$(if [[ "$BIND_IP" != "127.0.0.1" ]]; then cat <<EOL
  ⚠️  MongoDB is listening on $BIND_IP - ensure firewall is configured
EOL
fi)
$(if [[ "$ENABLE_SSL" == true ]]; then cat <<EOL
  ⚠️  SSL is enabled but certificates need manual configuration
EOL
fi)

Next Steps:
1. Test database connection with the examples above
2. Configure your applications to use MongoDB
3. Set up regular backups with: mongodb-backup
4. Monitor logs and performance
$(if [[ "$ENABLE_SSL" == true ]]; then echo "5. Configure SSL certificates in /etc/mongodb/ssl/"; fi)

EOF
    
    print_success "MongoDB installation completed successfully! 🚀"
}

# Main installation function
main() {
    show_script_header "MongoDB Installation Script"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup defaults
    setup_defaults
    
    # Show installation summary
    print_info "MongoDB will be installed with the following configuration:"
    print_info "  Version: $MONGODB_VERSION"
    print_info "  Authentication: $(if [[ "$ENABLE_AUTH" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    print_info "  Bind IP: $BIND_IP"
    print_info "  Port: $PORT"
    print_info "  SSL: $(if [[ "$ENABLE_SSL" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    if [[ -n "$DATABASE_NAME" ]]; then
        print_info "  Application Database: $DATABASE_NAME"
    fi
    
    if ! confirm_action "Proceed with MongoDB installation?" "Y"; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Installation steps
    add_mongodb_repository
    install_mongodb_packages
    setup_directories
    install_configuration
    start_mongodb_service
    setup_authentication
    setup_ssl
    create_backup_script
    
    # Show post-installation instructions
    show_post_install_instructions
}

# Run main function
main "$@"
