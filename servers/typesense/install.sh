#!/bin/bash
#
# Script: servers/typesense/install.sh
# Description: Install Typesense server with secure configuration
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
readonly TYPESENSE_SERVICE="typesense-server"
readonly TYPESENSE_CONFIG_DIR="/etc/typesense"
readonly TYPESENSE_CONFIG_FILE="$TYPESENSE_CONFIG_DIR/typesense-server.ini"
readonly TYPESENSE_DATA_DIR="/var/lib/typesense"
readonly TYPESENSE_LOG_DIR="/var/log/typesense"
readonly TYPESENSE_USER="typesense"
readonly TYPESENSE_BINARY_DIR="/usr/share/typesense"
readonly DEFAULT_PORT="8108"
readonly DEFAULT_PEERING_PORT="8107"

# Configuration
TYPESENSE_VERSION="29.0"
TYPESENSE_API_KEY=""
BIND_ADDRESS="127.0.0.1"
API_PORT="$DEFAULT_PORT"
PEERING_PORT="$DEFAULT_PEERING_PORT"
ENABLE_CORS=false
CORS_DOMAINS=""
ENABLE_SSL=false
SSL_CERT_PATH=""
SSL_KEY_PATH=""
ENABLE_ANALYTICS=false
ANALYTICS_DIR="/var/lib/typesense/analytics"
INSTALL_METHOD="deb"
ARCHITECTURE=""
VERBOSE=false
DRY_RUN=false
FORCE_REINSTALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            TYPESENSE_VERSION="$2"
            shift 2
            ;;
        --api-key)
            TYPESENSE_API_KEY="$2"
            shift 2
            ;;
        --bind-address)
            BIND_ADDRESS="$2"
            shift 2
            ;;
        --api-port)
            API_PORT="$2"
            shift 2
            ;;
        --peering-port)
            PEERING_PORT="$2"
            shift 2
            ;;
        --enable-cors)
            ENABLE_CORS=true
            shift
            ;;
        --cors-domains)
            CORS_DOMAINS="$2"
            ENABLE_CORS=true
            shift 2
            ;;
        --ssl-cert)
            SSL_CERT_PATH="$2"
            ENABLE_SSL=true
            shift 2
            ;;
        --ssl-key)
            SSL_KEY_PATH="$2"
            ENABLE_SSL=true
            shift 2
            ;;
        --enable-analytics)
            ENABLE_ANALYTICS=true
            shift
            ;;
        --analytics-dir)
            ANALYTICS_DIR="$2"
            ENABLE_ANALYTICS=true
            shift 2
            ;;
        --method)
            INSTALL_METHOD="$2"
            shift 2
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

Install Typesense server with secure configuration.

OPTIONS:
    --version VERSION       Typesense version to install (default: $TYPESENSE_VERSION)
    --api-key KEY          Set admin API key (prompted if not provided)
    --bind-address IP      Bind IP address (default: $BIND_ADDRESS)
    --api-port PORT        API port (default: $API_PORT)
    --peering-port PORT    Peering port for clustering (default: $PEERING_PORT)
    --enable-cors          Enable CORS support
    --cors-domains DOMAINS Comma-separated CORS domains
    --ssl-cert PATH        SSL certificate file path
    --ssl-key PATH         SSL private key file path
    --enable-analytics     Enable search analytics
    --analytics-dir DIR    Analytics data directory (default: $ANALYTICS_DIR)
    --method METHOD        Installation method: deb, binary (default: $INSTALL_METHOD)
    --force                Force reinstallation
    --verbose              Enable verbose output
    --dry-run              Show what would be done without executing
    -h, --help             Show this help message

EXAMPLES:
    $0                                      # Basic installation with prompts
    $0 --api-key mykey123                   # Set specific API key
    $0 --bind-address 0.0.0.0 --enable-cors # Network access with CORS
    $0 --ssl-cert /path/cert --ssl-key /path/key # Enable SSL
    $0 --enable-analytics                   # Enable search analytics
    $0 --method binary                      # Install from binary
    $0 --dry-run --verbose                  # Test installation

