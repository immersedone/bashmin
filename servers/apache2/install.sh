#!/bin/bash
#
# Script: servers/apache2/install.sh
# Description: Install and configure Apache2 web server with bashmin integration
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
readonly APACHE_CONF_DIR="/etc/apache2"
readonly APACHE_SITES_AVAILABLE="$APACHE_CONF_DIR/sites-available"
readonly APACHE_SITES_ENABLED="$APACHE_CONF_DIR/sites-enabled"
readonly APACHE_CONF_AVAILABLE="$APACHE_CONF_DIR/conf-available"
readonly APACHE_CONF_ENABLED="$APACHE_CONF_DIR/conf-enabled"
readonly APACHE_MODS_AVAILABLE="$APACHE_CONF_DIR/mods-available"
readonly APACHE_MODS_ENABLED="$APACHE_CONF_DIR/mods-enabled"
readonly APACHE_LOG_DIR="/var/log/apache2"
readonly VHOST_EXAMPLE="$SCRIPT_DIR/vhost.config.example"
readonly ADD_VHOST_SCRIPT="$SCRIPT_DIR/add-vhost.sh"
readonly SYSTEM_CONFIGS="$PROJECT_ROOT/system/etc/apache2"

# Configuration variables
INSTALL_MODE="standard"
ENABLE_SSL=true
ENABLE_HTTP2=true
ENABLE_COMPRESSION=true
ENABLE_CACHING=true
ENABLE_SECURITY=true
PHP_VERSION="8.3"
FORCE_INSTALL=false
VERBOSE=false
DRY_RUN=false
QUIET=false

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

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Install and configure Apache2 web server with bashmin integration.

OPTIONS:
    --mode MODE             Installation mode: standard, minimal, full (default: $INSTALL_MODE)
    --php-version VERSION   PHP version to configure (default: $PHP_VERSION)
    --no-ssl                Skip SSL module installation
    --no-http2              Skip HTTP/2 module installation
    --no-compression        Skip compression modules
    --no-caching            Skip caching modules
    --no-security           Skip security enhancements
    --force                 Force reinstallation even if already installed
    --quiet                 Suppress non-essential output
    --verbose               Enable verbose output
    --dry-run               Show what would be installed without executing
    -h, --help              Show this help message

MODES:
    minimal                 Basic Apache2 installation with essential modules
    standard                Standard installation with PHP, SSL, and optimization
    full                    Complete installation with all modules and security

EXAMPLES:
    $0                                      # Standard installation
    $0 --mode full --verbose               # Full installation with details
    $0 --php-version 8.4 --no-ssl          # Custom PHP version without SSL
    $0 --dry-run                           # Preview installation

FEATURES:
    - Automatic Apache2 package installation
    - Essential module configuration (SSL, HTTP/2, rewrite, etc.)
    - PHP-FPM integration with configurable version
    - Performance optimization configurations
    - Security enhancements and headers
    - Bashmin vhost management integration
    - Log rotation and monitoring setup

POST-INSTALL:
    - Use add-vhost.sh to create new virtual hosts
    - Check configuration with: apache2ctl -t
    - Restart service with: systemctl restart apache2

EOF
}

