#!/bin/bash
#
# Script: servers/varnish/install.sh
# Description: Install Varnish HTTP Cache with secure configuration
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
readonly VARNISH_SERVICE="varnish"
readonly VARNISHNCSA_SERVICE="varnishncsa"
readonly VARNISH_CONFIG_SOURCE="$PROJECT_ROOT/system/etc/varnish/default.vcl"
readonly VARNISH_CONFIG_TARGET="/etc/varnish/default.vcl"
readonly VARNISH_LOGROTATE_SOURCE="$PROJECT_ROOT/system/etc/logrotate.d/varnish"
readonly VARNISH_LOGROTATE_TARGET="/etc/logrotate.d/varnish"
readonly VARNISH_DATA_DIR="/var/lib/varnish"
readonly VARNISH_LOG_DIR="/var/log/varnish"
readonly VARNISH_USER="varnish"
readonly DEFAULT_LISTEN_PORT="80"
readonly DEFAULT_ADMIN_PORT="6082"
readonly DEFAULT_MEMORY_SIZE="256M"

# Configuration
VARNISH_VERSION=""
LISTEN_ADDRESS="0.0.0.0"
LISTEN_PORT="$DEFAULT_LISTEN_PORT"
ADMIN_PORT="$DEFAULT_ADMIN_PORT"
MEMORY_SIZE="$DEFAULT_MEMORY_SIZE"
BACKEND_HOST="127.0.0.1"
BACKEND_PORT="8080"
SECONDARY_BACKEND_PORT="8081"
NODEJS_BACKEND_PORT="3027"
ENABLE_LOGGING=true
ENABLE_ADMIN=true
ADMIN_SECRET=""
VERBOSE=false
DRY_RUN=false
FORCE_REINSTALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VARNISH_VERSION="$2"
            shift 2
            ;;
        --listen-address)
            LISTEN_ADDRESS="$2"
            shift 2
            ;;
        --listen-port)
            LISTEN_PORT="$2"
            shift 2
            ;;
        --admin-port)
            ADMIN_PORT="$2"
            shift 2
            ;;
        --memory)
            MEMORY_SIZE="$2"
            shift 2
            ;;
        --backend-host)
            BACKEND_HOST="$2"
            shift 2
            ;;
        --backend-port)
            BACKEND_PORT="$2"
            shift 2
            ;;
        --secondary-port)
            SECONDARY_BACKEND_PORT="$2"
            shift 2
            ;;
        --nodejs-port)
            NODEJS_BACKEND_PORT="$2"
            shift 2
            ;;
        --no-logging)
            ENABLE_LOGGING=false
            shift
            ;;
        --no-admin)
            ENABLE_ADMIN=false
            shift
            ;;
        --admin-secret)
            ADMIN_SECRET="$2"
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

Install Varnish HTTP Cache with secure configuration.

OPTIONS:
    --version VERSION       Varnish version to install (default: latest from repo)
    --listen-address IP     Listen IP address (default: $LISTEN_ADDRESS)
    --listen-port PORT      Listen port (default: $LISTEN_PORT)
    --admin-port PORT       Admin interface port (default: $ADMIN_PORT)
    --memory SIZE           Memory cache size (default: $MEMORY_SIZE)
    --backend-host HOST     Backend server host (default: $BACKEND_HOST)
    --backend-port PORT     Primary backend port (default: $BACKEND_PORT)
    --secondary-port PORT   Secondary PHP backend port (default: $SECONDARY_BACKEND_PORT)
    --nodejs-port PORT      NodeJS backend port (default: $NODEJS_BACKEND_PORT)
    --no-logging            Disable access logging
    --no-admin              Disable admin interface
    --admin-secret SECRET   Set admin interface secret
    --force                 Force reinstallation
    --verbose               Enable verbose output
    --dry-run               Show what would be done without executing
    -h, --help              Show this help message

