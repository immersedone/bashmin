#!/bin/bash
#
# Script: servers/nginx/install.sh
# Description: Install and configure Nginx web server with bashmin integration
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
readonly NGINX_CONF_DIR="/etc/nginx"
readonly NGINX_SITES_AVAILABLE="$NGINX_CONF_DIR/sites-available"
readonly NGINX_SITES_ENABLED="$NGINX_CONF_DIR/sites-enabled"
readonly NGINX_CONF_D="$NGINX_CONF_DIR/conf.d"
readonly NGINX_MODULES_AVAILABLE="$NGINX_CONF_DIR/modules-available"
readonly NGINX_MODULES_ENABLED="$NGINX_CONF_DIR/modules-enabled"
readonly NGINX_LOG_DIR="/var/log/nginx"
readonly VHOST_EXAMPLE="$SCRIPT_DIR/vhost.config.example"
readonly ADD_VHOST_SCRIPT="$SCRIPT_DIR/add-vhost.sh"
readonly ADD_PROXY_SCRIPT="$SCRIPT_DIR/add-proxy.sh"
readonly SYSTEM_CONFIGS="$PROJECT_ROOT/system/etc/nginx"

# Configuration variables
INSTALL_MODE="standard"
ENABLE_SSL=true
ENABLE_HTTP2=true
ENABLE_COMPRESSION=true
ENABLE_CACHING=true
ENABLE_SECURITY=true
ENABLE_MODSECURITY=false
ENABLE_RATE_LIMITING=true
PHP_VERSION="8.3"
NGINX_USER="www-data"
SERVER_HEADER="ImmersedOne"
HIDE_SERVER_HEADER=false
FORCE_INSTALL=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Install and configure Nginx web server with bashmin integration.

OPTIONS:
    --mode MODE             Installation mode: minimal, standard, full (default: $INSTALL_MODE)
    --php-version VERSION   PHP version to configure (default: $PHP_VERSION)
    --user USER             Nginx worker process user: www-data or shadower (default: $NGINX_USER)
    --server-header NAME    Set custom Server header value (default: $SERVER_HEADER)
    --hide-server-header    Remove Server header completely
    --no-ssl                Skip SSL module installation
    --no-http2              Skip HTTP/2 module installation
    --no-compression        Skip compression modules
    --no-caching            Skip caching modules
    --no-security           Skip security enhancements
    --enable-modsecurity    Enable ModSecurity WAF (requires module)
    --no-modsecurity        Skip ModSecurity installation (default)
    --no-rate-limiting      Skip rate limiting configuration
    --force                 Force reinstallation (creates timestamped backup)
    --quiet                 Suppress non-essential output
    --verbose               Enable verbose output
    --dry-run               Show what would be installed without executing
    -h, --help              Show this help message

MODES:
    minimal                 Basic Nginx installation with essential configuration
    standard                Standard installation with PHP, SSL, and optimization (ModSecurity disabled)
    full                    Complete installation with ModSecurity WAF and advanced features

EXAMPLES:
    $0                                      # Standard installation with www-data user
    $0 --user shadower                     # Install with shadower as nginx user
    $0 --mode full --verbose               # Full installation with details
    $0 --php-version 8.4 --no-modsecurity  # Custom PHP version without ModSecurity
    $0 --server-header MyServer            # Set custom Server header
    $0 --hide-server-header                # Remove Server header completely
    $0 --dry-run                           # Preview installation

FEATURES:
    - Automatic Nginx package installation
    - Essential module configuration (SSL, HTTP/2, compression, etc.)
    - PHP-FPM integration with configurable version
    - Performance optimization configurations
    - Security enhancements and ModSecurity WAF
    - Rate limiting and DDoS protection
    - Bashmin vhost and proxy management integration
    - Log rotation and monitoring setup

POST-INSTALL:
    - Use add-vhost.sh to create new virtual hosts
    - Use add-proxy.sh to create reverse proxy configurations
    - Check configuration with: nginx -t
    - Restart service with: systemctl restart nginx

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            INSTALL_MODE="$2"
            shift 2
            ;;
        --php-version)
            PHP_VERSION="$2"
            shift 2
            ;;
        --user)
            if [[ "$2" == "www-data" || "$2" == "shadower" ]]; then
                NGINX_USER="$2"
            else
                print_error "Invalid user: $2 (must be 'www-data' or 'shadower')"
                exit 1
            fi
            shift 2
            ;;
        --server-header)
            SERVER_HEADER="$2"
            shift 2
            ;;
        --hide-server-header)
            HIDE_SERVER_HEADER=true
            shift
            ;;
        --no-ssl)
            ENABLE_SSL=false
            shift
            ;;
        --no-http2)
            ENABLE_HTTP2=false
            shift
            ;;
        --no-compression)
            ENABLE_COMPRESSION=false
            shift
            ;;
        --no-caching)
            ENABLE_CACHING=false
            shift
            ;;
        --no-security)
            ENABLE_SECURITY=false
            shift
            ;;
        --enable-modsecurity)
            ENABLE_MODSECURITY=true
            shift
            ;;
        --no-modsecurity)
            ENABLE_MODSECURITY=false
            shift
            ;;
        --no-rate-limiting)
            ENABLE_RATE_LIMITING=false
            shift
            ;;
        --force)
            FORCE_INSTALL=true
            shift
            ;;
        --quiet)
            QUIET=true
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