# Function to check if Apache is installed
check_apache_installed() {
    if command -v apache2 >/dev/null 2>&1 && [[ -d "$APACHE_CONF_DIR" ]]; then
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
        print_info "This script requires sudo privileges. Please enter your password when prompted."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges"
            exit 1
        fi
    fi
    
    # Check OS compatibility
    if ! command -v apt >/dev/null 2>&1; then
        print_error "This script requires apt package manager (Ubuntu/Debian)"
        exit 1
    fi
    
    # Check if Apache is already installed
    if check_apache_installed && [[ "$FORCE_INSTALL" == false ]]; then
        if [[ "$QUIET" == false ]]; then
            print_warning "Apache2 appears to be already installed"
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

# Function to install Apache2 packages
install_apache_packages() {
    if [[ "$QUIET" == false ]]; then
        print_info "Installing Apache2 packages..."
    fi
    
    local packages=(
        "apache2"
        "apache2-utils"
    )
    
    # Add additional packages based on mode
    case "$INSTALL_MODE" in
        full)
            packages+=(
                "apache2-dev"
                "libapache2-mod-security2"
                "libapache2-mod-evasive"
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
            print_error "Failed to install package: $package"
            exit 1
        fi
    done
    
    if [[ "$QUIET" == false ]]; then
        print_success "Apache2 packages installed successfully"
    fi
}

# Function to enable Apache modules
enable_apache_modules() {
    if [[ "$QUIET" == false ]]; then
        print_info "Configuring Apache2 modules..."
    fi
    
    local modules=(
        "rewrite"
        "headers"
        "expires"
        "proxy"
        "proxy_fcgi"
    )
    
    # Add modules based on configuration
    if [[ "$ENABLE_SSL" == true ]]; then
        modules+=("ssl")
    fi
    
    if [[ "$ENABLE_HTTP2" == true ]]; then
        modules+=("http2")
    fi
    
    if [[ "$ENABLE_COMPRESSION" == true ]]; then
        modules+=("deflate" "brotli")
    fi
    
    case "$INSTALL_MODE" in
        full)
            modules+=(
                "security2"
                "evasive"
                "remoteip"
                "status"
                "info"
            )
            ;;
        standard)
            modules+=(
                "remoteip"
                "status"
            )
            ;;
    esac
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would enable modules: ${modules[*]}"
        return 0
    fi
    
    # Enable modules
    for module in "${modules[@]}"; do
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Enabling module: $module"
        fi
        
        if sudo a2enmod "$module" >/dev/null 2>&1; then
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_success "Enabled module: $module"
            fi
        else
            print_warning "Failed to enable module: $module (may not be available)"
        fi
    done
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
    
    # Install main apache2.conf if available
    if [[ -f "$SYSTEM_CONFIGS/apache2.conf" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Installing main Apache configuration..."
        fi
        sudo cp "$SYSTEM_CONFIGS/apache2.conf" "$APACHE_CONF_DIR/apache2.conf.new"
        sudo mv "$APACHE_CONF_DIR/apache2.conf" "$APACHE_CONF_DIR/apache2.conf.backup" 2>/dev/null || true
        sudo mv "$APACHE_CONF_DIR/apache2.conf.new" "$APACHE_CONF_DIR/apache2.conf"
    fi

    # Ensure Apache2 log directory exists with proper permissions
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Setting up Apache2 log directory..."
    fi
    sudo mkdir -p "$APACHE_LOG_DIR"
    sudo chown www-data:adm "$APACHE_LOG_DIR"
    sudo chmod 755 "$APACHE_LOG_DIR"

    # Create minimal ports.conf for Apache2 (ports will be added dynamically when vhosts are created)
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installing minimal ports configuration..."
    fi
    sudo tee "$APACHE_CONF_DIR/ports.conf" > /dev/null << 'PORTSEOF'
# Bashmin Apache2 Configuration
# Ports are added dynamically when virtual hosts are created
# Port range 8080-8082 reserved for PHP versions 8.2-8.4
# Listening on localhost only for security

# Default port to prevent "no listening sockets" error
# Using non-standard port to avoid conflicts
Listen 127.0.0.1:8080

# SSL support (will be used when SSL vhosts are created)
<IfModule ssl_module>
	Listen 127.0.0.1:8443 ssl
</IfModule>

<IfModule mod_gnutls.c>
	Listen 127.0.0.1:8443 ssl
</IfModule>

# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
PORTSEOF

    # Create a minimal default site to prevent "no virtual hosts" warnings
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Creating default site configuration..."
    fi
    sudo tee "$APACHE_SITES_AVAILABLE/000-bashmin-default.conf" > /dev/null << 'DEFAULTEOF'
<VirtualHost 127.0.0.1:8080>
    ServerName localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/default-error.log
    CustomLog ${APACHE_LOG_DIR}/default-access.log combined
</VirtualHost>
DEFAULTEOF

    # Enable the default site
    sudo a2ensite 000-bashmin-default >/dev/null 2>&1
    
    # Install optimization configurations
    if [[ -d "$SYSTEM_CONFIGS/conf-available" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Installing optimization configurations..."
        fi
        
        for conf_file in "$SYSTEM_CONFIGS/conf-available"/*.conf; do
            if [[ -f "$conf_file" ]]; then
                local conf_name=$(basename "$conf_file")
                sudo cp "$conf_file" "$APACHE_CONF_AVAILABLE/"
                
                # Enable optimization configs based on settings
                case "$conf_name" in
                    opt-deflate-gzip.conf)
                        [[ "$ENABLE_COMPRESSION" == true ]] && sudo a2enconf "$(basename "$conf_name" .conf)" >/dev/null 2>&1
                        ;;
                    opt-expires.conf|opt-cache-control.conf)
                        [[ "$ENABLE_CACHING" == true ]] && sudo a2enconf "$(basename "$conf_name" .conf)" >/dev/null 2>&1
                        ;;
                    *)
                        sudo a2enconf "$(basename "$conf_name" .conf)" >/dev/null 2>&1
                        ;;
                esac
            fi
        done
    fi
    
    # Install site examples
    if [[ -d "$SYSTEM_CONFIGS/sites-available" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Installing site configuration examples..."
        fi
        
        for site_file in "$SYSTEM_CONFIGS/sites-available"/*.conf; do
            if [[ -f "$site_file" ]]; then
                sudo cp "$site_file" "$APACHE_SITES_AVAILABLE/"
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
    
    # Create PHP configuration for Apache
    local php_conf_file="$APACHE_CONF_AVAILABLE/php${PHP_VERSION}-fpm.conf"
    
    sudo tee "$php_conf_file" > /dev/null << EOF
# PHP $PHP_VERSION FPM Configuration
<IfModule mod_proxy_fcgi.c>
    <FilesMatch ".+\.ph(p[3457]?|t|tml)$">
        SetHandler "proxy:unix:$php_socket|fcgi://localhost"
    </FilesMatch>
</IfModule>

# Optional: Enable status page
<IfModule mod_status.c>
    <Location "/fpm-status">
        SetHandler "proxy:unix:$php_socket|fcgi://localhost/status"
        Require local
    </Location>
    <Location "/fpm-ping">
        SetHandler "proxy:unix:$php_socket|fcgi://localhost/ping"
        Require local
    </Location>
</IfModule>
EOF
    
    # Enable PHP configuration
    sudo a2enconf "php${PHP_VERSION}-fpm" >/dev/null 2>&1
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "PHP $PHP_VERSION integration configured"
    fi
}

# Function to create add-vhost script
create_add_vhost_script() {
    if [[ "$QUIET" == false ]]; then
        print_info "Creating vhost management script..."
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create add-vhost.sh script"
        return 0
    fi
    
    # Create the add-vhost script
    cat > "$ADD_VHOST_SCRIPT" << 'EOF'
#!/bin/bash
#
# Script: servers/apache2/add-vhost.sh
# Description: Add new Apache2 virtual host using bashmin template
# Usage: ./add-vhost.sh [OPTIONS] DOMAIN
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly APACHE_SITES_AVAILABLE="/etc/apache2/sites-available"
readonly APACHE_SITES_ENABLED="/etc/apache2/sites-enabled"
readonly VHOST_TEMPLATE="$SCRIPT_DIR/vhost.config.example"
readonly DEFAULT_WEBROOT="/var/www/vhosts"
readonly DEFAULT_PHP_VERSION="8.3"

# Configuration variables
DOMAIN=""
WEBROOT=""
PHP_VERSION="$DEFAULT_PHP_VERSION"
ENABLE_SSL=true
PORT=8080
CREATE_DIRECTORY=true
UPDATE_HOSTS=true
FORCE=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --webroot)
            WEBROOT="$2"
            shift 2
            ;;
        --php-version)
            PHP_VERSION="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --no-ssl)
            ENABLE_SSL=false
            shift
            ;;
        --no-directory)
            CREATE_DIRECTORY=false
            shift
            ;;
        --no-hosts)
            UPDATE_HOSTS=false
            shift
            ;;
        --force)
            FORCE=true
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
            show_vhost_help
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_vhost_help
            exit 1
            ;;
        *)
            if [[ -z "$DOMAIN" ]]; then
                DOMAIN="$1"
            else
                print_error "Multiple domains specified: $DOMAIN and $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Function to show help
show_vhost_help() {
    cat << EOF
Usage: $0 [OPTIONS] DOMAIN

Create a new Apache2 virtual host configuration.

ARGUMENTS:
    DOMAIN                  Domain name for the virtual host (required)

OPTIONS:
    --webroot PATH          Custom webroot path (default: $DEFAULT_WEBROOT/DOMAIN/public)
    --php-version VERSION   PHP version to use (default: $DEFAULT_PHP_VERSION)
    --port PORT             Port to listen on (8080-8082, default: 8080)
    --no-ssl                Disable SSL configuration
    --no-directory          Don't create webroot directory
    --no-hosts              Don't update /etc/hosts file
    --force                 Overwrite existing configuration
    --quiet                 Suppress non-essential output
    --verbose               Enable verbose output
    --dry-run               Show what would be created without executing
    -h, --help              Show this help message

EXAMPLES:
    $0 example.local                        # Basic vhost
    $0 api.local --php-version 8.4          # Custom PHP version
    $0 app.local --webroot /custom/path     # Custom webroot
    $0 test.local --port 8081 --no-ssl     # Custom port, no SSL
    $0 php84.local --port 8082 --php-version 8.4  # PHP 8.4 on port 8082

NOTES:
    - Requires sudo privileges
    - Creates directory structure if needed
    - Updates /etc/hosts with 127.0.0.1 entry
    - Dynamically adds required ports to Apache2 configuration
    - Enables site automatically
    - Reloads Apache2 configuration
    - To remove vhost: sudo a2dissite DOMAIN && sudo rm /etc/apache2/sites-available/DOMAIN.conf

# Validate domain name
if [[ -z "$DOMAIN" ]]; then
    print_error "Domain name is required"
    show_vhost_help
    exit 1
fi

# Validate port range (8080-8082 for 3 latest PHP versions)
if [[ ! "$PORT" =~ ^808[0-2]$ ]]; then
    print_error "Invalid port: $PORT"
    print_info "Port must be in range 8080-8082 (one for each of the 3 latest PHP versions)"
    exit 1
fi

# Set default webroot if not specified
if [[ -z "$WEBROOT" ]]; then
    WEBROOT="$DEFAULT_WEBROOT/$DOMAIN/public"
fi

# Function to add port to ports.conf if not already present
add_port_to_config() {
    local port="$1"
    local ssl_port="$((port + 363))"  # 8080 -> 8443, 8081 -> 8444, 8082 -> 8445

    # Check if HTTP ports already exist (IPv4 and IPv6 localhost)
    if ! grep -q "^Listen 127.0.0.1:$port$" /etc/apache2/ports.conf; then
        sudo sed -i "/^# vim: syntax=apache/i\\Listen 127.0.0.1:$port" /etc/apache2/ports.conf
    fi
    if ! grep -q "^Listen \\[::1\\]:$port$" /etc/apache2/ports.conf; then
        sudo sed -i "/^# vim: syntax=apache/i\\Listen [::1]:$port" /etc/apache2/ports.conf
    fi

    # Check if SSL ports already exist (IPv4 and IPv6 localhost)
    if ! grep -q "Listen 127.0.0.1:$ssl_port ssl" /etc/apache2/ports.conf; then
        sudo sed -i "/<IfModule ssl_module>/a\\\\tListen 127.0.0.1:$ssl_port ssl" /etc/apache2/ports.conf
        sudo sed -i "/<IfModule mod_gnutls.c>/a\\\\tListen 127.0.0.1:$ssl_port ssl" /etc/apache2/ports.conf
    fi
    if ! grep -q "Listen \\[::1\\]:$ssl_port ssl" /etc/apache2/ports.conf; then
        sudo sed -i "/<IfModule ssl_module>/a\\\\tListen [::1]:$ssl_port ssl" /etc/apache2/ports.conf
        sudo sed -i "/<IfModule mod_gnutls.c>/a\\\\tListen [::1]:$ssl_port ssl" /etc/apache2/ports.conf
    fi
}

# Function to remove port from ports.conf if no vhosts use it
remove_port_from_config() {
    local port="$1"
    local ssl_port="$((port + 363))"

    # Check if any enabled sites use this port
    if ! grep -r ":$port>" /etc/apache2/sites-enabled/ >/dev/null 2>&1; then
        sudo sed -i "/^Listen 127.0.0.1:$port$/d" /etc/apache2/ports.conf
        sudo sed -i "/^Listen \\[::1\\]:$port$/d" /etc/apache2/ports.conf
        sudo sed -i "/Listen 127.0.0.1:$ssl_port ssl/d" /etc/apache2/ports.conf
        sudo sed -i "/Listen \\[::1\\]:$ssl_port ssl/d" /etc/apache2/ports.conf
    fi
}

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    print_info "This script requires sudo privileges. Please enter your password when prompted."
    if ! sudo -v; then
        print_error "Failed to obtain sudo privileges"
        exit 1
    fi
fi

# Check if template exists
if [[ ! -f "$VHOST_TEMPLATE" ]]; then
    print_error "Vhost template not found: $VHOST_TEMPLATE"
    exit 1
fi

# Check if site already exists
SITE_CONFIG="$APACHE_SITES_AVAILABLE/$DOMAIN.conf"
if [[ -f "$SITE_CONFIG" && "$FORCE" == false ]]; then
    print_error "Site configuration already exists: $SITE_CONFIG"
    print_info "Use --force to overwrite"
    exit 1
fi

if [[ "$QUIET" == false ]]; then
    print_info "Creating Apache2 virtual host for: $DOMAIN"
fi

# Create webroot directory
if [[ "$CREATE_DIRECTORY" == true ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create directory: $WEBROOT"
    else
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Creating webroot directory: $WEBROOT"
        fi
        sudo mkdir -p "$WEBROOT"
        sudo chown www-data:www-data "$WEBROOT"
        sudo chmod 755 "$WEBROOT"

        # Create basic index.php if it doesn't exist
        if [[ ! -f "$WEBROOT/index.php" ]]; then
            sudo tee "$WEBROOT/index.php" > /dev/null << INDEXEOF
<?php
echo "<h1>Welcome to $DOMAIN</h1>";
echo "<p>Server: " . \$_SERVER['SERVER_NAME'] . "</p>";
echo "<p>PHP Version: " . phpversion() . "</p>";
echo "<p>Document Root: " . \$_SERVER['DOCUMENT_ROOT'] . "</p>";
echo "<p>Current Time: " . date('Y-m-d H:i:s') . "</p>";
phpinfo();
?>
INDEXEOF
            sudo chown www-data:www-data "$WEBROOT/index.php"
        fi
    fi
fi

# Create site configuration from template
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would create site configuration: $SITE_CONFIG"
else
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Creating site configuration: $SITE_CONFIG"
    fi

    # Generate configuration from template
    sudo cp "$VHOST_TEMPLATE" "$SITE_CONFIG"

    # Replace placeholders
    sudo sed -i "s|ServerName php74.ti|ServerName $DOMAIN|g" "$SITE_CONFIG"
    sudo sed -i "s|127.0.0.1:8080|127.0.0.1:$PORT|g" "$SITE_CONFIG"
    sudo sed -i "s|/var/www/vhosts/php83-test/public|$WEBROOT|g" "$SITE_CONFIG"
    sudo sed -i "s|php8.3-fpm.sock|php${PHP_VERSION}-fpm.sock|g" "$SITE_CONFIG"
    sudo sed -i "s|php83.ti|$DOMAIN|g" "$SITE_CONFIG"

    # Add port to ports.conf if needed
    add_port_to_config "$PORT"

    # Enable the site
    sudo a2ensite "$DOMAIN" >/dev/null 2>&1
fi

# Update hosts file
if [[ "$UPDATE_HOSTS" == true ]]; then
    if [[ -x "$PROJECT_ROOT/hosts/update-hosts.sh" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would update /etc/hosts with: 127.0.0.1 $DOMAIN"
        else
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_info "Updating /etc/hosts file..."
            fi
            "$PROJECT_ROOT/hosts/update-hosts.sh" --quiet add 127.0.0.1 "$DOMAIN"
        fi
    else
        print_warning "Hosts update script not found, skipping hosts file update"
    fi
fi

# Test Apache configuration
if [[ "$DRY_RUN" == false ]]; then
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Testing Apache configuration..."
    fi

    if ! sudo apache2ctl -t >/dev/null 2>&1; then
        print_error "Apache configuration test failed"
        print_info "Rolling back changes..."
        sudo a2dissite "$DOMAIN" >/dev/null 2>&1 || true
        sudo rm -f "$SITE_CONFIG"
        remove_port_from_config "$PORT"
        exit 1
    fi

    # Reload Apache
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Reloading Apache2..."
    fi
    sudo systemctl reload apache2
fi

if [[ "$QUIET" == false ]]; then
    echo
    print_success "Virtual host created successfully! 🚀"
    echo
    print_info "=== Virtual Host Details ==="
    echo "Domain:       $DOMAIN"
    echo "Port:         $PORT"
    echo "Webroot:      $WEBROOT"
    echo "PHP Version:  $PHP_VERSION"
    echo "Config File:  $SITE_CONFIG"
    echo
    print_info "=== Next Steps ==="
    echo "• Visit: http://$DOMAIN:$PORT"
    echo "• Check logs: tail -f /var/log/apache2/$DOMAIN-*.log"
    echo "• Edit config: sudo nano $SITE_CONFIG"
    echo "• Disable site: sudo a2dissite $DOMAIN"
    echo
fi
EOF
    
    # Make script executable
    chmod +x "$ADD_VHOST_SCRIPT"
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Add-vhost script created: $ADD_VHOST_SCRIPT"
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
    local security_conf="$APACHE_CONF_AVAILABLE/bashmin-security.conf"
    
    sudo tee "$security_conf" > /dev/null << EOF
# Bashmin Security Configuration for Apache2

# Hide Apache version
ServerTokens Prod
ServerSignature Off

# Security headers
<IfModule mod_headers.c>
    # Security headers
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    
    # Remove server information
    Header unset Server
    Header unset X-Powered-By
</IfModule>

# Disable unnecessary HTTP methods
<Directory />
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>

# Protect sensitive files
<FilesMatch "(^\.|\.(log|bak|backup|old|tmp)$)">
    Require all denied
</FilesMatch>

# Disable server-status and server-info by default
<IfModule mod_status.c>
    <Location "/server-status">
        SetHandler server-status
        Require local
    </Location>
</IfModule>

<IfModule mod_info.c>
    <Location "/server-info">
        SetHandler server-info
        Require local
    </Location>
</IfModule>
EOF
    
    # Enable security configuration
    sudo a2enconf bashmin-security >/dev/null 2>&1
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Security settings configured"
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
    local system_logrotate="$PROJECT_ROOT/system/etc/logrotate.d/apache2"
    if [[ -f "$system_logrotate" ]]; then
        sudo cp "$system_logrotate" "/etc/logrotate.d/apache2"
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Log rotation configured from system template"
        fi
    fi
}

# Function to validate installation
validate_installation() {
    if [[ "$QUIET" == false ]]; then
        print_info "Validating Apache2 installation..."
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would validate installation"
        return 0
    fi
    
    # Test Apache configuration
    if ! sudo apache2ctl -t >/dev/null 2>&1; then
        print_error "Apache configuration test failed"
        return 1
    fi
    
    # Check if Apache is running
    if ! sudo systemctl is-active apache2 >/dev/null 2>&1; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Starting Apache2 service..."
        fi
        sudo systemctl start apache2
    fi
    
    # Enable Apache2 to start on boot
    sudo systemctl enable apache2 >/dev/null 2>&1
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Apache2 installation validated"
    fi
}

# Function to show installation summary
show_installation_summary() {
    if [[ "$QUIET" == true ]]; then
        return 0
    fi
    
    echo
    print_info "=== Apache2 Installation Summary ==="
    echo
    
    cat << EOF
Installation Details:
  Mode:              $INSTALL_MODE
  PHP Version:       $PHP_VERSION
  SSL Enabled:       $(if [[ "$ENABLE_SSL" == true ]]; then echo "Yes"; else echo "No"; fi)
  HTTP/2 Enabled:    $(if [[ "$ENABLE_HTTP2" == true ]]; then echo "Yes"; else echo "No"; fi)
  Compression:       $(if [[ "$ENABLE_COMPRESSION" == true ]]; then echo "Yes"; else echo "No"; fi)
  Caching:           $(if [[ "$ENABLE_CACHING" == true ]]; then echo "Yes"; else echo "No"; fi)
  Security:          $(if [[ "$ENABLE_SECURITY" == true ]]; then echo "Yes"; else echo "No"; fi)

Installed Components:
  ✓ Apache2 web server
  ✓ Essential modules (rewrite, headers, proxy, etc.)
  ✓ PHP $PHP_VERSION integration via FPM
  ✓ Performance optimizations
  ✓ Security configurations
  ✓ Log rotation setup
  ✓ Vhost management script

Configuration Files:
  Main Config:       /etc/apache2/apache2.conf
  Sites Available:   /etc/apache2/sites-available/
  Sites Enabled:     /etc/apache2/sites-enabled/
  Logs Directory:    /var/log/apache2/

Management:
  Create vhost:      $ADD_VHOST_SCRIPT DOMAIN
  Test config:       sudo apache2ctl -t
  Reload config:     sudo systemctl reload apache2
  View logs:         sudo tail -f /var/log/apache2/*.log

Next Steps:
  1. Create your first virtual host:
     $ADD_VHOST_SCRIPT example.local

  2. Test the installation:
     curl -I http://localhost:8080

  3. Check Apache status:
     sudo systemctl status apache2

Security Notes:
  - Server tokens hidden for security
  - Security headers configured
  - Sensitive files protected
  - Only essential HTTP methods allowed

EOF
    
    print_success "Apache2 installation completed successfully! 🚀"
}

# Main function
main() {
    if [[ "$QUIET" == false ]]; then
        show_script_header "Apache2 Installation Script"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show installation plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installation plan:"
        print_info "  Mode: $INSTALL_MODE"
        print_info "  PHP Version: $PHP_VERSION"
        print_info "  SSL: $ENABLE_SSL"
        print_info "  HTTP/2: $ENABLE_HTTP2"
        print_info "  Compression: $ENABLE_COMPRESSION"
        print_info "  Caching: $ENABLE_CACHING"
        print_info "  Security: $ENABLE_SECURITY"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with Apache2 installation?" "Y"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Install Apache packages
    install_apache_packages
    
    # Enable Apache modules
    enable_apache_modules
    
    # Install system configurations
    install_system_configs
    
    # Configure PHP integration
    configure_php_integration
    
    # Configure security settings
    configure_security
    
    # Setup log rotation
    setup_log_rotation
    
    # Create vhost management script
    create_add_vhost_script
    
    # Validate installation
    validate_installation
    
    # Show summary
    show_installation_summary
}

# Run main function
main "$@"