INSTALL METHODS:
    deb      - Install DEB package (recommended for Ubuntu/Debian)
    binary   - Download and install from binary archive

NOTES:
    - Requires sudo privileges
    - API key authentication is required
    - Default configuration is secure (localhost only)
    - SSL requires valid certificate files
    - Data stored in: $TYPESENSE_DATA_DIR
    - Logs stored in: $TYPESENSE_LOG_DIR
    - Config stored in: $TYPESENSE_CONFIG_FILE

EOF
}

# Function to detect system architecture
detect_architecture() {
    local arch
    arch=$(uname -m)
    
    case $arch in
        x86_64)
            ARCHITECTURE="amd64"
            ;;
        aarch64|arm64)
            ARCHITECTURE="arm64"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            print_info "Supported architectures: x86_64, aarch64/arm64"
            exit 1
            ;;
    esac
    
    if [[ "$VERBOSE" == true ]]; then
        print_info "Detected architecture: $ARCHITECTURE"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. This is not recommended for security reasons."
    elif ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        exit 1
    fi
    
    # Check Ubuntu/Debian system
    if ! command -v apt &> /dev/null; then
        print_error "This script requires apt package manager (Ubuntu/Debian-based systems)"
        exit 1
    fi
    
    # Check Ubuntu version for compatibility
    local ubuntu_version
    if [[ -f /etc/os-release ]]; then
        ubuntu_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2 | cut -d'.' -f1)
        if [[ "$ubuntu_version" -lt 20 ]]; then
            print_error "Typesense v26.0+ requires Ubuntu 20 or later"
            print_info "Current Ubuntu version: $ubuntu_version"
            exit 1
        fi
    fi
    
    # Check if Typesense is already installed
    if [[ -f "/usr/bin/typesense-server" && "$FORCE_REINSTALL" == false ]]; then
        local current_version
        current_version=$(typesense-server --version 2>/dev/null | head -n1 || echo "unknown")
        print_warning "Typesense is already installed: $current_version"
        if ! confirm_action "Reinstall Typesense?"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Detect architecture
    detect_architecture
    
    print_success "Prerequisites check completed"
}