EXAMPLES:
    $0                                      # Basic installation
    $0 --memory 512M --listen-port 8080    # Custom memory and port
    $0 --backend-port 80 --no-admin        # Different backend, no admin
    $0 --admin-secret mysecret             # Set admin secret
    $0 --dry-run --verbose                 # Test installation

MEMORY FORMATS:
    128M, 256M, 512M, 1G, 2G (case sensitive)

NOTES:
    - Requires sudo privileges
    - Default VCL supports multiple backends (PHP 7.4, PHP 7.3, NodeJS)
    - Admin interface allows cache management
    - Access logging helps with monitoring
    - Configuration templates from: $VARNISH_CONFIG_SOURCE

BACKEND CONFIGURATION:
    The default VCL configuration supports:
    - Primary PHP backend on port $BACKEND_PORT (PHP 7.4)
    - Secondary PHP backend on port $SECONDARY_BACKEND_PORT (PHP 7.3)
    - NodeJS backend on port $NODEJS_BACKEND_PORT
    - Multiple listening ports: 8090, 8091, 8095

EOF
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
    
    # Check if VCL configuration file exists
    if [[ ! -f "$VARNISH_CONFIG_SOURCE" ]]; then
        print_error "VCL configuration file not found: $VARNISH_CONFIG_SOURCE"
        exit 1
    fi
    
    # Check if Varnish is already installed
    if [[ -f "/usr/bin/varnishd" && "$FORCE_REINSTALL" == false ]]; then
        local current_version
        current_version=$(varnishd -V 2>&1 | grep -oP 'varnish-\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        print_warning "Varnish is already installed: $current_version"
        if ! confirm_action "Reinstall Varnish?"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    print_success "Prerequisites check completed"
}

# Function to setup defaults
setup_defaults() {
    # Generate admin secret if not provided and admin is enabled
    if [[ "$ENABLE_ADMIN" == true && -z "$ADMIN_SECRET" ]]; then
        if confirm_action "Generate secure admin secret for Varnish management interface?" "Y"; then
            ADMIN_SECRET=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
            print_info "Generated admin secret: $ADMIN_SECRET"
            print_warning "Save this secret securely - you'll need it to access Varnish admin"
        else
            print_warning "Admin interface will be disabled without a secret"
            ENABLE_ADMIN=false
        fi
    fi
    
    # Validate memory size format
    if [[ ! "$MEMORY_SIZE" =~ ^[0-9]+[MGT]$ ]]; then
        print_error "Invalid memory size format: $MEMORY_SIZE"
        print_info "Use format like: 128M, 256M, 512M, 1G, 2G"
        exit 1
    fi
    
    # Check if ports are available
    if command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":$LISTEN_PORT "; then
            print_warning "Port $LISTEN_PORT is already in use"
        fi
        
        if [[ "$ENABLE_ADMIN" == true ]] && netstat -tuln | grep -q ":$ADMIN_PORT "; then
            print_warning "Admin port $ADMIN_PORT is already in use"
        fi
    fi
}