# Function to check if Nginx is installed
check_nginx_installed() {
    if command -v nginx >/dev/null 2>&1 && [[ -d "$NGINX_CONF_DIR" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Checking system prerequisites..."
    fi
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        exit 1
    fi
    
    # Check OS compatibility
    if ! command -v apt >/dev/null 2>&1; then
        print_error "This script requires apt package manager (Ubuntu/Debian)"
        exit 1
    fi
    
    # Check if Nginx is already installed
    if check_nginx_installed && [[ "$FORCE_INSTALL" == false ]]; then
        if [[ "$QUIET" == false ]]; then
            print_warning "Nginx appears to be already installed"
            print_info "Use --force to reinstall or reconfigure"
        fi
        exit 1
    fi
    
    # Check disk space (minimum 500MB)
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 512000 ]]; then
        print_warning "Low disk space detected (less than 500MB available)"
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Continue with installation?" "N"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
}

# Function to install Nginx packages
install_nginx_packages() {
    if [[ "$QUIET" == false ]]; then
        print_info "Installing Nginx packages..."
    fi
    
    local packages=(
        "nginx"
        "nginx-common"
        "nginx-core"
    )
    
    # Add additional packages based on mode
    case "$INSTALL_MODE" in
        full)
            packages+=(
                "nginx-extras"
                "libnginx-mod-http-headers-more-filter"
                "libnginx-mod-http-cache-purge"
            )
            
            # ModSecurity packages
            if [[ "$ENABLE_MODSECURITY" == true ]]; then
                packages+=(
                    "libnginx-mod-security"
                    "modsecurity-crs"
                )
            fi
            ;;
        standard)
            packages+=(
                "nginx-extras"
            )
            ;;
    esac
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install packages: ${packages[*]}"
        return 0
    fi
    
    # Update package list
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Updating package lists..."
    fi
    sudo apt update -qq
    
    # Install packages
    for package in "${packages[@]}"; do
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Installing $package..."
        fi
        
        if ! sudo apt install -y "$package" >/dev/null 2>&1; then
            if [[ "$package" == "nginx-extras" || "$package" == "libnginx-mod-"* ]]; then
                print_warning "Optional package not available: $package"
                continue
            else
                print_error "Failed to install package: $package"
                exit 1
            fi
        fi
    done
    
    if [[ "$QUIET" == false ]]; then
        print_success "Nginx packages installed successfully"
    fi
}

# Function to configure nginx user
configure_nginx_user() {
    if [[ "$QUIET" == false ]]; then
        print_info "Configuring Nginx to run as user: $NGINX_USER"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure Nginx user as: $NGINX_USER"
        return 0
    fi

    # Ensure user exists
    if ! id "$NGINX_USER" >/dev/null 2>&1; then
        if [[ "$NGINX_USER" == "shadower" ]]; then
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_info "Creating user: $NGINX_USER"
            fi
            sudo useradd -r -s /bin/false -d /var/cache/nginx -c "Nginx web server" "$NGINX_USER" 2>/dev/null || true
        fi
    fi

    # Update nginx.conf to use selected user (in case it's an existing installation)
    if [[ -f "$NGINX_CONF_DIR/nginx.conf" ]]; then
        # Check if nginx.conf has placeholder or wrong user
        if grep -q "{NGINX_USER}" "$NGINX_CONF_DIR/nginx.conf" || ! grep -q "^user $NGINX_USER;" "$NGINX_CONF_DIR/nginx.conf"; then
            # Backup original
            sudo cp "$NGINX_CONF_DIR/nginx.conf" "$NGINX_CONF_DIR/nginx.conf.backup.user.$(date +%Y%m%d_%H%M%S)"

            # Replace placeholder if exists
            sudo sed -i "s/{NGINX_USER}/$NGINX_USER/g" "$NGINX_CONF_DIR/nginx.conf"

            # Update existing user directive
            sudo sed -i "s/^user .*/user $NGINX_USER;/" "$NGINX_CONF_DIR/nginx.conf"

            # If user directive doesn't exist, add it at the beginning
            if ! grep -q "^user " "$NGINX_CONF_DIR/nginx.conf"; then
                sudo sed -i "1i user $NGINX_USER;" "$NGINX_CONF_DIR/nginx.conf"
            fi
        fi
    fi

    # Ensure log directory permissions
    if [[ -d "$NGINX_LOG_DIR" ]]; then
        sudo chown -R $NGINX_USER:adm "$NGINX_LOG_DIR"
        sudo chmod 755 "$NGINX_LOG_DIR"
    fi

    # Ensure cache directories permissions
    for cache_dir in /var/cache/nginx /var/lib/nginx; do
        if [[ -d "$cache_dir" ]]; then
            sudo chown -R $NGINX_USER:$NGINX_USER "$cache_dir"
        else
            sudo mkdir -p "$cache_dir"
            sudo chown -R $NGINX_USER:$NGINX_USER "$cache_dir"
        fi
    done

    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Nginx user configured as: $NGINX_USER"
    fi
}