# Function to setup defaults
setup_defaults() {
    # Generate secure API key if not provided
    if [[ -z "$TYPESENSE_API_KEY" ]]; then
        print_info "Typesense requires an admin API key for security"
        if confirm_action "Generate secure API key automatically?" "Y"; then
            TYPESENSE_API_KEY=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
            print_info "Generated secure API key: $TYPESENSE_API_KEY"
            print_warning "Save this API key securely - you'll need it to access Typesense"
        else
            while true; do
                read -s -p "Enter Typesense admin API key: " TYPESENSE_API_KEY
                echo
                
                if [[ ${#TYPESENSE_API_KEY} -lt 16 ]]; then
                    print_error "API key must be at least 16 characters long"
                    continue
                fi
                
                read -s -p "Confirm API key: " confirm_key
                echo
                
                if [[ "$TYPESENSE_API_KEY" == "$confirm_key" ]]; then
                    break
                else
                    print_error "API keys do not match. Please try again."
                fi
            done
        fi
    fi
    
    # Validate SSL configuration
    if [[ "$ENABLE_SSL" == true ]]; then
        if [[ -z "$SSL_CERT_PATH" || -z "$SSL_KEY_PATH" ]]; then
            print_error "SSL enabled but certificate or key path not provided"
            print_info "Use --ssl-cert and --ssl-key options"
            exit 1
        fi
        
        if [[ ! -f "$SSL_CERT_PATH" ]]; then
            print_error "SSL certificate file not found: $SSL_CERT_PATH"
            exit 1
        fi
        
        if [[ ! -f "$SSL_KEY_PATH" ]]; then
            print_error "SSL key file not found: $SSL_KEY_PATH"
            exit 1
        fi
    fi
}

# Function to create system user
create_typesense_user() {
    print_info "Creating Typesense system user..."
    
    if ! id "$TYPESENSE_USER" &>/dev/null; then
        execute_command "sudo useradd --system --shell /bin/false --home $TYPESENSE_DATA_DIR --create-home $TYPESENSE_USER" "Creating system user: $TYPESENSE_USER"
    else
        print_info "User $TYPESENSE_USER already exists"
    fi
}

# Function to create directories
setup_directories() {
    print_info "Setting up Typesense directories..."
    
    local directories=(
        "$TYPESENSE_CONFIG_DIR"
        "$TYPESENSE_DATA_DIR"
        "$TYPESENSE_LOG_DIR"
        "$TYPESENSE_BINARY_DIR"
        "$ANALYTICS_DIR"
    )
    
    for dir in "${directories[@]}"; do
        execute_command "sudo mkdir -p '$dir'" "Creating directory: $dir"
    done
    
    # Set proper ownership
    execute_command "sudo chown -R $TYPESENSE_USER:$TYPESENSE_USER '$TYPESENSE_DATA_DIR'" "Setting data directory ownership"
    execute_command "sudo chown -R $TYPESENSE_USER:$TYPESENSE_USER '$TYPESENSE_LOG_DIR'" "Setting log directory ownership"
    
    if [[ "$ENABLE_ANALYTICS" == true ]]; then
        execute_command "sudo chown -R $TYPESENSE_USER:$TYPESENSE_USER '$ANALYTICS_DIR'" "Setting analytics directory ownership"
    fi
    
    # Set proper permissions
    execute_command "sudo chmod 755 '$TYPESENSE_CONFIG_DIR'" "Setting config directory permissions"
    execute_command "sudo chmod 750 '$TYPESENSE_DATA_DIR'" "Setting data directory permissions"
    execute_command "sudo chmod 750 '$TYPESENSE_LOG_DIR'" "Setting log directory permissions"
    
    print_success "Directories setup completed"
}

# Function to install via DEB package
install_via_deb() {
    print_info "Installing Typesense via DEB package..."
    
    local deb_url="https://dl.typesense.org/releases/${TYPESENSE_VERSION}/typesense-server-${TYPESENSE_VERSION}-${ARCHITECTURE}.deb"
    local deb_file="/tmp/typesense-server-${TYPESENSE_VERSION}-${ARCHITECTURE}.deb"
    
    # Download DEB package
    execute_command "curl -L -o '$deb_file' '$deb_url'" "Downloading Typesense DEB package"
    
    # Install package
    execute_command "sudo apt install -y '$deb_file'" "Installing Typesense DEB package"
    
    # Cleanup
    execute_command "rm -f '$deb_file'" "Cleaning up downloaded package"
    
    print_success "Typesense DEB package installed"
}

# Function to install via binary
install_via_binary() {
    print_info "Installing Typesense via binary..."
    
    local binary_url="https://dl.typesense.org/releases/${TYPESENSE_VERSION}/typesense-server-${TYPESENSE_VERSION}-linux-${ARCHITECTURE}.tar.gz"
    local binary_archive="/tmp/typesense-server-${TYPESENSE_VERSION}-linux-${ARCHITECTURE}.tar.gz"
    local extract_dir="/tmp/typesense-${TYPESENSE_VERSION}"
    
    # Download binary
    execute_command "curl -L -o '$binary_archive' '$binary_url'" "Downloading Typesense binary"
    
    # Extract binary
    execute_command "mkdir -p '$extract_dir'" "Creating extract directory"
    execute_command "tar -xzf '$binary_archive' -C '$extract_dir'" "Extracting Typesense binary"
    
    # Install binary
    execute_command "sudo cp '$extract_dir/typesense-server' '/usr/bin/typesense-server'" "Installing Typesense binary"
    execute_command "sudo chmod +x '/usr/bin/typesense-server'" "Making binary executable"
    
    # Copy additional files to shared directory
    execute_command "sudo cp -r '$extract_dir'/* '$TYPESENSE_BINARY_DIR/'" "Copying files to shared directory"
    
    # Cleanup
    execute_command "rm -rf '$binary_archive' '$extract_dir'" "Cleaning up temporary files"
    
    print_success "Typesense binary installed"
}

# Function to install Typesense
install_typesense() {
    print_info "Installing Typesense server..."
    
    # Update package lists
    execute_command "sudo apt update" "Updating package lists"
    
    # Install dependencies
    local dependencies=(
        "curl"
        "openssl"
    )
    
    execute_command "sudo apt install -y ${dependencies[*]}" "Installing dependencies"
    
    # Install based on method
    case "$INSTALL_METHOD" in
        "deb")
            install_via_deb
            ;;
        "binary")
            install_via_binary
            ;;
        *)
            print_error "Unknown installation method: $INSTALL_METHOD"
            exit 1
            ;;
    esac
    
    print_success "Typesense installation completed"
}