# Function to install Varnish packages
install_varnish_packages() {
    print_info "Installing Varnish packages..."
    
    # Update package lists
    execute_command "sudo apt update" "Updating package lists"
    
    # Install dependencies
    local dependencies=(
        "curl"
        "gnupg"
        "apt-transport-https"
    )
    
    execute_command "sudo apt install -y ${dependencies[*]}" "Installing dependencies"
    
    # Add Varnish repository if specific version requested
    if [[ -n "$VARNISH_VERSION" ]]; then
        print_info "Adding Varnish $VARNISH_VERSION repository..."
        execute_command "curl -fsSL https://packagecloud.io/varnishcache/varnish${VARNISH_VERSION//./}/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/varnish-archive-keyring.gpg" "Adding Varnish GPG key"
        
        local codename
        codename=$(lsb_release -cs)
        echo "deb [signed-by=/usr/share/keyrings/varnish-archive-keyring.gpg] https://packagecloud.io/varnishcache/varnish${VARNISH_VERSION//./}/ubuntu/ $codename main" | sudo tee /etc/apt/sources.list.d/varnishcache_varnish${VARNISH_VERSION//./}.list > /dev/null
        
        execute_command "sudo apt update" "Updating package lists with Varnish repository"
    fi
    
    # Install Varnish packages
    local packages=(
        "varnish"
        "varnish-dev"
    )
    
    if [[ -n "$VARNISH_VERSION" ]]; then
        execute_command "sudo apt install -y varnish=$VARNISH_VERSION* varnish-dev=$VARNISH_VERSION*" "Installing Varnish $VARNISH_VERSION"
        execute_command "sudo apt-mark hold varnish varnish-dev" "Holding Varnish packages"
    else
        execute_command "sudo apt install -y ${packages[*]}" "Installing Varnish packages"
    fi
    
    print_success "Varnish packages installed successfully"
}

# Function to create directories and set permissions
setup_directories() {
    print_info "Setting up Varnish directories..."
    
    local directories=(
        "$VARNISH_DATA_DIR"
        "$VARNISH_LOG_DIR"
        "/etc/varnish"
    )
    
    for dir in "${directories[@]}"; do
        execute_command "sudo mkdir -p '$dir'" "Creating directory: $dir"
    done
    
    # Set proper ownership
    execute_command "sudo chown -R $VARNISH_USER:$VARNISH_USER '$VARNISH_DATA_DIR'" "Setting data directory ownership"
    execute_command "sudo chown -R $VARNISH_USER:$VARNISH_USER '$VARNISH_LOG_DIR'" "Setting log directory ownership"
    
    # Set proper permissions
    execute_command "sudo chmod 755 '/etc/varnish'" "Setting config directory permissions"
    execute_command "sudo chmod 750 '$VARNISH_DATA_DIR'" "Setting data directory permissions"
    execute_command "sudo chmod 750 '$VARNISH_LOG_DIR'" "Setting log directory permissions"
    
    print_success "Directories setup completed"
}

# Function to configure VCL file
configure_vcl_file() {
    print_info "Configuring Varnish VCL..."
    
    local temp_vcl="/tmp/default.vcl.$$"
    
    # Copy and customize VCL configuration
    if [[ "$DRY_RUN" == false ]]; then
        # Copy base VCL file
        execute_command "cp '$VARNISH_CONFIG_SOURCE' '$temp_vcl'" "Copying base VCL configuration"
        
        # Update backend configurations if different from defaults
        if [[ "$BACKEND_HOST" != "127.0.0.1" || "$BACKEND_PORT" != "8080" ]]; then
            sed -i "s/\.host = \"127\.0\.0\.1\";/.host = \"$BACKEND_HOST\";/" "$temp_vcl"
            sed -i "s/\.port = \"8080\";/.port = \"$BACKEND_PORT\";/" "$temp_vcl"
        fi
        
        if [[ "$SECONDARY_BACKEND_PORT" != "8081" ]]; then
            sed -i "s/\.port = \"8081\";/.port = \"$SECONDARY_BACKEND_PORT\";/" "$temp_vcl"
        fi
        
        if [[ "$NODEJS_BACKEND_PORT" != "3027" ]]; then
            sed -i "s/\.port = \"3027\";/.port = \"$NODEJS_BACKEND_PORT\";/" "$temp_vcl"
        fi
        
        # Install the VCL configuration
        execute_command "sudo mv '$temp_vcl' '$VARNISH_CONFIG_TARGET'" "Installing VCL configuration"
        execute_command "sudo chown root:$VARNISH_USER '$VARNISH_CONFIG_TARGET'" "Setting VCL file ownership"
        execute_command "sudo chmod 644 '$VARNISH_CONFIG_TARGET'" "Setting VCL file permissions"
    else
        echo "[DRY-RUN] Would configure VCL with:"
        echo "  Backend Host: $BACKEND_HOST"
        echo "  Primary Backend Port: $BACKEND_PORT"
        echo "  Secondary Backend Port: $SECONDARY_BACKEND_PORT"
        echo "  NodeJS Backend Port: $NODEJS_BACKEND_PORT"
    fi
    
    print_success "VCL configuration completed"
}

# Function to configure Varnish service
configure_varnish_service() {
    print_info "Configuring Varnish service..."
    
    local varnish_config="/etc/default/varnish"
    local systemd_override_dir="/etc/systemd/system/varnish.service.d"
    local systemd_override="$systemd_override_dir/override.conf"
    
    # Create systemd override directory
    execute_command "sudo mkdir -p '$systemd_override_dir'" "Creating systemd override directory"
    
    # Configure Varnish systemd service
    execute_command "sudo tee '$systemd_override' > /dev/null" "Creating systemd override" <<EOF
[Unit]
Description=Varnish HTTP Cache
Documentation=https://varnish-cache.org/docs/
After=network.target

[Service]
Type=notify
User=$VARNISH_USER
Group=$VARNISH_USER
ExecStart=/usr/sbin/varnishd \\
    -a $LISTEN_ADDRESS:$LISTEN_PORT \\
    $(if [[ "$ENABLE_ADMIN" == true ]]; then echo "-T $LISTEN_ADDRESS:$ADMIN_PORT"; fi) \\
    -f $VARNISH_CONFIG_TARGET \\
    -s malloc,$MEMORY_SIZE \\
    -p feature=+http2 \\
    -p vcc_allow_inline_c=on \\
    -p thread_pool_min=50 \\
    -p thread_pool_max=1000 \\
    -p thread_pool_timeout=300 \\
    -p ban_lurker_sleep=0.01 \\
    -p ban_lurker_batch=1000
ExecReload=/usr/bin/varnish-vcl-reload
PIDFile=/run/varnishd.pid
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillMode=process

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$VARNISH_DATA_DIR $VARNISH_LOG_DIR /run

# Resource limits
LimitNOFILE=131072
LimitNPROC=4096
LimitMEMLOCK=82000

[Install]
WantedBy=multi-user.target
EOF
    
    # Configure admin secret if enabled
    if [[ "$ENABLE_ADMIN" == true && -n "$ADMIN_SECRET" ]]; then
        local secret_file="/etc/varnish/secret"
        execute_command "echo '$ADMIN_SECRET' | sudo tee '$secret_file' > /dev/null" "Creating admin secret file"
        execute_command "sudo chown root:$VARNISH_USER '$secret_file'" "Setting secret file ownership"
        execute_command "sudo chmod 640 '$secret_file'" "Setting secret file permissions"
        
        # Update systemd service to use secret file
        sudo sed -i "/-T $LISTEN_ADDRESS:$ADMIN_PORT/s/$/ -S $secret_file/" "$systemd_override"
    fi
    
    print_success "Varnish service configuration completed"
}

# Function to setup logging
setup_varnish_logging() {
    if [[ "$ENABLE_LOGGING" == false ]]; then
        print_info "Skipping Varnish logging setup"
        return 0
    fi
    
    print_info "Setting up Varnish logging..."
    
    # Install logrotate configuration
    if [[ -f "$VARNISH_LOGROTATE_SOURCE" ]]; then
        execute_command "sudo cp '$VARNISH_LOGROTATE_SOURCE' '$VARNISH_LOGROTATE_TARGET'" "Installing logrotate configuration"
        execute_command "sudo chown root:root '$VARNISH_LOGROTATE_TARGET'" "Setting logrotate file ownership"
        execute_command "sudo chmod 644 '$VARNISH_LOGROTATE_TARGET'" "Setting logrotate file permissions"
    fi
    
    # Configure varnishncsa service for access logging
    local ncsa_override_dir="/etc/systemd/system/varnishncsa.service.d"
    local ncsa_override="$ncsa_override_dir/override.conf"
    
    execute_command "sudo mkdir -p '$ncsa_override_dir'" "Creating varnishncsa override directory"
    
    execute_command "sudo tee '$ncsa_override' > /dev/null" "Configuring varnishncsa service" <<EOF
[Unit]
Description=Varnish HTTP Cache Access Logging
Documentation=https://varnish-cache.org/docs/
After=varnish.service
Requires=varnish.service

[Service]
Type=forking
User=$VARNISH_USER
Group=$VARNISH_USER
ExecStart=/usr/bin/varnishncsa \\
    -a \\
    -w $VARNISH_LOG_DIR/varnishncsa.log \\
    -D \\
    -P /run/varnishncsa.pid
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/run/varnishncsa.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Varnish logging setup completed"
}

# Function to start and enable services
start_varnish_services() {
    print_info "Starting Varnish services..."
    
    # Reload systemd
    execute_command "sudo systemctl daemon-reload" "Reloading systemd"
    
    # Enable and start Varnish service
    execute_command "sudo systemctl enable $VARNISH_SERVICE" "Enabling Varnish service"
    execute_command "sudo systemctl start $VARNISH_SERVICE" "Starting Varnish service"
    
    # Enable and start logging service if configured
    if [[ "$ENABLE_LOGGING" == true ]]; then
        execute_command "sudo systemctl enable $VARNISHNCSA_SERVICE" "Enabling Varnish logging service"
        execute_command "sudo systemctl start $VARNISHNCSA_SERVICE" "Starting Varnish logging service"
    fi
    
    # Wait for services to start
    if [[ "$DRY_RUN" == false ]]; then
        print_info "Waiting for Varnish to start..."
        sleep 3
        
        # Check service status
        if sudo systemctl is-active --quiet $VARNISH_SERVICE; then
            print_success "Varnish service is running"
        else
            print_error "Varnish service failed to start"
            print_info "Check logs: sudo journalctl -u $VARNISH_SERVICE -f"
            exit 1
        fi
        
        # Check logging service if enabled
        if [[ "$ENABLE_LOGGING" == true ]]; then
            if sudo systemctl is-active --quiet $VARNISHNCSA_SERVICE; then
                print_success "Varnish logging service is running"
            else
                print_warning "Varnish logging service failed to start"
                print_info "Check logs: sudo journalctl -u $VARNISHNCSA_SERVICE -f"
            fi
        fi
    fi
}

# Function to test Varnish installation
test_varnish_installation() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test Varnish HTTP cache"
        return 0
    fi
    
    print_info "Testing Varnish installation..."
    
    # Test basic HTTP connection
    if curl -s -I "http://$LISTEN_ADDRESS:$LISTEN_PORT/" | grep -q "HTTP/"; then
        print_success "Varnish HTTP test passed"
        
        # Check for cache headers
        local cache_header
        cache_header=$(curl -s -I "http://$LISTEN_ADDRESS:$LISTEN_PORT/" | grep -i "x-cache" || echo "")
        if [[ -n "$cache_header" ]]; then
            print_success "Cache headers detected: $cache_header"
        fi
    else
        print_warning "Varnish HTTP test failed - this may be normal if no backend is configured"
    fi
    
    # Test admin interface if enabled
    if [[ "$ENABLE_ADMIN" == true ]]; then
        if nc -z "$LISTEN_ADDRESS" "$ADMIN_PORT" 2>/dev/null; then
            print_success "Varnish admin interface is accessible on port $ADMIN_PORT"
        else
            print_warning "Varnish admin interface is not accessible"
        fi
    fi
    
    # Check VCL compilation
    if sudo varnishd -C -f "$VARNISH_CONFIG_TARGET" > /dev/null 2>&1; then
        print_success "VCL configuration compiled successfully"
    else
        print_error "VCL configuration compilation failed"
        exit 1
    fi
}