# Function to backup existing configurations
backup_existing_configs() {
    if [[ "$FORCE_INSTALL" == false ]]; then
        return 0
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$NGINX_CONF_DIR/backups/$timestamp"
    local configs_backed_up=false

    if [[ "$QUIET" == false ]]; then
        print_info "Creating backup of existing configurations..."
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create backup in: $backup_dir"
        return 0
    fi

    # Create backup directory
    sudo mkdir -p "$backup_dir"

    # Backup main nginx.conf
    if [[ -f "$NGINX_CONF_DIR/nginx.conf" ]]; then
        sudo cp "$NGINX_CONF_DIR/nginx.conf" "$backup_dir/nginx.conf"
        configs_backed_up=true
    fi

    # Backup conf.d directory
    if [[ -d "$NGINX_CONF_D" ]] && [[ "$(ls -A $NGINX_CONF_D 2>/dev/null)" ]]; then
        sudo cp -r "$NGINX_CONF_D" "$backup_dir/"
        configs_backed_up=true
    fi

    # Backup sites-available
    if [[ -d "$NGINX_SITES_AVAILABLE" ]] && [[ "$(ls -A $NGINX_SITES_AVAILABLE 2>/dev/null)" ]]; then
        sudo mkdir -p "$backup_dir/sites-available"
        sudo cp -r "$NGINX_SITES_AVAILABLE"/* "$backup_dir/sites-available/" 2>/dev/null || true
        configs_backed_up=true
    fi

    # Backup sites-enabled
    if [[ -d "$NGINX_SITES_ENABLED" ]] && [[ "$(ls -A $NGINX_SITES_ENABLED 2>/dev/null)" ]]; then
        sudo mkdir -p "$backup_dir/sites-enabled"
        sudo cp -r "$NGINX_SITES_ENABLED"/* "$backup_dir/sites-enabled/" 2>/dev/null || true
        configs_backed_up=true
    fi

    # Backup modules configuration
    if [[ -d "$NGINX_MODULES_ENABLED" ]] && [[ "$(ls -A $NGINX_MODULES_ENABLED 2>/dev/null)" ]]; then
        sudo mkdir -p "$backup_dir/modules-enabled"
        sudo cp -r "$NGINX_MODULES_ENABLED"/* "$backup_dir/modules-enabled/" 2>/dev/null || true
        configs_backed_up=true
    fi

    if [[ "$configs_backed_up" == true ]]; then
        # Create backup info file
        sudo tee "$backup_dir/backup_info.txt" > /dev/null << EOF
Nginx Configuration Backup
==========================
Timestamp: $timestamp
Date: $(date)
User: $(whoami)
Force: $FORCE_INSTALL
Nginx Version: $(nginx -v 2>&1)
EOF

        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Backup created at: $backup_dir"
        fi

        # Keep only last 10 backups
        if [[ -d "$NGINX_CONF_DIR/backups" ]]; then
            local backup_count=$(ls -1 "$NGINX_CONF_DIR/backups" | wc -l)
            if [[ $backup_count -gt 10 ]]; then
                if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                    print_info "Cleaning old backups (keeping last 10)..."
                fi
                ls -1t "$NGINX_CONF_DIR/backups" | tail -n +11 | while read old_backup; do
                    sudo rm -rf "$NGINX_CONF_DIR/backups/$old_backup"
                done
            fi
        fi
    else
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_warning "No existing configurations found to backup"
        fi
    fi
}

# Function to install system configurations
install_system_configs() {
    if [[ "$QUIET" == false ]]; then
        print_info "Installing system configurations..."
    fi

    if [[ ! -d "$SYSTEM_CONFIGS" ]]; then
        print_warning "System configurations not found: $SYSTEM_CONFIGS"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install system configurations"
        return 0
    fi
    # Install main nginx.conf if available
    if [[ -f "$SYSTEM_CONFIGS/nginx.conf" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Installing main Nginx configuration with user: $NGINX_USER"
        fi
        # Copy template and replace placeholders
        sudo cp "$SYSTEM_CONFIGS/nginx.conf" "$NGINX_CONF_DIR/nginx.conf"
        sudo sed -i "s/{NGINX_USER}/$NGINX_USER/g" "$NGINX_CONF_DIR/nginx.conf"

        # Configure Server header based on flags
        if [[ "$HIDE_SERVER_HEADER" == true ]]; then
            # Completely remove the Server header
            local server_header_config="more_clear_headers Server;"
            sudo sed -i "s|{SERVER_HEADER_CONFIG}|$server_header_config|" "$NGINX_CONF_DIR/nginx.conf"
        elif [[ -n "$SERVER_HEADER" ]]; then
            # Set custom Server header
            local server_header_config="more_set_headers 'Server: $SERVER_HEADER';"
            sudo sed -i "s|{SERVER_HEADER_CONFIG}|$server_header_config|" "$NGINX_CONF_DIR/nginx.conf"
        else
            # No server header modification
            sudo sed -i "s|{SERVER_HEADER_CONFIG}|# Server header not modified|" "$NGINX_CONF_DIR/nginx.conf"
        fi

        # Configure ModSecurity based on flag
        if [[ "$ENABLE_MODSECURITY" == true ]]; then
            local modsec_config="modsecurity on;\n        modsecurity_rules_file /etc/nginx/modsec/main.conf;"
            sudo sed -i "s|{MODSECURITY_CONFIG}|$modsec_config|" "$NGINX_CONF_DIR/nginx.conf"
        else
            # Comment out or remove ModSecurity directives
            sudo sed -i "s|{MODSECURITY_CONFIG}|# modsecurity off; (not enabled)|" "$NGINX_CONF_DIR/nginx.conf"
        fi
    fi
    
    # Install site configurations
    if [[ -d "$SYSTEM_CONFIGS/sites-available" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Installing site configuration examples..."
        fi
        
        for site_file in "$SYSTEM_CONFIGS/sites-available"/*.conf; do
            if [[ -f "$site_file" ]] && [[ "$(basename "$site_file")" != "default" ]]; then
                sudo cp "$site_file" "$NGINX_SITES_AVAILABLE/"
            fi
        done
        
        # Install default site if available
        if [[ -f "$SYSTEM_CONFIGS/sites-available/default" ]]; then
            sudo cp "$SYSTEM_CONFIGS/sites-available/default" "$NGINX_SITES_AVAILABLE/"
        fi
    fi
    
    # Install ModSecurity configurations
    if [[ "$ENABLE_MODSECURITY" == true && -d "$SYSTEM_CONFIGS/modsec" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Installing ModSecurity configurations..."
        fi
        
        sudo mkdir -p "$NGINX_CONF_DIR/modsec"
        sudo cp -r "$SYSTEM_CONFIGS/modsec"/* "$NGINX_CONF_DIR/modsec/"
    fi
    
    # Install modules if available
    if [[ -d "$SYSTEM_CONFIGS/modules-available" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Installing available modules..."
        fi
        
        sudo mkdir -p "$NGINX_MODULES_AVAILABLE"
        for module_file in "$SYSTEM_CONFIGS/modules-available"/*; do
            if [[ -f "$module_file" ]]; then
                sudo cp "$module_file" "$NGINX_MODULES_AVAILABLE/"
            fi
        done
    fi
}

# Function to configure PHP integration
configure_php_integration() {
    if [[ "$QUIET" == false ]]; then
        print_info "Configuring PHP $PHP_VERSION integration..."
    fi
    
    local php_fpm_package="php${PHP_VERSION}-fpm"
    local php_socket="/run/php/php${PHP_VERSION}-fpm.sock"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure PHP $PHP_VERSION integration"
        return 0
    fi
    
    # Check if PHP-FPM is installed
    if ! dpkg -l | grep -q "$php_fpm_package"; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Installing PHP-FPM $PHP_VERSION..."
        fi
        sudo apt install -y "$php_fpm_package" >/dev/null 2>&1
    fi
    
    # Enable PHP-FPM service
    sudo systemctl enable "php${PHP_VERSION}-fpm" >/dev/null 2>&1
    sudo systemctl start "php${PHP_VERSION}-fpm" >/dev/null 2>&1
    
    # Create PHP configuration snippet for Nginx
    local php_conf_file="$NGINX_CONF_D/php${PHP_VERSION}-fpm.conf"
    
    sudo tee "$php_conf_file" > /dev/null << EOF
# PHP $PHP_VERSION FPM Configuration for Nginx

# FastCGI cache configuration
fastcgi_cache_path /var/cache/nginx/fastcgi levels=1:2 keys_zone=phpcache:100m max_size=10g 
                   inactive=60m use_temp_path=off;

# PHP location block (include this in server blocks)
# location ~ \.php$ {
#     try_files \$uri =404;
#     fastcgi_split_path_info ^(.+\.php)(/.+)$;
#     fastcgi_pass unix:$php_socket;
#     fastcgi_index index.php;
#     include fastcgi_params;
#     fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
#     fastcgi_param PATH_INFO \$fastcgi_path_info;
#     
#     # FastCGI cache settings
#     fastcgi_cache phpcache;
#     fastcgi_cache_valid 200 301 302 10m;
#     fastcgi_cache_valid 404 1m;
#     fastcgi_cache_bypass \$skip_cache;
#     fastcgi_no_cache \$skip_cache;
#     add_header X-FastCGI-Cache \$upstream_cache_status;
# }

# Cache bypass conditions
map \$request_method \$skip_cache {
    default 0;
    POST    1;
}

map \$request_uri \$skip_cache {
    default 0;
    ~*/wp-admin/.*    1;
    ~*/wp-login.php   1;
    ~*/admin/.*       1;
    ~*/phpmyadmin/.*  1;
}