# Function to generate configuration file
generate_config_file() {
    print_info "Generating Typesense configuration..."
    
    local temp_config="/tmp/typesense-server.ini.$$"
    
    # Generate configuration
    if [[ "$DRY_RUN" == false ]]; then
        cat > "$temp_config" << EOF
; Typesense Server Configuration
; Generated by installation script on $(date)

[server]

; Authentication
api-key = $TYPESENSE_API_KEY

; Data and logging
data-dir = $TYPESENSE_DATA_DIR
log-dir = $TYPESENSE_LOG_DIR

; Networking
api-address = $BIND_ADDRESS
api-port = $API_PORT
peering-port = $PEERING_PORT

; Security
$(if [[ "$ENABLE_CORS" == true ]]; then
    echo "enable-cors = true"
    if [[ -n "$CORS_DOMAINS" ]]; then
        echo "cors-domains = $CORS_DOMAINS"
    fi
fi)

$(if [[ "$ENABLE_SSL" == true ]]; then
    cat << SSL_CONFIG
; SSL/TLS Configuration
ssl-certificate = $SSL_CERT_PATH
ssl-certificate-key = $SSL_KEY_PATH
ssl-refresh-interval-seconds = 28800
SSL_CONFIG
fi)

; Analytics
$(if [[ "$ENABLE_ANALYTICS" == true ]]; then
    cat << ANALYTICS_CONFIG
enable-search-analytics = true
analytics-dir = $ANALYTICS_DIR
analytics-flush-interval = 3600
analytics-minute-rate-limit = 10
ANALYTICS_CONFIG
fi)

; Performance and resource usage
thread-pool-size = $(nproc --all)
cache-num-entries = 2000
embedding-cache-num-entries = 1000
disk-used-max-percentage = 95
memory-used-max-percentage = 95

; Search limits
max-per-page = 250
filter-by-max-ops = 200

; Logging
enable-access-logging = true
enable-search-logging = false
log-slow-requests-time-ms = 1000

; Database
snapshot-interval-seconds = 3600
db-compaction-interval = 604800

EOF
        
        # Install the configuration
        execute_command "sudo mv '$temp_config' '$TYPESENSE_CONFIG_FILE'" "Installing configuration file"
        execute_command "sudo chown root:$TYPESENSE_USER '$TYPESENSE_CONFIG_FILE'" "Setting config file ownership"
        execute_command "sudo chmod 640 '$TYPESENSE_CONFIG_FILE'" "Setting config file permissions"
    else
        echo "[DRY-RUN] Would generate Typesense configuration with:"
        echo "  API Key: [HIDDEN]"
        echo "  Bind Address: $BIND_ADDRESS"
        echo "  API Port: $API_PORT"
        echo "  CORS: $(if [[ "$ENABLE_CORS" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
        echo "  SSL: $(if [[ "$ENABLE_SSL" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
        echo "  Analytics: $(if [[ "$ENABLE_ANALYTICS" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
        rm -f "$temp_config"
    fi
    
    print_success "Configuration file generated"
}