# Function to create management scripts
create_management_scripts() {
    print_info "Creating Varnish management scripts..."
    
    # Create VCL reload script
    local vcl_reload_script="/usr/local/bin/varnish-vcl-reload"
    
    execute_command "sudo tee '$vcl_reload_script' > /dev/null" "Creating VCL reload script" <<EOF
#!/bin/bash
#
# Varnish VCL Reload Script
# Created by Varnish installation script
#

VCL_FILE="$VARNISH_CONFIG_TARGET"
ADMIN_PORT="$ADMIN_PORT"
$(if [[ "$ENABLE_ADMIN" == true && -n "$ADMIN_SECRET" ]]; then echo "SECRET_FILE=\"/etc/varnish/secret\""; fi)

# Validate VCL syntax
echo "Validating VCL syntax..."
if ! varnishd -C -f "\$VCL_FILE" > /dev/null 2>&1; then
    echo "ERROR: VCL syntax validation failed"
    exit 1
fi

echo "VCL syntax is valid"

# Reload VCL via admin interface
if [[ "$ENABLE_ADMIN" == true ]]; then
    echo "Reloading VCL via admin interface..."
    TIMESTAMP=\$(date +%s)
    
    $(if [[ -n "$ADMIN_SECRET" ]]; then cat <<ADMIN_SECRET_BLOCK
    varnishadm -S "\$SECRET_FILE" -T $LISTEN_ADDRESS:$ADMIN_PORT \\
        vcl.load "reload_\$TIMESTAMP" "\$VCL_FILE"
    varnishadm -S "\$SECRET_FILE" -T $LISTEN_ADDRESS:$ADMIN_PORT \\
        vcl.use "reload_\$TIMESTAMP"
ADMIN_SECRET_BLOCK
else cat <<NO_SECRET_BLOCK
    varnishadm -T $LISTEN_ADDRESS:$ADMIN_PORT \\
        vcl.load "reload_\$TIMESTAMP" "\$VCL_FILE"
    varnishadm -T $LISTEN_ADDRESS:$ADMIN_PORT \\
        vcl.use "reload_\$TIMESTAMP"
NO_SECRET_BLOCK
fi)
    
    echo "VCL reloaded successfully"
else
    echo "Restarting Varnish service..."
    systemctl restart varnish
    echo "Varnish service restarted"
fi
EOF
    
    execute_command "sudo chmod +x '$vcl_reload_script'" "Making VCL reload script executable"
    
    # Create status script
    local status_script="/usr/local/bin/varnish-status"
    
    execute_command "sudo tee '$status_script' > /dev/null" "Creating status script" <<EOF
#!/bin/bash
#
# Varnish Status Script
# Created by Varnish installation script
#

echo "Varnish HTTP Cache Status:"
echo "=========================="

# Service status
echo "Service Status:"
systemctl is-active varnish && echo "  Varnish: Running" || echo "  Varnish: Stopped"
$(if [[ "$ENABLE_LOGGING" == true ]]; then
    echo 'systemctl is-active varnishncsa && echo "  Logging: Running" || echo "  Logging: Stopped"'
fi)

echo ""
echo "Configuration:"
echo "  Listen: $LISTEN_ADDRESS:$LISTEN_PORT"
$(if [[ "$ENABLE_ADMIN" == true ]]; then
    echo "echo \"  Admin: $LISTEN_ADDRESS:$ADMIN_PORT\""
fi)
echo "  Memory: $MEMORY_SIZE"
echo "  VCL: $VARNISH_CONFIG_TARGET"

echo ""
echo "Cache Statistics:"
if command -v varnishstat &> /dev/null; then
    varnishstat -1 | grep -E "(cache_hit|cache_miss|cache_hitpass|cache_hipass)" | head -10
else
    echo "  varnishstat not available"
fi

echo ""
echo "Backend Health:"
$(if [[ "$ENABLE_ADMIN" == true ]]; then
if [[ -n "$ADMIN_SECRET" ]]; then
    echo 'varnishadm -S "/etc/varnish/secret" -T '$LISTEN_ADDRESS':'$ADMIN_PORT' backend.list 2>/dev/null || echo "  Admin interface not accessible"'
else
    echo 'varnishadm -T '$LISTEN_ADDRESS':'$ADMIN_PORT' backend.list 2>/dev/null || echo "  Admin interface not accessible"'
fi
else
    echo "echo \"  Admin interface disabled\""
fi)
EOF
    
    execute_command "sudo chmod +x '$status_script'" "Making status script executable"
    
    # Create cache purge script
    local purge_script="/usr/local/bin/varnish-purge"
    
    execute_command "sudo tee '$purge_script' > /dev/null" "Creating cache purge script" <<EOF
#!/bin/bash
#
# Varnish Cache Purge Script
# Created by Varnish installation script
#

URL="\$1"
METHOD="\${2:-PURGE}"

if [[ -z "\$URL" ]]; then
    echo "Usage: \$0 <URL> [METHOD]"
    echo "Examples:"
    echo "  \$0 http://example.com/page"
    echo "  \$0 http://example.com/images/* BAN"
    exit 1
fi

echo "Purging cache for: \$URL"
echo "Method: \$METHOD"

if [[ "\$METHOD" == "BAN" ]]; then
    # Use ban for pattern matching
    $(if [[ "$ENABLE_ADMIN" == true ]]; then
if [[ -n "$ADMIN_SECRET" ]]; then
    echo 'varnishadm -S "/etc/varnish/secret" -T '$LISTEN_ADDRESS':'$ADMIN_PORT' "ban req.url ~ \$URL"'
else
    echo 'varnishadm -T '$LISTEN_ADDRESS':'$ADMIN_PORT' "ban req.url ~ \$URL"'
fi
else
    echo 'echo "Admin interface required for BAN method"'
    echo 'exit 1'
fi)
else
    # Use HTTP PURGE method
    curl -X PURGE "\$URL"
fi

echo "Cache purge completed"
EOF
    
    execute_command "sudo chmod +x '$purge_script'" "Making purge script executable"
    
    print_success "Management scripts created"
}