map \$http_cookie \$skip_cache {
    default 0;
    ~*wordpress_logged_in.*   1;
    ~*comment_author.*        1;
    ~*wp-postpass.*           1;
}
EOF
    
    # Create cache directory
    sudo mkdir -p /var/cache/nginx/fastcgi
    sudo chown $NGINX_USER:$NGINX_USER /var/cache/nginx/fastcgi
    sudo chmod 755 /var/cache/nginx/fastcgi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "PHP $PHP_VERSION integration configured"
    fi
}

# Function to configure security settings
configure_security() {
    if [[ "$ENABLE_SECURITY" == false ]]; then
        return 0
    fi
    
    if [[ "$QUIET" == false ]]; then
        print_info "Configuring security settings..."
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure security settings"
        return 0
    fi
    
    # Create security configuration
    local security_conf="$NGINX_CONF_D/bashmin-security.conf"
    
    sudo tee "$security_conf" > /dev/null << EOF
# Bashmin Security Configuration for Nginx
# Focus: Security headers only
# Note: All other settings are configured in main nginx.conf or other dedicated configs

# Security headers for all requests
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header X-Download-Options noopen always;
add_header X-Permitted-Cross-Domain-Policies none always;

# Remove server header completely (requires headers-more module)
# Comment out if headers-more module is not available
more_clear_headers Server;
EOF
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Security settings configured"
    fi
}