# Function to create systemd service
create_systemd_service() {
    print_info "Creating systemd service..."
    
    local service_file="/etc/systemd/system/$TYPESENSE_SERVICE.service"
    
    execute_command "sudo tee '$service_file' > /dev/null" "Creating systemd service file" <<EOF
[Unit]
Description=Typesense Search Server
Documentation=https://typesense.org/docs/
After=network.target
Wants=network.target

[Service]
Type=exec
User=$TYPESENSE_USER
Group=$TYPESENSE_USER
ExecStart=/usr/bin/typesense-server --config=$TYPESENSE_CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillMode=process
KillSignal=SIGTERM

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$TYPESENSE_DATA_DIR $TYPESENSE_LOG_DIR $(if [[ "$ENABLE_ANALYTICS" == true ]]; then echo "$ANALYTICS_DIR"; fi)

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Environment
Environment=TYPESENSE_CONFIG=$TYPESENSE_CONFIG_FILE

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    execute_command "sudo systemctl daemon-reload" "Reloading systemd"
    
    print_success "Systemd service created"
}

# Function to start Typesense service
start_typesense_service() {
    print_info "Starting Typesense service..."
    
    # Enable service
    execute_command "sudo systemctl enable $TYPESENSE_SERVICE" "Enabling Typesense service"
    
    # Start service
    execute_command "sudo systemctl start $TYPESENSE_SERVICE" "Starting Typesense service"
    
    # Wait for service to start
    if [[ "$DRY_RUN" == false ]]; then
        print_info "Waiting for Typesense to start..."
        sleep 5
        
        # Check service status
        if sudo systemctl is-active --quiet $TYPESENSE_SERVICE; then
            print_success "Typesense service is running"
        else
            print_error "Typesense service failed to start"
            print_info "Check logs: sudo journalctl -u $TYPESENSE_SERVICE -f"
            print_info "Check status: sudo systemctl status $TYPESENSE_SERVICE"
            exit 1
        fi
    fi
}

# Function to test Typesense installation
test_typesense_installation() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test Typesense API connection"
        return 0
    fi
    
    print_info "Testing Typesense installation..."
    
    local base_url="http://$BIND_ADDRESS:$API_PORT"
    if [[ "$ENABLE_SSL" == true ]]; then
        base_url="https://$BIND_ADDRESS:$API_PORT"
    fi
    
    # Test health endpoint
    if curl -s -H "X-TYPESENSE-API-KEY: $TYPESENSE_API_KEY" "$base_url/health" | grep -q '"ok":true'; then
        print_success "Typesense health check passed"
        
        # Test debug endpoint for version
        local version_info
        version_info=$(curl -s -H "X-TYPESENSE-API-KEY: $TYPESENSE_API_KEY" "$base_url/debug" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        print_success "Typesense version: $version_info"
        
        # Test collections endpoint
        if curl -s -H "X-TYPESENSE-API-KEY: $TYPESENSE_API_KEY" "$base_url/collections" > /dev/null; then
            print_success "Typesense API test passed"
        else
            print_warning "Typesense API collections test failed"
        fi
    else
        print_error "Typesense health check failed"
        print_info "Check service status: sudo systemctl status $TYPESENSE_SERVICE"
        print_info "Check logs: sudo journalctl -u $TYPESENSE_SERVICE -f"
        exit 1
    fi
}