# Function to show post-installation instructions
show_post_install_instructions() {
    echo
    print_info "=== Varnish HTTP Cache Installation Complete! ==="
    echo
    
    cat << EOF
Varnish Configuration:
  Service:         $VARNISH_SERVICE
  VCL Config:      $VARNISH_CONFIG_TARGET
  Data Directory:  $VARNISH_DATA_DIR
  Log Directory:   $VARNISH_LOG_DIR
  
Network Settings:
  Listen Address:  $LISTEN_ADDRESS
  Listen Port:     $LISTEN_PORT
  $(if [[ "$ENABLE_ADMIN" == true ]]; then echo "Admin Port:      $ADMIN_PORT"; fi)
  Memory Size:     $MEMORY_SIZE

Backend Configuration:
  Primary Backend:    $BACKEND_HOST:$BACKEND_PORT (PHP 7.4)
  Secondary Backend:  $BACKEND_HOST:$SECONDARY_BACKEND_PORT (PHP 7.3)
  NodeJS Backend:     $BACKEND_HOST:$NODEJS_BACKEND_PORT
  
Service Management:
  sudo systemctl status varnish          # Check service status
  sudo systemctl start varnish           # Start service
  sudo systemctl stop varnish            # Stop service
  sudo systemctl restart varnish         # Restart service
  $(if [[ "$ENABLE_LOGGING" == true ]]; then echo "sudo systemctl status varnishncsa       # Check logging service"; fi)

Cache Management:
  varnish-vcl-reload                     # Reload VCL configuration
  varnish-status                         # Show cache statistics
  varnish-purge <URL>                    # Purge specific URL
  varnish-purge <pattern> BAN            # Ban URL pattern

$(if [[ "$ENABLE_ADMIN" == true ]]; then cat <<ADMIN_SECTION
Admin Interface:
  Connection: $LISTEN_ADDRESS:$ADMIN_PORT
  $(if [[ -n "$ADMIN_SECRET" ]]; then echo "Secret: $ADMIN_SECRET"; fi)
  
  # Connect to admin interface
  $(if [[ -n "$ADMIN_SECRET" ]]; then
    echo "varnishadm -S /etc/varnish/secret -T $LISTEN_ADDRESS:$ADMIN_PORT"
  else
    echo "varnishadm -T $LISTEN_ADDRESS:$ADMIN_PORT"
  fi)
  
  # Common admin commands
  help                    # Show available commands
  status                  # Show cache status
  ban req.url ~ ".*"      # Ban all cached content
  vcl.list                # List VCL configurations
  backend.list            # Show backend health

ADMIN_SECTION
fi)

VCL Configuration:
  The installed VCL supports multiple backends and listening ports:
  - Port 8090 → Primary PHP backend ($BACKEND_HOST:$BACKEND_PORT)
  - Port 8091 → Secondary PHP backend ($BACKEND_HOST:$SECONDARY_BACKEND_PORT)
  - Port 8095 → NodeJS backend ($BACKEND_HOST:$NODEJS_BACKEND_PORT)
  
  Edit VCL: $VARNISH_CONFIG_TARGET
  Reload:   varnish-vcl-reload

HTTP Testing:
  # Test cache functionality
  curl -I http://$LISTEN_ADDRESS:$LISTEN_PORT/
  
  # Check cache headers
  curl -H "Cache-Control: no-cache" http://$LISTEN_ADDRESS:$LISTEN_PORT/
  
  # Purge specific content
  curl -X PURGE http://$LISTEN_ADDRESS:$LISTEN_PORT/page

$(if [[ "$ENABLE_LOGGING" == true ]]; then cat <<LOGGING_SECTION
Log Files:
  sudo journalctl -u varnish -f                    # Service logs
  sudo journalctl -u varnishncsa -f                # Logging service
  sudo tail -f $VARNISH_LOG_DIR/varnishncsa.log           # Access logs

LOGGING_SECTION
fi)

Performance Monitoring:
  varnishstat                            # Real-time statistics
  varnishlog                             # Real-time request log
  varnishhist                            # Response time histogram
  varnishtop                             # Top requests/objects

Security Notes:
  ✅ Service runs as dedicated user ($VARNISH_USER)
  ✅ Proper file permissions set
  ✅ VCL configuration validated
  $(if [[ "$ENABLE_ADMIN" == true && -n "$ADMIN_SECRET" ]]; then echo "✅ Admin interface secured with secret"; fi)
  $(if [[ "$LISTEN_ADDRESS" != "127.0.0.1" ]]; then echo "⚠️  Varnish is listening on $LISTEN_ADDRESS - ensure firewall is configured"; fi)

Next Steps:
1. Configure your web server to listen on backend ports
2. Test cache functionality with the examples above
3. Monitor cache hit rates with varnishstat
4. Customize VCL configuration as needed
5. Set up regular log rotation and monitoring

EOF
    
    print_success "Varnish installation completed successfully! 🚀"
}

# Main installation function
main() {
    show_script_header "Varnish HTTP Cache Installation Script"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup defaults
    setup_defaults
    
    # Show installation summary
    print_info "Varnish will be installed with the following configuration:"
    print_info "  Listen: $LISTEN_ADDRESS:$LISTEN_PORT"
    print_info "  Memory: $MEMORY_SIZE"
    print_info "  Backend: $BACKEND_HOST:$BACKEND_PORT"
    print_info "  Admin: $(if [[ "$ENABLE_ADMIN" == true ]]; then echo "Enabled on port $ADMIN_PORT"; else echo "Disabled"; fi)"
    print_info "  Logging: $(if [[ "$ENABLE_LOGGING" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    
    if ! confirm_action "Proceed with Varnish installation?" "Y"; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Installation steps
    install_varnish_packages
    setup_directories
    configure_vcl_file
    configure_varnish_service
    setup_varnish_logging
    start_varnish_services
    test_varnish_installation
    create_management_scripts
    
    # Show post-installation instructions
    show_post_install_instructions
}

# Run main function
main "$@"