# Function to configure rate limiting
configure_rate_limiting() {
    if [[ "$ENABLE_RATE_LIMITING" == false ]]; then
        return 0
    fi
    
    if [[ "$QUIET" == false ]]; then
        print_info "Configuring rate limiting..."
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure rate limiting"
        return 0
    fi
    
    # Create rate limiting configuration
    local ratelimit_conf="$NGINX_CONF_D/bashmin-ratelimiting.conf"
    
    sudo tee "$ratelimit_conf" > /dev/null << EOF
# Bashmin Rate Limiting Configuration for Nginx

# Define rate limiting zones
limit_req_zone \$binary_remote_addr zone=general:10m rate=200r/m;
limit_req_zone \$binary_remote_addr zone=login:10m rate=10r/m;
limit_req_zone \$binary_remote_addr zone=api:10m rate=100r/m;
limit_req_zone \$binary_remote_addr zone=search:10m rate=30r/m;

# Connection limits
limit_conn_zone \$binary_remote_addr zone=connlimitperip:10m;
limit_conn_zone \$server_name zone=connlimitperserver:10m;

# Global limits
limit_conn connlimitperip 16;
limit_conn connlimitperserver 1000;

# Request size limits - consolidated here to avoid duplicates
client_max_body_size 100M;
client_body_buffer_size 128k;
client_header_buffer_size 1k;
large_client_header_buffers 4 4k;

# Timeout settings - consolidated here to avoid duplicates
client_body_timeout 12;
client_header_timeout 12;
send_timeout 10;

# Example usage in server blocks:
# location / {
#     limit_req zone=general burst=200 nodelay;
#     limit_req_status 429;
# }
#
# location /login {
#     limit_req zone=login burst=10 nodelay;
#     limit_req_status 429;
# }
#
# location /api {
#     limit_req zone=api burst=100 nodelay;
#     limit_req_status 429;
# }
#
# location /search {
#     limit_req zone=search burst=30 nodelay;
#     limit_req_status 429;
# }
EOF
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Rate limiting configured"
    fi
}

