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
