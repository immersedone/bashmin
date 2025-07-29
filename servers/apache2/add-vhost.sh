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
            show_help
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_help
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
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] DOMAIN

Create a new Apache2 virtual host configuration.

ARGUMENTS:
    DOMAIN                  Domain name for the virtual host (required)

OPTIONS:
    --webroot PATH          Custom webroot path (default: $DEFAULT_WEBROOT/DOMAIN/public)
    --php-version VERSION   PHP version to use (default: $DEFAULT_PHP_VERSION)
    --port PORT             Port to listen on (default: 8080)
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

NOTES:
    - Requires sudo privileges
    - Creates directory structure if needed
    - Updates /etc/hosts with 127.0.0.1 entry
    - Enables site automatically
    - Reloads Apache2 configuration

EOF
}

# Function to validate domain name
validate_domain() {
    local domain="$1"
    
    # Basic domain validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        print_error "Invalid domain name: $domain"
        print_info "Domain names must contain only letters, numbers, dots, and hyphens"
        exit 1
    fi
    
    # Check for common mistakes
    if [[ "$domain" =~ ^https?:// ]]; then
        print_error "Domain should not include protocol (http/https)"
        exit 1
    fi
    
    if [[ "$domain" =~ / ]]; then
        print_error "Domain should not include paths"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Checking prerequisites..."
    fi
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        exit 1
    fi
    
    # Check if Apache is installed
    if ! command -v apache2 >/dev/null 2>&1; then
        print_error "Apache2 is not installed"
        print_info "Run the Apache2 install script first: $PROJECT_ROOT/servers/apache2/install.sh"
        exit 1
    fi
    
    # Check if Apache is running
    if ! sudo systemctl is-active apache2 >/dev/null 2>&1; then
        print_warning "Apache2 is not running"
        if [[ "$DRY_RUN" == false ]] && confirm_action "Start Apache2 service?" "Y"; then
            sudo systemctl start apache2
        fi
    fi
    
    # Check if template exists
    if [[ ! -f "$VHOST_TEMPLATE" ]]; then
        print_error "Vhost template not found: $VHOST_TEMPLATE"
        print_info "Make sure the Apache2 installation is complete"
        exit 1
    fi
    
    # Check if PHP-FPM is available for the specified version
    local php_socket="/run/php/php${PHP_VERSION}-fpm.sock"
    if [[ ! -S "$php_socket" ]]; then
        print_warning "PHP-FPM $PHP_VERSION socket not found: $php_socket"
        print_info "Make sure PHP $PHP_VERSION FPM is installed and running"
    fi
}

# Function to check if site already exists
check_site_exists() {
    local domain="$1"
    local site_config="$APACHE_SITES_AVAILABLE/$domain.conf"
    
    if [[ -f "$site_config" && "$FORCE" == false ]]; then
        print_error "Site configuration already exists: $site_config"
        print_info "Use --force to overwrite existing configuration"
        exit 1
    fi
    
    # Check if site is enabled
    if [[ -L "$APACHE_SITES_ENABLED/$domain.conf" ]]; then
        if [[ "$FORCE" == false ]]; then
            print_error "Site is already enabled: $domain"
            print_info "Use --force to overwrite existing configuration"
            exit 1
        else
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_info "Disabling existing site: $domain"
            fi
            if [[ "$DRY_RUN" == false ]]; then
                sudo a2dissite "$domain" >/dev/null 2>&1 || true
            fi
        fi
    fi
}

# Function to create webroot directory
create_webroot() {
    local webroot="$1"
    local domain="$2"
    
    if [[ "$CREATE_DIRECTORY" == false ]]; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create directory: $webroot"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Creating webroot directory: $webroot"
    fi
    
    # Create directory structure
    sudo mkdir -p "$webroot"
    sudo chown www-data:www-data "$webroot"
    sudo chmod 755 "$webroot"
    
    # Create parent directory with proper permissions
    local parent_dir=$(dirname "$webroot")
    if [[ "$parent_dir" == "$DEFAULT_WEBROOT/$domain" ]]; then
        sudo chown www-data:www-data "$parent_dir"
        sudo chmod 755 "$parent_dir"
    fi
    
    # Create basic index.php if it doesn't exist
    if [[ ! -f "$webroot/index.php" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Creating default index.php file"
        fi
        
        sudo tee "$webroot/index.php" > /dev/null << EOF
<?php
/**
 * Default index page for $domain
 * Generated by bashmin Apache2 vhost script
 */

// Prevent direct access to this file in production
if (isset(\$_GET['info']) && \$_GET['info'] === 'php') {
    phpinfo();
    exit;
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to <?= htmlspecialchars('$domain') ?></title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
               line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 2rem; }
        .header { background: #f8f9fa; padding: 2rem; border-radius: 8px; margin-bottom: 2rem; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 1rem; }
        .info-card { background: #fff; border: 1px solid #dee2e6; padding: 1rem; border-radius: 6px; }
        .info-card h3 { margin-top: 0; color: #495057; }
        .success { color: #28a745; }
        .warning { color: #ffc107; }
        code { background: #f8f9fa; padding: 0.2rem 0.4rem; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="header">
        <h1 class="success">🚀 Welcome to <?= htmlspecialchars('$domain') ?></h1>
        <p>Your Apache2 virtual host is configured and running successfully!</p>
    </div>

    <div class="info-grid">
        <div class="info-card">
            <h3>Server Information</h3>
            <p><strong>Domain:</strong> <?= htmlspecialchars(\$_SERVER['SERVER_NAME'] ?? 'Unknown') ?></p>
            <p><strong>Server IP:</strong> <?= htmlspecialchars(\$_SERVER['SERVER_ADDR'] ?? 'Unknown') ?></p>
            <p><strong>Port:</strong> <?= htmlspecialchars(\$_SERVER['SERVER_PORT'] ?? 'Unknown') ?></p>
            <p><strong>Protocol:</strong> <?= htmlspecialchars(\$_SERVER['SERVER_PROTOCOL'] ?? 'Unknown') ?></p>
        </div>

        <div class="info-card">
            <h3>PHP Information</h3>
            <p><strong>PHP Version:</strong> <?= phpversion() ?></p>
            <p><strong>PHP SAPI:</strong> <?= php_sapi_name() ?></p>
            <p><strong>Memory Limit:</strong> <?= ini_get('memory_limit') ?></p>
            <p><strong>Max Execution Time:</strong> <?= ini_get('max_execution_time') ?>s</p>
        </div>

        <div class="info-card">
            <h3>Document Root</h3>
            <p><strong>Path:</strong> <code><?= htmlspecialchars(\$_SERVER['DOCUMENT_ROOT'] ?? 'Unknown') ?></code></p>
            <p><strong>Script:</strong> <code><?= htmlspecialchars(\$_SERVER['SCRIPT_FILENAME'] ?? 'Unknown') ?></code></p>
        </div>

        <div class="info-card">
            <h3>Request Information</h3>
            <p><strong>Method:</strong> <?= htmlspecialchars(\$_SERVER['REQUEST_METHOD'] ?? 'Unknown') ?></p>
            <p><strong>URI:</strong> <?= htmlspecialchars(\$_SERVER['REQUEST_URI'] ?? 'Unknown') ?></p>
            <p><strong>User Agent:</strong> <?= htmlspecialchars(substr(\$_SERVER['HTTP_USER_AGENT'] ?? 'Unknown', 0, 50)) ?>...</p>
            <p><strong>Remote IP:</strong> <?= htmlspecialchars(\$_SERVER['REMOTE_ADDR'] ?? 'Unknown') ?></p>
        </div>
    </div>

    <div style="margin-top: 2rem; padding: 1rem; background: #f8f9fa; border-radius: 6px;">
        <h3>Quick Links</h3>
        <ul>
            <li><a href="?info=php">View PHP Info</a> (detailed PHP configuration)</li>
            <li><a href="/server-status">Server Status</a> (if mod_status is enabled)</li>
            <li><a href="/server-info">Server Info</a> (if mod_info is enabled)</li>
        </ul>

        <h3>Next Steps</h3>
        <ol>
            <li>Replace this file with your application code</li>
            <li>Configure your database connections</li>
            <li>Set up SSL certificates if needed</li>
            <li>Configure any additional Apache modules</li>
        </ol>

        <p><small>Generated on <?= date('Y-m-d H:i:s') ?> by bashmin Apache2 vhost script</small></p>
    </div>
</body>
</html>
EOF
        
        sudo chown www-data:www-data "$webroot/index.php"
        sudo chmod 644 "$webroot/index.php"
    fi
}

# Function to create site configuration
create_site_config() {
    local domain="$1"
    local webroot="$2"
    local php_version="$3"
    local port="$4"
    
    local site_config="$APACHE_SITES_AVAILABLE/$domain.conf"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create site configuration: $site_config"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Creating site configuration: $site_config"
    fi
    
    # Generate configuration from template
    sudo cp "$VHOST_TEMPLATE" "$site_config"
    
    # Replace placeholders in the configuration
    sudo sed -i "s|{DOMAIN_NAME}|$domain|g" "$site_config"
    sudo sed -i "s|{PORT}|$port|g" "$site_config"
    sudo sed -i "s|{DOCUMENT_ROOT}|$webroot|g" "$site_config"
    sudo sed -i "s|{PHP_VERSION}|$php_version|g" "$site_config"
    sudo sed -i "s|127.0.0.1:8080|127.0.0.1:$port|g" "$site_config"
    
    # Set default server admin if not specified
    local server_admin="admin@$domain"
    sudo sed -i "s|admin@{DOMAIN_NAME}|$server_admin|g" "$site_config"
    
    # Update file header with current information
    sudo sed -i "s|File: vhost.config.example|File: $domain.conf|g" "$site_config"
    sudo sed -i "s|Last Modified: bashmin (29/07/2025)|Last Modified: bashmin ($(date '+%d/%m/%Y'))|g" "$site_config"
    
    # Add custom error pages if enabled
    if [[ "$ENABLE_SSL" == true ]]; then
        # Add SSL-related configurations (placeholder for future SSL support)
        sudo sed -i '/CustomLog.*combined/a\\n    # SSL Configuration (placeholder)\n    # SSLEngine on\n    # SSLCertificateFile /etc/ssl/certs/'$domain'.crt\n    # SSLCertificateKeyFile /etc/ssl/private/'$domain'.key' "$site_config"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Site configuration created: $site_config"
    fi
}

# Function to enable site
enable_site() {
    local domain="$1"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would enable site: $domain"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Enabling site: $domain"
    fi
    
    if sudo a2ensite "$domain" >/dev/null 2>&1; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Site enabled: $domain"
        fi
    else
        print_error "Failed to enable site: $domain"
        exit 1
    fi
}

# Function to update hosts file
update_hosts_file() {
    local domain="$1"
    
    if [[ "$UPDATE_HOSTS" == false ]]; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would update /etc/hosts with: 127.0.0.1 $domain"
        return 0
    fi
    
    # Use bashmin hosts script if available
    if [[ -x "$PROJECT_ROOT/hosts/update-hosts.sh" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Updating /etc/hosts file..."
        fi
        
        if "$PROJECT_ROOT/hosts/update-hosts.sh" --quiet add 127.0.0.1 "$domain"; then
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_success "Hosts file updated"
            fi
        else
            print_warning "Failed to update hosts file automatically"
        fi
    else
        # Fallback manual method
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Adding entry to /etc/hosts manually..."
        fi
        
        if ! grep -q "127.0.0.1.*$domain" /etc/hosts; then
            echo "127.0.0.1    $domain" | sudo tee -a /etc/hosts >/dev/null
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_success "Added to /etc/hosts: 127.0.0.1 $domain"
            fi
        else
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_info "Entry already exists in /etc/hosts"
            fi
        fi
    fi
}

# Function to test Apache configuration
test_apache_config() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test Apache configuration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Testing Apache configuration..."
    fi
    
    if sudo apache2ctl -t >/dev/null 2>&1; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Apache configuration test passed"
        fi
        return 0
    else
        print_error "Apache configuration test failed"
        
        # Show the actual error
        if [[ "$VERBOSE" == true ]]; then
            print_info "Configuration errors:"
            sudo apache2ctl -t 2>&1 | head -10
        fi
        
        return 1
    fi
}

# Function to reload Apache
reload_apache() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would reload Apache2"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Reloading Apache2..."
    fi
    
    if sudo systemctl reload apache2; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Apache2 reloaded successfully"
        fi
    else
        print_error "Failed to reload Apache2"
        exit 1
    fi
}

# Function to show completion summary
show_completion_summary() {
    if [[ "$QUIET" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    local url_protocol="http"
    local url_port=""
    
    if [[ "$PORT" != "80" ]]; then
        url_port=":$PORT"
    fi
    
    echo
    print_success "Virtual host created successfully! 🚀"
    echo
    print_info "=== Virtual Host Details ==="
    cat << EOF
Domain:         $DOMAIN
Webroot:        $WEBROOT
PHP Version:    $PHP_VERSION
Port:           $PORT
Config File:    $APACHE_SITES_AVAILABLE/$DOMAIN.conf
Log Files:      /var/log/apache2/$DOMAIN-*.log

EOF
    
    print_info "=== Quick Access ==="
    cat << EOF
Website URL:    $url_protocol://$DOMAIN$url_port
Test Page:      $url_protocol://$DOMAIN$url_port/
PHP Info:       $url_protocol://$DOMAIN$url_port/?info=php

EOF
    
    print_info "=== Management Commands ==="
    cat << EOF
View logs:      sudo tail -f /var/log/apache2/$DOMAIN-*.log
Edit config:    sudo nano $APACHE_SITES_AVAILABLE/$DOMAIN.conf
Disable site:   sudo a2dissite $DOMAIN && sudo systemctl reload apache2
Test config:    sudo apache2ctl -t
Reload Apache:  sudo systemctl reload apache2

EOF
    
    print_info "=== Next Steps ==="
    cat << EOF
1. Visit your site: $url_protocol://$DOMAIN$url_port
2. Upload your application files to: $WEBROOT
3. Configure database connections as needed
4. Set up SSL certificates for production use

EOF
    
    print_info "🎉 Your virtual host is ready to use!"
}

# Main function
main() {
    # Validate domain name
    if [[ -z "$DOMAIN" ]]; then
        print_error "Domain name is required"
        show_help
        exit 1
    fi
    
    validate_domain "$DOMAIN"
    
    # Set default webroot if not specified
    if [[ -z "$WEBROOT" ]]; then
        WEBROOT="$DEFAULT_WEBROOT/$DOMAIN/public"
    fi
    
    if [[ "$QUIET" == false ]]; then
        show_script_header "Apache2 Virtual Host Creator"
        print_info "Creating virtual host for: $DOMAIN"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check if site already exists
    check_site_exists "$DOMAIN"
    
    # Show creation plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Virtual host creation plan:"
        print_info "  Domain: $DOMAIN"
        print_info "  Webroot: $WEBROOT"
        print_info "  PHP Version: $PHP_VERSION"
        print_info "  Port: $PORT"
        print_info "  Create Directory: $CREATE_DIRECTORY"
        print_info "  Update Hosts: $UPDATE_HOSTS"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with virtual host creation?" "Y"; then
            print_info "Virtual host creation cancelled"
            exit 0
        fi
    fi
    
    # Create webroot directory
    create_webroot "$WEBROOT" "$DOMAIN"
    
    # Create site configuration
    create_site_config "$DOMAIN" "$WEBROOT" "$PHP_VERSION" "$PORT"
    
    # Enable the site
    enable_site "$DOMAIN"
    
    # Update hosts file
    update_hosts_file "$DOMAIN"
    
    # Test Apache configuration
    if ! test_apache_config; then
        print_error "Configuration test failed, rolling back changes..."
        
        # Rollback changes
        if [[ "$DRY_RUN" == false ]]; then
            sudo a2dissite "$DOMAIN" >/dev/null 2>&1 || true
            sudo rm -f "$APACHE_SITES_AVAILABLE/$DOMAIN.conf"
        fi
        
        exit 1
    fi
    
    # Reload Apache
    reload_apache
    
    # Show completion summary
    show_completion_summary
}

# Run main function
main "$@"