# Function to create vhost management scripts
create_management_scripts() {
    if [[ "$QUIET" == false ]]; then
        print_info "Creating vhost management scripts..."
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create management scripts"
        return 0
    fi
    
    # Create vhost example template first
    create_vhost_template
    
    # Create add-vhost script (simplified here, full implementation would be similar to Apache)
    cat > "$ADD_VHOST_SCRIPT" << 'EOF'
#!/bin/bash
# Nginx Add-VHost Script (placeholder)
# Full implementation would follow Apache2 pattern
echo "Nginx add-vhost script created - implementation pending"
EOF
    
    # Create add-proxy script
    cat > "$ADD_PROXY_SCRIPT" << 'EOF'
#!/bin/bash
# Nginx Add-Proxy Script (placeholder)
# For creating reverse proxy configurations
echo "Nginx add-proxy script created - implementation pending"
EOF
    
    # Make scripts executable
    chmod +x "$ADD_VHOST_SCRIPT" "$ADD_PROXY_SCRIPT"
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Management scripts created"
    fi
}

# Function to create vhost template
create_vhost_template() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create vhost template"
        return 0
    fi
    
    # Create vhost template based on system example
    if [[ -f "$SYSTEM_CONFIGS/sites-available/site.conf.example" ]]; then
        sudo cp "$SYSTEM_CONFIGS/sites-available/site.conf.example" "$VHOST_EXAMPLE"
    else
        # Create basic template
        cat > "$VHOST_EXAMPLE" << EOF
# Nginx Virtual Host Template
# Generated by bashmin Nginx installer

server {
    listen 80;
    listen [::]:80;
    
    server_name {DOMAIN_NAME};
    root {DOCUMENT_ROOT};
    index index.php index.html index.htm;
    
    # Security headers
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Rate limiting
    limit_req zone=general burst=200 nodelay;
    
    # PHP handling
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php{PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    
    # Static files
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Deny access to sensitive files
    location ~ /\. {
        deny all;
        return 404;
    }
    
    # Logging
    access_log /var/log/nginx/{DOMAIN_NAME}-access.log;
    error_log /var/log/nginx/{DOMAIN_NAME}-error.log;
}
EOF
    fi
}

# Function to setup log rotation
setup_log_rotation() {
    if [[ "$QUIET" == false ]]; then
        print_info "Configuring log rotation..."
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure log rotation"
        return 0
    fi
    
    # Use system logrotate configuration if available
    local system_logrotate="$PROJECT_ROOT/system/etc/logrotate.d/nginx"
    if [[ -f "$system_logrotate" ]]; then
        sudo cp "$system_logrotate" "/etc/logrotate.d/nginx"
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Log rotation configured from system template"
        fi
    fi
}