# Function to create management scripts
create_management_scripts() {
    print_info "Creating Typesense management scripts..."
    
    # Create backup script
    local backup_script="/usr/local/bin/typesense-backup"
    
    execute_command "sudo tee '$backup_script' > /dev/null" "Creating backup script" <<EOF
#!/bin/bash
#
# Typesense Backup Script
# Created by Typesense installation script
#

BACKUP_DIR="/var/backups/typesense"
DATE=\$(date +"%Y%m%d_%H%M%S")
DATA_DIR="$TYPESENSE_DATA_DIR"
CONFIG_FILE="$TYPESENSE_CONFIG_FILE"

# Create backup directory
mkdir -p "\$BACKUP_DIR"

# Backup data directory
echo "Backing up Typesense data..."
tar -czf "\$BACKUP_DIR/typesense_data_\$DATE.tar.gz" -C "\$(dirname "\$DATA_DIR")" "\$(basename "\$DATA_DIR")"

# Backup configuration
echo "Backing up Typesense configuration..."
cp "\$CONFIG_FILE" "\$BACKUP_DIR/typesense-server_\$DATE.ini"

echo "Backup completed:"
echo "  Data: \$BACKUP_DIR/typesense_data_\$DATE.tar.gz"
echo "  Config: \$BACKUP_DIR/typesense-server_\$DATE.ini"
EOF
    
    execute_command "sudo chmod +x '$backup_script'" "Making backup script executable"
    
    # Create status script
    local status_script="/usr/local/bin/typesense-status"
    
    execute_command "sudo tee '$status_script' > /dev/null" "Creating status script" <<EOF
#!/bin/bash
#
# Typesense Status Script
# Created by Typesense installation script
#

BASE_URL="http://$BIND_ADDRESS:$API_PORT"
if [[ "$ENABLE_SSL" == true ]]; then
    BASE_URL="https://$BIND_ADDRESS:$API_PORT"
fi

echo "Typesense Server Status:"
echo "========================"

# Service status
echo "Service Status:"
sudo systemctl is-active $TYPESENSE_SERVICE && echo "  Status: Running" || echo "  Status: Stopped"

# API Health
echo ""
echo "API Health:"
if curl -s -H "X-TYPESENSE-API-KEY: $TYPESENSE_API_KEY" "\$BASE_URL/health" | grep -q '"ok":true'; then
    echo "  Health: OK"
    
    # Get version
    VERSION=\$(curl -s -H "X-TYPESENSE-API-KEY: $TYPESENSE_API_KEY" "\$BASE_URL/debug" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    echo "  Version: \$VERSION"
    
    # Get stats
    echo ""
    echo "Collections:"
    curl -s -H "X-TYPESENSE-API-KEY: $TYPESENSE_API_KEY" "\$BASE_URL/collections" | jq '.[] | {name: .name, num_documents: .num_documents}' 2>/dev/null || echo "  No collections or jq not available"
else
    echo "  Health: Failed"
fi

echo ""
echo "Resource Usage:"
echo "  Data Directory: $TYPESENSE_DATA_DIR"
echo "  Log Directory: $TYPESENSE_LOG_DIR"
echo "  Config File: $TYPESENSE_CONFIG_FILE"

# Disk usage
if [[ -d "$TYPESENSE_DATA_DIR" ]]; then
    DISK_USAGE=\$(du -sh "$TYPESENSE_DATA_DIR" | cut -f1)
    echo "  Data Size: \$DISK_USAGE"
fi
EOF
    
    execute_command "sudo chmod +x '$status_script'" "Making status script executable"
    
    print_success "Management scripts created"
}

# Function to show post-installation instructions
show_post_install_instructions() {
    echo
    print_info "=== Typesense Installation Complete! ==="
    echo
    
    cat << EOF
Typesense Configuration:
  Service:         $TYPESENSE_SERVICE
  Config File:     $TYPESENSE_CONFIG_FILE
  Data Directory:  $TYPESENSE_DATA_DIR
  Log Directory:   $TYPESENSE_LOG_DIR
  Binary Location: /usr/bin/typesense-server
  Shared Files:    $TYPESENSE_BINARY_DIR
  
Server Settings:
  Version:         $TYPESENSE_VERSION
  Bind Address:    $BIND_ADDRESS
  API Port:        $API_PORT
  Peering Port:    $PEERING_PORT
  SSL/TLS:         $(if [[ "$ENABLE_SSL" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
  CORS:           $(if [[ "$ENABLE_CORS" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
  Analytics:      $(if [[ "$ENABLE_ANALYTICS" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)

Service Management:
  sudo systemctl status typesense-server     # Check service status
  sudo systemctl start typesense-server      # Start service
  sudo systemctl stop typesense-server       # Stop service
  sudo systemctl restart typesense-server    # Restart service

API Endpoints:
  Base URL: $(if [[ "$ENABLE_SSL" == true ]]; then echo "https"; else echo "http"; fi)://$BIND_ADDRESS:$API_PORT
  Health:   $(if [[ "$ENABLE_SSL" == true ]]; then echo "https"; else echo "http"; fi)://$BIND_ADDRESS:$API_PORT/health
  Debug:    $(if [[ "$ENABLE_SSL" == true ]]; then echo "https"; else echo "http"; fi)://$BIND_ADDRESS:$API_PORT/debug

API Authentication:
  Admin API Key: $TYPESENSE_API_KEY
  
  🔐 IMPORTANT: Save your API key securely!
  This key provides full administrative access to Typesense.

Connection Examples:
  # Health check
  curl -H "X-TYPESENSE-API-KEY: $TYPESENSE_API_KEY" \\
       "$(if [[ "$ENABLE_SSL" == true ]]; then echo "https"; else echo "http"; fi)://$BIND_ADDRESS:$API_PORT/health"
  
  # List collections
  curl -H "X-TYPESENSE-API-KEY: $TYPESENSE_API_KEY" \\
       "$(if [[ "$ENABLE_SSL" == true ]]; then echo "https"; else echo "http"; fi)://$BIND_ADDRESS:$API_PORT/collections"

Client SDK Configuration:
  {
    'nodes': [{
      'host': '$BIND_ADDRESS',
      'port': '$API_PORT',
      'protocol': '$(if [[ "$ENABLE_SSL" == true ]]; then echo "https"; else echo "http"; fi)'
    }],
    'api_key': '$TYPESENSE_API_KEY',
    'connection_timeout_seconds': 2
  }

Management Scripts:
  typesense-backup                       # Backup data and configuration
  typesense-status                       # Show server status and stats
  
Log Files:
  sudo journalctl -u typesense-server -f        # Service logs
  sudo tail -f $TYPESENSE_LOG_DIR/typesense.log        # Application logs
  sudo tail -f $TYPESENSE_LOG_DIR/typesense-access.log # Access logs

Performance Testing:
  # Install Typesense client for testing
  npm install typesense
  # or
  pip install typesense

Security Notes:
  ✅ Admin API key is configured
  ✅ Service runs as dedicated user ($TYPESENSE_USER)
  ✅ Proper file permissions set
$(if [[ "$BIND_ADDRESS" != "127.0.0.1" ]]; then cat <<EOL
  ⚠️  Typesense is listening on $BIND_ADDRESS - ensure firewall is configured
EOL
fi)
$(if [[ "$ENABLE_SSL" == false ]]; then cat <<EOL
  ⚠️  SSL is disabled - consider enabling for production use
EOL
fi)

Next Steps:
1. Test API connection with the examples above
2. Create search-only API keys for your applications
3. Set up regular backups with: typesense-backup
4. Monitor server with: typesense-status
5. Read the documentation: https://typesense.org/docs/

EOF
    
    print_success "Typesense installation completed successfully! 🚀"
}

# Main installation function
main() {
    show_script_header "Typesense Installation Script"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup defaults
    setup_defaults
    
    # Show installation summary
    print_info "Typesense will be installed with the following configuration:"
    print_info "  Version: $TYPESENSE_VERSION"
    print_info "  Method: $INSTALL_METHOD"
    print_info "  Architecture: $ARCHITECTURE"
    print_info "  Bind Address: $BIND_ADDRESS"
    print_info "  API Port: $API_PORT"
    print_info "  SSL: $(if [[ "$ENABLE_SSL" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    print_info "  CORS: $(if [[ "$ENABLE_CORS" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    print_info "  Analytics: $(if [[ "$ENABLE_ANALYTICS" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    
    if ! confirm_action "Proceed with Typesense installation?" "Y"; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Installation steps
    create_typesense_user
    setup_directories
    install_typesense
    generate_config_file
    create_systemd_service
    start_typesense_service
    test_typesense_installation
    create_management_scripts
    
    # Show post-installation instructions
    show_post_install_instructions
}

# Run main function
main "$@"