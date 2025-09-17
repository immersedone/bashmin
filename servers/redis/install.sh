#!/bin/bash
#
# Script: servers/redis/install.sh
# Description: Install Redis server with secure configuration
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
readonly REDIS_SERVICE="redis-server"
readonly REDIS_CONFIG_SOURCE="$PROJECT_ROOT/system/etc/redis/redis.conf"
readonly REDIS_CONFIG_TARGET="/etc/redis/redis.conf"
readonly REDIS_DATA_DIR="/var/lib/redis"
readonly REDIS_LOG_DIR="/var/log/redis"
readonly REDIS_USER="redis"
readonly DEFAULT_MEMORY_LIMIT="256mb"

# Configuration
REDIS_VERSION=""
REDIS_PASSWORD=""
BIND_IP="127.0.0.1"
PORT="6379"
MAX_MEMORY=""
ENABLE_PERSISTENCE=true
SAVE_INTERVAL="900 1"
ENABLE_SSL=false
VERBOSE=false
DRY_RUN=false
FORCE_REINSTALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            REDIS_VERSION="$2"
            shift 2
            ;;
        --password)
            REDIS_PASSWORD="$2"
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
        --max-memory)
            MAX_MEMORY="$2"
            shift 2
            ;;
        --no-persistence)
            ENABLE_PERSISTENCE=false
            shift
            ;;
        --save-interval)
            SAVE_INTERVAL="$2"
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

Install Redis server with secure configuration.

OPTIONS:
    --version VERSION       Redis version to install (default: latest from repo)
    --password PASSWORD     Set Redis auth password (prompted if not provided)
    --bind-ip IP           Bind IP address (default: $BIND_IP)
    --port PORT            Redis port (default: $PORT)
    --max-memory SIZE      Maximum memory limit (default: $DEFAULT_MEMORY_LIMIT)
    --no-persistence       Disable data persistence (cache-only mode)
    --save-interval TIME   Save interval "seconds changes" (default: $SAVE_INTERVAL)
    --ssl                  Enable SSL/TLS (requires certificates)
    --force                Force reinstallation
    --verbose              Enable verbose output
    --dry-run              Show what would be done without executing
    -h, --help             Show this help message

EXAMPLES:
    $0                                      # Basic installation with auth
    $0 --password myredispass               # Set specific password
    $0 --max-memory 512mb --port 6380      # Custom memory and port
    $0 --bind-ip 0.0.0.0 --ssl             # Network access with SSL
    $0 --no-persistence                    # Cache-only mode
    $0 --save-interval "300 10"            # Save every 5min if 10+ changes
    $0 --dry-run --verbose                 # Test installation

MEMORY FORMATS:
    256mb, 1gb, 2G, 512MB (case insensitive)

NOTES:
    - Requires sudo privileges
    - Password authentication is strongly recommended
    - Default configuration is secure (localhost only)
    - SSL requires manual certificate configuration

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
    
    # Check if Redis is already installed
    if [[ -f "/usr/bin/redis-server" && "$FORCE_REINSTALL" == false ]]; then
        local current_version
        current_version=$(redis-server --version 2>/dev/null | grep -oP 'v=\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        print_warning "Redis is already installed: $current_version"
        if ! confirm_action "Reinstall Redis?"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    print_success "Prerequisites check completed"
}