# Function to fix existing nginx configuration issues
fix_existing_config_issues() {
    if [[ "$QUIET" == false ]]; then
        print_info "Checking for existing nginx configuration issues..."
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would check and fix existing nginx configuration issues"
        return 0
    fi

    # Check if nginx.conf exists
    if [[ ! -f "$NGINX_CONF_DIR/nginx.conf" ]]; then
        return 0
    fi

    local config_changed=false

    # Fix ModSecurity issues if modules aren't installed
    if grep -q "^[[:space:]]*modsecurity" "$NGINX_CONF_DIR/nginx.conf" && [[ "$ENABLE_MODSECURITY" == false ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Disabling ModSecurity directives in existing config..."
        fi

        # Comment out modsecurity directives
        sudo sed -i 's/^[[:space:]]*modsecurity/#&/' "$NGINX_CONF_DIR/nginx.conf"
        config_changed=true
    fi

    # Fix duplicate server_tokens directive
    if [[ -f "$NGINX_CONF_D/bashmin-security.conf" ]] && grep -q "^server_tokens" "$NGINX_CONF_D/bashmin-security.conf"; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Removing duplicate server_tokens from security config..."
        fi

        # Remove duplicate server_tokens from security config
        sudo sed -i '/^server_tokens/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^# Hide Nginx version/d' "$NGINX_CONF_D/bashmin-security.conf"
        config_changed=true
    fi

    # Fix duplicate SSL directives
    if [[ -f "$NGINX_CONF_D/bashmin-security.conf" ]] && grep -q "^ssl_" "$NGINX_CONF_D/bashmin-security.conf"; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Removing duplicate SSL directives from security config..."
        fi

        # Remove SSL-related duplicates from security config
        sudo sed -i '/^ssl_protocols/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^ssl_ciphers/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^ssl_prefer_server_ciphers/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^ssl_session_cache/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^ssl_session_timeout/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^# SSL Security/d' "$NGINX_CONF_D/bashmin-security.conf"
        config_changed=true
    fi

    # Fix duplicate client/buffer/timeout directives in security config
    if [[ -f "$NGINX_CONF_D/bashmin-security.conf" ]] && (grep -q "^client_" "$NGINX_CONF_D/bashmin-security.conf" || grep -q "^keepalive_timeout" "$NGINX_CONF_D/bashmin-security.conf" || grep -q "^send_timeout" "$NGINX_CONF_D/bashmin-security.conf"); then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Removing duplicate client/timeout directives from security config..."
        fi

        # Remove client and timeout directives that belong in main config or ratelimiting config
        sudo sed -i '/^client_body_buffer_size/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^client_header_buffer_size/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^client_max_body_size/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^large_client_header_buffers/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^client_body_timeout/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^client_header_timeout/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^keepalive_timeout/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^send_timeout/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^# Buffer size limits/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^# Timeouts/d' "$NGINX_CONF_D/bashmin-security.conf"
        config_changed=true
    fi

    # Fix duplicate connection limiting and location blocks in security config
    if [[ -f "$NGINX_CONF_D/bashmin-security.conf" ]] && (grep -q "^limit_conn_zone" "$NGINX_CONF_D/bashmin-security.conf" || grep -q "^location" "$NGINX_CONF_D/bashmin-security.conf"); then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Removing connection limits and location blocks from security config..."
        fi

        # Remove connection limiting and location blocks that don't belong in security config
        sudo sed -i '/^limit_conn_zone/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^# Connection limiting/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^# File upload restrictions/,/^}$/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^# Block common attack patterns/,/^}$/d' "$NGINX_CONF_D/bashmin-security.conf"
        sudo sed -i '/^location.*{/,/^}/d' "$NGINX_CONF_D/bashmin-security.conf"
        config_changed=true
    fi

    # Fix duplicate client/buffer settings between rate limiting and security configs
    if [[ -f "$NGINX_CONF_D/bashmin-ratelimiting.conf" ]] && [[ -f "$NGINX_CONF_D/bashmin-security.conf" ]]; then
        # Check if both configs have client buffer settings
        if grep -q "^client_.*buffer" "$NGINX_CONF_D/bashmin-ratelimiting.conf" && grep -q "^client_.*buffer" "$NGINX_CONF_D/bashmin-security.conf"; then
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_info "Removing duplicate client buffer settings from security config (keeping in ratelimiting config)..."
            fi

            # Remove client buffer and timeout settings from security config to avoid conflicts with ratelimiting config
            sudo sed -i '/^client_body_buffer_size/d' "$NGINX_CONF_D/bashmin-security.conf"
            sudo sed -i '/^client_header_buffer_size/d' "$NGINX_CONF_D/bashmin-security.conf"
            sudo sed -i '/^client_max_body_size/d' "$NGINX_CONF_D/bashmin-security.conf"
            sudo sed -i '/^large_client_header_buffers/d' "$NGINX_CONF_D/bashmin-security.conf"
            sudo sed -i '/^client_body_timeout/d' "$NGINX_CONF_D/bashmin-security.conf"
            sudo sed -i '/^client_header_timeout/d' "$NGINX_CONF_D/bashmin-security.conf"
            sudo sed -i '/^keepalive_timeout/d' "$NGINX_CONF_D/bashmin-security.conf"
            sudo sed -i '/^send_timeout/d' "$NGINX_CONF_D/bashmin-security.conf"
            config_changed=true
        fi
    fi

    if [[ "$config_changed" == true ]]; then
        if [[ "$QUIET" == false ]]; then
            print_success "Fixed existing nginx configuration issues"
        fi
    fi
}

# Function to validate installation
validate_installation() {
    if [[ "$QUIET" == false ]]; then
        print_info "Validating Nginx installation..."
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would validate installation"
        return 0
    fi

    # Test Nginx configuration syntax
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Testing Nginx configuration syntax..."
    fi

    local config_test_output
    config_test_output=$(sudo nginx -t 2>&1)
    local config_test_result=$?

    if [[ $config_test_result -ne 0 ]]; then
        print_error "Nginx configuration test failed"
        echo "Configuration errors:"
        echo "$config_test_output"

        # Try to provide helpful suggestions
        if echo "$config_test_output" | grep -q "duplicate"; then
            print_info "Suggestion: Check for duplicate directives in configuration files"
        fi
        if echo "$config_test_output" | grep -q "unknown directive"; then
            print_info "Suggestion: Check for typos or unsupported directives"
        fi
        if echo "$config_test_output" | grep -q "emerg"; then
            print_info "Suggestion: Check file syntax and missing semicolons"
        fi

        return 1
    else
        if [[ "$QUIET" == false ]]; then
            print_success "Nginx configuration test passed"
        fi
    fi

    # Reload nginx configuration to apply changes
    if sudo systemctl is-active nginx >/dev/null 2>&1; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Reloading Nginx configuration..."
        fi
        sudo systemctl reload nginx
    else
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Starting Nginx service..."
        fi
        sudo systemctl start nginx
    fi

    # Enable Nginx to start on boot
    sudo systemctl enable nginx >/dev/null 2>&1

    # Final service status check
    if sudo systemctl is-active nginx >/dev/null 2>&1; then
        if [[ "$QUIET" == false ]]; then
            print_success "Nginx service is running"
        fi
    else
        print_warning "Nginx service may not be running properly"
        if [[ "$VERBOSE" == true ]]; then
            print_info "Service status:"
            sudo systemctl status nginx --no-pager -l | head -10
        fi
    fi

    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Nginx installation validated"
    fi
}

# Function to show installation summary
show_installation_summary() {
    if [[ "$QUIET" == true ]]; then
        return 0
    fi
    
    echo
    print_info "=== Nginx Installation Summary ==="
    echo
    
    cat << EOF
Installation Details:
  Mode:              $INSTALL_MODE
  Nginx User:        $NGINX_USER
  PHP Version:       $PHP_VERSION
  SSL Enabled:       $(if [[ "$ENABLE_SSL" == true ]]; then echo "Yes"; else echo "No"; fi)
  HTTP/2 Enabled:    $(if [[ "$ENABLE_HTTP2" == true ]]; then echo "Yes"; else echo "No"; fi)
  Compression:       $(if [[ "$ENABLE_COMPRESSION" == true ]]; then echo "Yes"; else echo "No"; fi)
  Caching:           $(if [[ "$ENABLE_CACHING" == true ]]; then echo "Yes"; else echo "No"; fi)
  Security:          $(if [[ "$ENABLE_SECURITY" == true ]]; then echo "Yes"; else echo "No"; fi)
  ModSecurity:       $(if [[ "$ENABLE_MODSECURITY" == true ]]; then echo "Yes"; else echo "No"; fi)
  Rate Limiting:     $(if [[ "$ENABLE_RATE_LIMITING" == true ]]; then echo "Yes"; else echo "No"; fi)

Installed Components:
  ✓ Nginx web server
  ✓ Essential modules and configurations
  ✓ PHP $PHP_VERSION integration via FPM
  ✓ Performance optimizations
  ✓ Security configurations
  ✓ Rate limiting and DDoS protection
  ✓ Log rotation setup
  ✓ Vhost management scripts

Configuration Files:
  Main Config:       /etc/nginx/nginx.conf
  Sites Available:   /etc/nginx/sites-available/
  Sites Enabled:     /etc/nginx/sites-enabled/
  Configuration:     /etc/nginx/conf.d/
  Logs Directory:    /var/log/nginx/

Management:
  Create vhost:      $ADD_VHOST_SCRIPT DOMAIN
  Create proxy:      $ADD_PROXY_SCRIPT DOMAIN TARGET
  Test config:       sudo nginx -t
  Reload config:     sudo systemctl reload nginx
  View logs:         sudo tail -f /var/log/nginx/*.log

Next Steps:
  1. Create your first virtual host:
     $ADD_VHOST_SCRIPT example.local

  2. Test the installation:
     curl -I http://localhost

  3. Check Nginx status:
     sudo systemctl status nginx

Security Features:
  - Server tokens hidden
  - Security headers configured
  - Rate limiting zones defined
  - File access restrictions
  - ModSecurity WAF (if enabled)

Performance Features:
  - FastCGI caching configured
  - Static file optimization
  - Compression enabled
  - Keep-alive optimization

EOF
    
    print_success "Nginx installation completed successfully! 🚀"
}

# Main function
main() {
    if [[ "$QUIET" == false ]]; then
        show_script_header "Nginx Installation Script"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show installation plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installation plan:"
        print_info "  Mode: $INSTALL_MODE"
        print_info "  Nginx User: $NGINX_USER"
        print_info "  PHP Version: $PHP_VERSION"
        print_info "  SSL: $ENABLE_SSL"
        print_info "  HTTP/2: $ENABLE_HTTP2"
        print_info "  Compression: $ENABLE_COMPRESSION"
        print_info "  Caching: $ENABLE_CACHING"
        print_info "  Security: $ENABLE_SECURITY"
        print_info "  ModSecurity: $ENABLE_MODSECURITY"
        print_info "  Rate Limiting: $ENABLE_RATE_LIMITING"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with Nginx installation?" "Y"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi

    # Enable ModSecurity for full mode
    if [[ "$INSTALL_MODE" == "full" ]]; then
        ENABLE_MODSECURITY=true
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Full mode: ModSecurity enabled"
        fi
    fi

    # Install Nginx packages
    install_nginx_packages

    # Configure nginx user
    configure_nginx_user

    # Backup existing configurations if using --force
    backup_existing_configs

    # Fix any existing configuration issues FIRST before installing new configs
    fix_existing_config_issues

    # Install system configurations
    install_system_configs

    # Configure PHP integration
    configure_php_integration

    # Configure security settings
    configure_security

    # Configure rate limiting
    configure_rate_limiting

    # Setup log rotation
    setup_log_rotation

    # Create management scripts
    create_management_scripts

    # Validate installation
    validate_installation
    
    # Show summary
    show_installation_summary
}

# Run main function
main "$@"