# Function to setup defaults
setup_defaults() {
    # Set default memory limit
    if [[ -z "$MAX_MEMORY" ]]; then
        MAX_MEMORY="$DEFAULT_MEMORY_LIMIT"
    fi
    
    # Prompt for Redis password if not provided
    if [[ -z "$REDIS_PASSWORD" ]]; then
        print_info "Redis authentication is strongly recommended for security"
        if confirm_action "Set Redis authentication password?" "Y"; then
            while true; do
                read -s -p "Enter Redis password: " REDIS_PASSWORD
                echo
                read -s -p "Confirm Redis password: " confirm_password
                echo
                
                if [[ "$REDIS_PASSWORD" == "$confirm_password" ]]; then
                    break
                else
                    print_error "Passwords do not match. Please try again."
                fi
            done
            
            if [[ ${#REDIS_PASSWORD} -lt 8 ]]; then
                print_error "Password must be at least 8 characters long"
                exit 1
            fi
        else
            print_warning "Redis will be installed WITHOUT authentication"
            print_warning "This is not recommended for production environments"
        fi
    fi
}

# Function to install Redis packages
install_redis_packages() {
    print_info "Installing Redis packages..."
    
    # Update package lists
    execute_command "sudo apt update" "Updating package lists"
    
    local packages=(
        "redis-server"
        "redis-tools"
    )
    
    # Install specific version if requested
    if [[ -n "$REDIS_VERSION" ]]; then
        execute_command "sudo apt install -y redis-server=$REDIS_VERSION redis-tools=$REDIS_VERSION" "Installing Redis $REDIS_VERSION"
        execute_command "sudo apt-mark hold redis-server redis-tools" "Holding Redis packages"
    else
        execute_command "sudo apt install -y ${packages[*]}" "Installing Redis packages"
    fi
    
    print_success "Redis packages installed successfully"
}

# Function to create directories and set permissions
setup_directories() {
    print_info "Setting up Redis directories..."
    
    local directories=(
        "$REDIS_DATA_DIR"
        "$REDIS_LOG_DIR"
        "/etc/redis/ssl"
    )
    
    for dir in "${directories[@]}"; do
        execute_command "sudo mkdir -p '$dir'" "Creating directory: $dir"
    done
    
    # Set proper ownership
    execute_command "sudo chown -R $REDIS_USER:$REDIS_USER '$REDIS_DATA_DIR'" "Setting data directory ownership"
    execute_command "sudo chown -R $REDIS_USER:$REDIS_USER '$REDIS_LOG_DIR'" "Setting log directory ownership"
    
    # Set proper permissions
    execute_command "sudo chmod 750 '$REDIS_DATA_DIR'" "Setting data directory permissions"
    execute_command "sudo chmod 750 '$REDIS_LOG_DIR'" "Setting log directory permissions"
    execute_command "sudo chmod 700 '/etc/redis/ssl'" "Setting SSL directory permissions"
    
    print_success "Directories setup completed"
}

# Function to generate secure Redis configuration
generate_redis_config() {
    print_info "Generating Redis configuration..."
    
    local temp_config="/tmp/redis.conf.$$"
    
    # Start with base configuration if available
    if [[ -f "$REDIS_CONFIG_SOURCE" ]]; then
        execute_command "cp '$REDIS_CONFIG_SOURCE' '$temp_config'" "Copying base configuration"
    else
        # Create minimal configuration
        cat > "$temp_config" << 'EOF'
# Redis Configuration - Generated by installation script
################################## NETWORK #####################################
EOF
    fi
    
    # Apply custom configurations
    if [[ "$DRY_RUN" == false ]]; then
        # Network settings
        sed -i "s/^bind .*/bind $BIND_IP/" "$temp_config"
        sed -i "s/^port .*/port $PORT/" "$temp_config"
        
        # Security settings
        if [[ -n "$REDIS_PASSWORD" ]]; then
            sed -i "s/^# requirepass .*/requirepass $REDIS_PASSWORD/" "$temp_config"
            echo "requirepass $REDIS_PASSWORD" >> "$temp_config"
        fi
        
        # Memory settings
        echo "" >> "$temp_config"
        echo "# Memory Management" >> "$temp_config"
        echo "maxmemory $MAX_MEMORY" >> "$temp_config"
        echo "maxmemory-policy allkeys-lru" >> "$temp_config"
        
        # Persistence settings
        if [[ "$ENABLE_PERSISTENCE" == true ]]; then
            echo "" >> "$temp_config"
            echo "# Persistence" >> "$temp_config"
            echo "save $SAVE_INTERVAL" >> "$temp_config"
            echo "dir $REDIS_DATA_DIR" >> "$temp_config"
            echo "dbfilename dump.rdb" >> "$temp_config"
        else
            echo "" >> "$temp_config"
            echo "# Persistence disabled" >> "$temp_config"
            echo "save \"\"" >> "$temp_config"
        fi
        
        # Logging settings
        echo "" >> "$temp_config"
        echo "# Logging" >> "$temp_config"
        echo "logfile $REDIS_LOG_DIR/redis-server.log" >> "$temp_config"
        echo "loglevel notice" >> "$temp_config"
        
        # Security enhancements
        echo "" >> "$temp_config"
        echo "# Security" >> "$temp_config"
        echo "protected-mode yes" >> "$temp_config"
        echo "tcp-keepalive 300" >> "$temp_config"
        echo "timeout 0" >> "$temp_config"
        
        # Performance settings
        echo "" >> "$temp_config"
        echo "# Performance" >> "$temp_config"
        echo "tcp-backlog 511" >> "$temp_config"
        echo "databases 16" >> "$temp_config"
        
        # SSL/TLS settings if enabled
        if [[ "$ENABLE_SSL" == true ]]; then
            echo "" >> "$temp_config"
            echo "# SSL/TLS" >> "$temp_config"
            echo "tls-port $PORT" >> "$temp_config"
            echo "port 0" >> "$temp_config"
            echo "tls-cert-file /etc/redis/ssl/redis.crt" >> "$temp_config"
            echo "tls-key-file /etc/redis/ssl/redis.key" >> "$temp_config"
            echo "tls-ca-cert-file /etc/redis/ssl/ca.crt" >> "$temp_config"
        fi
        
        # Install the configuration
        execute_command "sudo mv '$temp_config' '$REDIS_CONFIG_TARGET'" "Installing Redis configuration"
        execute_command "sudo chown root:$REDIS_USER '$REDIS_CONFIG_TARGET'" "Setting config file ownership"
        execute_command "sudo chmod 640 '$REDIS_CONFIG_TARGET'" "Setting config file permissions"
    else
        echo "[DRY-RUN] Would generate Redis configuration with:"
        echo "  Bind IP: $BIND_IP"
        echo "  Port: $PORT"
        echo "  Max Memory: $MAX_MEMORY"
        echo "  Authentication: $(if [[ -n "$REDIS_PASSWORD" ]]; then echo "Enabled"; else echo "Disabled"; fi)"
        echo "  Persistence: $(if [[ "$ENABLE_PERSISTENCE" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
        echo "  SSL: $(if [[ "$ENABLE_SSL" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
        rm -f "$temp_config"
    fi
    
    print_success "Redis configuration generated"
}

# Function to start and enable Redis service
start_redis_service() {
    print_info "Starting Redis service..."
    
    # Stop service if running
    execute_command "sudo systemctl stop $REDIS_SERVICE" "Stopping Redis service" || true
    
    # Reload systemd
    execute_command "sudo systemctl daemon-reload" "Reloading systemd"
    
    # Enable Redis service
    execute_command "sudo systemctl enable $REDIS_SERVICE" "Enabling Redis service"
    
    # Start Redis service
    execute_command "sudo systemctl start $REDIS_SERVICE" "Starting Redis service"
    
    # Wait for service to start
    if [[ "$DRY_RUN" == false ]]; then
        print_info "Waiting for Redis to start..."
        sleep 3
        
        # Check service status
        if sudo systemctl is-active --quiet $REDIS_SERVICE; then
            print_success "Redis service is running"
        else
            print_error "Redis service failed to start"
            print_info "Check logs: sudo journalctl -u $REDIS_SERVICE -f"
            exit 1
        fi
    fi
}

# Function to test Redis installation
test_redis_installation() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test Redis connection"
        return 0
    fi
    
    print_info "Testing Redis installation..."
    
    # Test basic connection
    local redis_cmd="redis-cli -h $BIND_IP -p $PORT"
    
    # Add auth if password is set
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis_cmd="$redis_cmd -a $REDIS_PASSWORD"
    fi
    
    # Test ping command
    if $redis_cmd ping | grep -q "PONG"; then
        print_success "Redis connection test passed"
        
        # Test set/get operations
        if $redis_cmd set test_key "installation_test" | grep -q "OK"; then
            if [[ "$($redis_cmd get test_key)" == "installation_test" ]]; then
                print_success "Redis read/write test passed"
                $redis_cmd del test_key > /dev/null
            else
                print_warning "Redis read test failed"
            fi
        else
            print_warning "Redis write test failed"
        fi
    else
        print_error "Redis connection test failed"
        print_info "Check service status: sudo systemctl status $REDIS_SERVICE"
        exit 1
    fi
}

# Function to setup SSL if enabled
setup_ssl() {
    if [[ "$ENABLE_SSL" == false ]]; then
        return 0
    fi
    
    print_info "Setting up SSL/TLS configuration..."
    
    print_warning "SSL is enabled but certificates need to be configured manually"
    print_info "Place your certificates in /etc/redis/ssl/"
    print_info "  - redis.crt (server certificate)"
    print_info "  - redis.key (private key)"
    print_info "  - ca.crt (certificate authority)"
    
    # Set proper permissions for SSL directory
    execute_command "sudo chown -R root:$REDIS_USER /etc/redis/ssl" "Setting SSL directory ownership"
    execute_command "sudo chmod 750 /etc/redis/ssl" "Setting SSL directory permissions"
    
    print_info "SSL directory created. Configure certificates and restart Redis."
}

# Function to create Redis management script
create_redis_scripts() {
    print_info "Creating Redis management scripts..."
    
    # Create backup script
    local backup_script="/usr/local/bin/redis-backup"
    
    execute_command "sudo tee '$backup_script' > /dev/null" "Creating backup script" <<EOF
#!/bin/bash
#
# Redis Backup Script
# Created by Redis installation script
#

BACKUP_DIR="/var/backups/redis"
DATE=\$(date +"%Y%m%d_%H%M%S")
REDIS_HOST="$BIND_IP"
REDIS_PORT="$PORT"

# Create backup directory
mkdir -p "\$BACKUP_DIR"

# Backup command
if [[ -n "$REDIS_PASSWORD" ]]; then
    REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h "\$REDIS_HOST" -p "\$REDIS_PORT" --rdb "\$BACKUP_DIR/redis_backup_\$DATE.rdb"
else
    redis-cli -h "\$REDIS_HOST" -p "\$REDIS_PORT" --rdb "\$BACKUP_DIR/redis_backup_\$DATE.rdb"
fi

# Compress backup
gzip "\$BACKUP_DIR/redis_backup_\$DATE.rdb"

echo "Backup completed: \$BACKUP_DIR/redis_backup_\$DATE.rdb.gz"
EOF
    
    execute_command "sudo chmod +x '$backup_script'" "Making backup script executable"
    
    # Create monitoring script
    local monitor_script="/usr/local/bin/redis-monitor"
    
    execute_command "sudo tee '$monitor_script' > /dev/null" "Creating monitoring script" <<EOF
#!/bin/bash
#
# Redis Monitoring Script
# Created by Redis installation script
#

REDIS_HOST="$BIND_IP"
REDIS_PORT="$PORT"

# Connection command
REDIS_CMD="redis-cli -h \$REDIS_HOST -p \$REDIS_PORT"
if [[ -n "$REDIS_PASSWORD" ]]; then
    REDIS_CMD="REDISCLI_AUTH='$REDIS_PASSWORD' \$REDIS_CMD"
fi

echo "Redis Server Information:"
echo "========================="
eval "\$REDIS_CMD info server | grep -E '^redis_version|^uptime_in_seconds|^process_id'"

echo ""
echo "Memory Usage:"
echo "============="
eval "\$REDIS_CMD info memory | grep -E '^used_memory_human|^used_memory_peak_human|^maxmemory_human'"

echo ""
echo "Connected Clients:"
echo "=================="
eval "\$REDIS_CMD info clients | grep connected_clients"

echo ""
echo "Keyspace:"
echo "=========="
eval "\$REDIS_CMD info keyspace"
EOF
    
    execute_command "sudo chmod +x '$monitor_script'" "Making monitoring script executable"
    
    print_success "Management scripts created"
}

# Function to show post-installation instructions
show_post_install_instructions() {
    echo
    print_info "=== Redis Installation Complete! ==="
    echo
    
    cat << EOF
Redis Configuration:
  Service:         $REDIS_SERVICE
  Config File:     $REDIS_CONFIG_TARGET
  Data Directory:  $REDIS_DATA_DIR
  Log Directory:   $REDIS_LOG_DIR
  Bind IP:         $BIND_IP
  Port:           $PORT
  Max Memory:     $MAX_MEMORY
  Authentication:  $(if [[ -n "$REDIS_PASSWORD" ]]; then echo "Enabled"; else echo "Disabled"; fi)
  Persistence:    $(if [[ "$ENABLE_PERSISTENCE" == true ]]; then echo "Enabled"; else echo "Cache-only"; fi)
  SSL/TLS:        $(if [[ "$ENABLE_SSL" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)

Service Management:
  sudo systemctl status redis-server     # Check service status
  sudo systemctl start redis-server      # Start service
  sudo systemctl stop redis-server       # Stop service
  sudo systemctl restart redis-server    # Restart service

Connection Examples:
EOF

    if [[ -n "$REDIS_PASSWORD" ]]; then
        cat << EOF
  # Command line with auth
  redis-cli -h $BIND_IP -p $PORT -a $REDIS_PASSWORD

  # Environment variable auth
  REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h $BIND_IP -p $PORT

  # Connection string format
  redis://:$REDIS_PASSWORD@$BIND_IP:$PORT/0
EOF
    else
        cat << EOF
  # Command line without auth
  redis-cli -h $BIND_IP -p $PORT

  # Connection string format
  redis://$BIND_IP:$PORT/0
EOF
    fi

    cat << EOF

Management Scripts:
  redis-backup                        # Create database backup
  redis-monitor                       # Show server information
  redis-cli monitor                   # Monitor commands in real-time
  redis-cli --latency                 # Monitor latency

Common Commands:
  redis-cli ping                      # Test connection
  redis-cli info                      # Server information
  redis-cli config get "*"            # Show all configuration
  redis-cli dbsize                    # Number of keys
  redis-cli flushall                  # Clear all data (careful!)

Performance Testing:
  redis-benchmark -h $BIND_IP -p $PORT $(if [[ -n "$REDIS_PASSWORD" ]]; then echo "-a $REDIS_PASSWORD"; fi) # Benchmark performance

Logs and Monitoring:
  sudo tail -f $REDIS_LOG_DIR/redis-server.log    # View Redis logs
  sudo journalctl -u redis-server -f              # View service logs

Security Notes:
$(if [[ -n "$REDIS_PASSWORD" ]]; then cat <<EOL
  ✅ Authentication is enabled
  ✅ Password protection active
EOL
else cat <<EOL
  ⚠️  Authentication is DISABLED - not recommended for production!
  ⚠️  Set password with: redis-cli config set requirepass yourpassword
EOL
fi)
$(if [[ "$BIND_IP" != "127.0.0.1" ]]; then cat <<EOL
  ⚠️  Redis is listening on $BIND_IP - ensure firewall is configured
EOL
fi)
$(if [[ "$ENABLE_SSL" == true ]]; then cat <<EOL
  ⚠️  SSL is enabled but certificates need manual configuration
EOL
fi)

Next Steps:
1. Test Redis connection with the examples above
2. Configure your applications to use Redis
3. Set up regular backups with: redis-backup
4. Monitor performance and memory usage
$(if [[ "$ENABLE_SSL" == true ]]; then echo "5. Configure SSL certificates in /etc/redis/ssl/"; fi)

EOF
    
    print_success "Redis installation completed successfully! 🚀"
}

# Main installation function
main() {
    show_script_header "Redis Installation Script"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup defaults
    setup_defaults
    
    # Show installation summary
    print_info "Redis will be installed with the following configuration:"
    print_info "  Bind IP: $BIND_IP"
    print_info "  Port: $PORT"
    print_info "  Max Memory: $MAX_MEMORY"
    print_info "  Authentication: $(if [[ -n "$REDIS_PASSWORD" ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    print_info "  Persistence: $(if [[ "$ENABLE_PERSISTENCE" == true ]]; then echo "Enabled"; else echo "Cache-only"; fi)"
    print_info "  SSL: $(if [[ "$ENABLE_SSL" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    
    if ! confirm_action "Proceed with Redis installation?" "Y"; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Installation steps
    install_redis_packages
    setup_directories
    generate_redis_config
    start_redis_service
    test_redis_installation
    setup_ssl
    create_redis_scripts
    
    # Show post-installation instructions
    show_post_install_instructions
}

# Run main function
main "$@"