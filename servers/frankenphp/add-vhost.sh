#!/bin/bash
#
# Script: servers/frankenphp/add-vhost.sh
# Description: Add virtual host configuration for FrankenPHP server
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
readonly FRANKENPHP_SERVICE="frankenphp"
readonly VHOSTS_DIR="/etc/frankenphp/vhosts"
readonly WEB_ROOT="/var/www/vhosts"
readonly DEFAULT_PHP_VERSION="8.3"

# Configuration variables
DOMAIN=""
DOCUMENT_ROOT=""
PHP_VERSION=""
HTTP_PORT="8100"
HTTPS_PORT="8143"
ENABLE_SSL=false
SSL_EMAIL=""
TEMPLATE_TYPE="php"
CREATE_DIRECTORIES=true
VERBOSE=false
DRY_RUN=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -r|--root)
            DOCUMENT_ROOT="$2"
            shift 2
            ;;
        --php-version)
            PHP_VERSION="$2"
            shift 2
            ;;
        --http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --https-port)
            HTTPS_PORT="$2"
            shift 2
            ;;
        --ssl)
            ENABLE_SSL=true
            shift
            ;;
        --ssl-email)
            SSL_EMAIL="$2"
            ENABLE_SSL=true
            shift 2
            ;;
        --template)
            TEMPLATE_TYPE="$2"
            shift 2
            ;;
        --no-directories)
            CREATE_DIRECTORIES=false
            shift
            ;;
        --force)
            FORCE=true
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
            # Positional argument (domain)
            if [[ -z "$DOMAIN" ]]; then
                DOMAIN="$1"
            else
                print_error "Multiple domains specified: $DOMAIN, $1"
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

Add virtual host configuration for FrankenPHP server.

ARGUMENTS:
    DOMAIN                  Domain name for the virtual host (required)

OPTIONS:
    -d, --domain DOMAIN     Domain name (alternative to positional arg)
    -r, --root PATH         Custom document root path
    --php-version VERSION   PHP version to use (default: $DEFAULT_PHP_VERSION)
    --http-port PORT        HTTP port (default: 8100, range: 8100-8199)
    --https-port PORT       HTTPS port (default: 8143, range: 8100-8199)
    --ssl                   Enable SSL/TLS with Let's Encrypt
    --ssl-email EMAIL       Email for Let's Encrypt SSL certificate
    --template TYPE         Virtual host template: php, static, proxy (default: php)
    --no-directories        Don't create web directories
    --force                 Force creation even if vhost exists
    --verbose              Enable verbose output
    --dry-run              Show what would be done without executing
    -h, --help             Show this help message

TEMPLATES:
    php                    PHP application with FrankenPHP
    static                 Static file serving only
    proxy                  Reverse proxy configuration

EXAMPLES:
    $0 example.com                           # Basic PHP virtual host
    $0 --ssl --ssl-email me@example.com example.com  # With SSL
    $0 --template static static.example.com  # Static file host
    $0 --php-version 8.2 app.example.com     # Specific PHP version
    $0 --root /custom/path example.com       # Custom document root
    $0 --dry-run --verbose example.com       # Test configuration

NOTES:
    - Requires sudo privileges
    - Creates directories under $WEB_ROOT/DOMAIN/
    - Automatically reloads FrankenPHP service
    - SSL certificates are obtained automatically with Let's Encrypt

EOF
}

# Function to validate domain name
validate_domain() {
    if [[ -z "$DOMAIN" ]]; then
        print_error "No domain specified"
        show_help
        exit 1
    fi
    
    # Basic domain validation
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$ ]]; then
        print_error "Invalid domain name: $DOMAIN"
        print_info "Domain must contain only letters, numbers, hyphens, and dots"
        exit 1
    fi
    
    # Check if domain is localhost or IP (no SSL)
    if [[ "$DOMAIN" == "localhost" || "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if [[ "$ENABLE_SSL" == true ]]; then
            print_warning "SSL disabled for localhost/IP addresses"
            ENABLE_SSL=false
        fi
    fi
    
    print_success "Domain validation passed: $DOMAIN"

    # Validate port ranges (8100-8199)
    if [[ ! "$HTTP_PORT" =~ ^81[0-9]{2}$ ]]; then
        print_error "Invalid HTTP port: $HTTP_PORT"
        print_info "HTTP port must be in range 8100-8199"
        exit 1
    fi

    if [[ "$ENABLE_SSL" == true ]] && [[ ! "$HTTPS_PORT" =~ ^81[0-9]{2}$ ]]; then
        print_error "Invalid HTTPS port: $HTTPS_PORT"
        print_info "HTTPS port must be in range 8100-8199"
        exit 1
    fi

    if [[ "$HTTP_PORT" == "$HTTPS_PORT" ]]; then
        print_error "HTTP and HTTPS ports cannot be the same"
        exit 1
    fi

    print_success "Port configuration validated: HTTP=$HTTP_PORT, HTTPS=$HTTPS_PORT"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root"
    elif ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. Please enter your password when prompted."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges"
            exit 1
        fi
    fi
    
    # Check if FrankenPHP is installed
    if ! command -v frankenphp &> /dev/null; then
        print_error "FrankenPHP is not installed"
        print_info "Install with: ./install.sh"
        exit 1
    fi
    
    # Check if FrankenPHP service exists
    if ! sudo systemctl list-unit-files | grep -q "$FRANKENPHP_SERVICE.service"; then
        print_error "FrankenPHP service not found"
        print_info "Install FrankenPHP service with: ./install.sh"
        exit 1
    fi
    
    # Check if vhosts directory exists
    if [[ ! -d "$VHOSTS_DIR" ]]; then
        print_error "FrankenPHP vhosts directory not found: $VHOSTS_DIR"
        print_info "Install FrankenPHP first with: ./install.sh"
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Function to setup defaults
setup_defaults() {
    # Set default document root
    if [[ -z "$DOCUMENT_ROOT" ]]; then
        DOCUMENT_ROOT="$WEB_ROOT/$DOMAIN"
    fi
    
    # Set default PHP version
    if [[ -z "$PHP_VERSION" ]]; then
        PHP_VERSION="$DEFAULT_PHP_VERSION"
    fi
    
    # Prompt for SSL email if SSL enabled but no email provided
    if [[ "$ENABLE_SSL" == true && -z "$SSL_EMAIL" ]]; then
        read -p "Enter email for Let's Encrypt SSL certificate: " SSL_EMAIL
        if [[ -z "$SSL_EMAIL" ]]; then
            print_error "Email required for SSL certificate"
            exit 1
        fi
    fi
}

# Function to check if virtual host already exists
check_existing_vhost() {
    local vhost_file="$VHOSTS_DIR/$DOMAIN.conf"
    
    if [[ -f "$vhost_file" && "$FORCE" == false ]]; then
        print_warning "Virtual host already exists: $vhost_file"
        if ! confirm_action "Overwrite existing virtual host?"; then
            print_info "Virtual host creation cancelled"
            exit 0
        fi
    fi
}

# Function to create web directories
create_web_directories() {
    if [[ "$CREATE_DIRECTORIES" == false ]]; then
        print_info "Skipping directory creation (--no-directories)"
        return 0
    fi
    
    print_info "Creating web directories..."
    
    local directories=(
        "$DOCUMENT_ROOT"
        "$DOCUMENT_ROOT/public"
        "$DOCUMENT_ROOT/logs"
        "$DOCUMENT_ROOT/tmp"
    )
    
    for dir in "${directories[@]}"; do
        execute_command "sudo mkdir -p '$dir'" "Creating directory: $dir"
    done
    
    # Set proper ownership and permissions
    execute_command "sudo chown -R www-data:www-data '$DOCUMENT_ROOT'" "Setting directory ownership"
    execute_command "sudo chmod -R 755 '$DOCUMENT_ROOT'" "Setting directory permissions"
    
    # Create a sample index file
    create_sample_files
    
    print_success "Web directories created successfully"
}

# Function to create sample files
create_sample_files() {
    local index_file="$DOCUMENT_ROOT/public/index.php"
    
    if [[ "$TEMPLATE_TYPE" == "static" ]]; then
        index_file="$DOCUMENT_ROOT/public/index.html"
        
        execute_command "sudo tee '$index_file' > /dev/null" "Creating sample HTML file" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to $DOMAIN</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; }
        .domain { color: #3498db; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌐 Welcome to <span class="domain">$DOMAIN</span></h1>
        <p>Your static website is now live!</p>
        <p>Edit this file at: <code>$DOCUMENT_ROOT/public/index.html</code></p>
    </div>
</body>
</html>
EOF
    else
        execute_command "sudo tee '$index_file' > /dev/null" "Creating sample PHP file" <<EOF
<?php
\$domain = '$DOMAIN';
\$document_root = '$DOCUMENT_ROOT/public';
\$php_version = PHP_VERSION;
\$server_software = \$_SERVER['SERVER_SOFTWARE'] ?? 'Unknown';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to <?= htmlspecialchars(\$domain) ?></title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; text-align: center; }
        .info { background: #ecf0f1; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .success { background: #d5edda; border: 1px solid #c3e6cb; color: #155724; }
        .domain { color: #3498db; font-weight: bold; }
        .code { background: #f8f9fa; border: 1px solid #e9ecef; padding: 10px; border-radius: 4px; font-family: monospace; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Welcome to <span class="domain"><?= htmlspecialchars(\$domain) ?></span></h1>
        
        <div class="info success">
            <h3>✅ Virtual Host Active</h3>
            <p>Your FrankenPHP virtual host is working correctly!</p>
        </div>
        
        <div class="info">
            <h3>📊 Server Information</h3>
            <ul>
                <li><strong>Domain:</strong> <?= htmlspecialchars(\$domain) ?></li>
                <li><strong>Document Root:</strong> <?= htmlspecialchars(\$document_root) ?></li>
                <li><strong>PHP Version:</strong> <?= htmlspecialchars(\$php_version) ?></li>
                <li><strong>Server:</strong> <?= htmlspecialchars(\$server_software) ?></li>
            </ul>
        </div>
        
        <div class="info">
            <h3>📁 File Structure</h3>
            <div class="code">
$DOCUMENT_ROOT/<br>
├── public/          # Web accessible files<br>
│   └── index.php    # This file<br>
├── logs/           # Application logs<br>
└── tmp/            # Temporary files
            </div>
        </div>
        
        <div class="info">
            <h3>🔧 Next Steps</h3>
            <ul>
                <li>Upload your application files to <code>$DOCUMENT_ROOT/public/</code></li>
                <li>Configure your database connection</li>
                <li>Set up SSL with <code>--ssl</code> option</li>
                <li>Check logs: <code>sudo journalctl -u frankenphp -f</code></li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF
    fi
    
    execute_command "sudo chown www-data:www-data '$index_file'" "Setting index file ownership"
}

# Function to generate virtual host configuration
generate_vhost_config() {
    local vhost_file="$VHOSTS_DIR/$DOMAIN.conf"
    
    print_info "Generating virtual host configuration..."
    
    case "$TEMPLATE_TYPE" in
        "php")
            generate_php_vhost_config "$vhost_file"
            ;;
        "static")
            generate_static_vhost_config "$vhost_file"
            ;;
        "proxy")
            generate_proxy_vhost_config "$vhost_file"
            ;;
        *)
            print_error "Unknown template type: $TEMPLATE_TYPE"
            exit 1
            ;;
    esac
    
    # Set proper permissions
    execute_command "sudo chown root:root '$vhost_file'" "Setting vhost file ownership"
    execute_command "sudo chmod 644 '$vhost_file'" "Setting vhost file permissions"
    
    print_success "Virtual host configuration created: $vhost_file"
}

# Function to generate PHP virtual host configuration
generate_php_vhost_config() {
    local vhost_file="$1"
    
    local ssl_config=""
    if [[ "$ENABLE_SSL" == true ]]; then
        ssl_config="tls $SSL_EMAIL"
    fi
    
    execute_command "sudo tee '$vhost_file' > /dev/null" "Creating PHP vhost configuration" <<EOF
# Virtual Host: $DOMAIN
# Created: $(date)
# Type: PHP Application
# Ports: HTTP=$HTTP_PORT$(if [[ "$ENABLE_SSL" == true ]]; then echo ", HTTPS=$HTTPS_PORT"; fi)

127.0.0.1:$HTTP_PORT$(if [[ "$ENABLE_SSL" == true ]]; then echo ", 127.0.0.1:$HTTPS_PORT"; fi) {
	bind 127.0.0.1
$(if [[ "$ENABLE_SSL" == true ]]; then echo "    $ssl_config"; fi)
    
    # Document root
    root * $DOCUMENT_ROOT/public
    
    # PHP handling with FrankenPHP
    php_server
    
    # File server for static assets
    file_server
    
    # Logging
    log {
        output file $DOCUMENT_ROOT/logs/access.log
        format single_field common_log
    }
    
    # Error handling
    handle_errors {
        @4xx expression {http.error.status_code} >= 400 && {http.error.status_code} < 500
        @5xx expression {http.error.status_code} >= 500 && {http.error.status_code} < 600
        
        rewrite @4xx /error/4xx.html
        rewrite @5xx /error/5xx.html
        file_server
    }
    
    # Security headers
    header {
        # Remove server information
        -Server
        
        # Security headers
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
        
$(if [[ "$ENABLE_SSL" == true ]]; then cat <<EOL
        # HTTPS security headers
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
EOL
fi)
    }
    
    # Deny access to sensitive files
    @sensitive {
        path /.env* /config/* /.git/* /vendor/* /composer.* /package.* /webpack.* /gulpfile.* /Gruntfile.*
    }
    respond @sensitive 403
}

# IPv6 localhost support
[::1]:$HTTP_PORT$(if [[ "$ENABLE_SSL" == true ]]; then echo ", [::1]:$HTTPS_PORT"; fi) {
	bind ::1
$(if [[ "$ENABLE_SSL" == true ]]; then echo "    $ssl_config"; fi)

    # Document root
    root * $DOCUMENT_ROOT/public

    # PHP handling with FrankenPHP
    php_server

    # File server for static assets
    file_server

    # Logging
    log {
        output file $DOCUMENT_ROOT/logs/ipv6-access.log
        format single_field common_log
    }

    # Error handling
    handle_errors {
        @4xx expression {http.error.status_code} >= 400 && {http.error.status_code} < 500
        @5xx expression {http.error.status_code} >= 500 && {http.error.status_code} < 600

        rewrite @4xx /error/4xx.html
        rewrite @5xx /error/5xx.html
        file_server
    }

    # Security headers
    header {
        # Remove server information
        -Server

        # Security headers
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin

$(if [[ "$ENABLE_SSL" == true ]]; then cat <<EOL
        # HTTPS security headers
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
EOL
fi)
    }

    # Deny access to sensitive files
    @sensitive {
        path /.env* /config/* /.git/* /vendor/* /composer.* /package.* /webpack.* /gulpfile.* /Gruntfile.*
    }
    respond @sensitive 403
}

# Redirect www to non-www (optional)
www.$DOMAIN {
$(if [[ "$ENABLE_SSL" == true ]]; then echo "    $ssl_config"; fi)
    redir https://$DOMAIN{uri} permanent
}
EOF
}

# Function to generate static virtual host configuration
generate_static_vhost_config() {
    local vhost_file="$1"
    
    local ssl_config=""
    if [[ "$ENABLE_SSL" == true ]]; then
        ssl_config="tls $SSL_EMAIL"
    fi
    
    execute_command "sudo tee '$vhost_file' > /dev/null" "Creating static vhost configuration" <<EOF
# Virtual Host: $DOMAIN
# Created: $(date)
# Type: Static File Server
# Ports: HTTP=$HTTP_PORT$(if [[ "$ENABLE_SSL" == true ]]; then echo ", HTTPS=$HTTPS_PORT"; fi)

127.0.0.1:$HTTP_PORT$(if [[ "$ENABLE_SSL" == true ]]; then echo ", 127.0.0.1:$HTTPS_PORT"; fi) {
	bind 127.0.0.1
$(if [[ "$ENABLE_SSL" == true ]]; then echo "    $ssl_config"; fi)
    
    # Document root
    root * $DOCUMENT_ROOT/public
    
    # Static file serving
    file_server
    
    # Try files (for SPAs)
    try_files {path} {path}/ /index.html
    
    # Logging
    log {
        output file $DOCUMENT_ROOT/logs/access.log
        format single_field common_log
    }
    
    # Compression
    encode gzip
    
    # Cache static assets
    @static {
        path *.css *.js *.png *.jpg *.jpeg *.gif *.ico *.svg *.woff *.woff2 *.ttf *.eot
    }
    header @static Cache-Control "public, max-age=31536000"
    
    # Security headers
    header {
        -Server
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        
$(if [[ "$ENABLE_SSL" == true ]]; then cat <<EOL
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
EOL
fi)
    }
}

# Redirect www to non-www
www.$DOMAIN {
$(if [[ "$ENABLE_SSL" == true ]]; then echo "    $ssl_config"; fi)
    redir https://$DOMAIN{uri} permanent
}
EOF
}

# Function to generate proxy virtual host configuration
generate_proxy_vhost_config() {
    local vhost_file="$1"
    
    # Prompt for backend server
    local backend_url
    read -p "Enter backend server URL (e.g., http://127.0.0.1:3000): " backend_url
    
    if [[ -z "$backend_url" ]]; then
        print_error "Backend URL is required for proxy configuration"
        exit 1
    fi
    
    local ssl_config=""
    if [[ "$ENABLE_SSL" == true ]]; then
        ssl_config="tls $SSL_EMAIL"
    fi
    
    execute_command "sudo tee '$vhost_file' > /dev/null" "Creating proxy vhost configuration" <<EOF
# Virtual Host: $DOMAIN
# Created: $(date)
# Type: Reverse Proxy
# Ports: HTTP=$HTTP_PORT$(if [[ "$ENABLE_SSL" == true ]]; then echo ", HTTPS=$HTTPS_PORT"; fi)

127.0.0.1:$HTTP_PORT$(if [[ "$ENABLE_SSL" == true ]]; then echo ", 127.0.0.1:$HTTPS_PORT"; fi) {
	bind 127.0.0.1
$(if [[ "$ENABLE_SSL" == true ]]; then echo "    $ssl_config"; fi)
    
    # Reverse proxy to backend
    reverse_proxy $backend_url {
        # Health check
        health_uri /health
        health_interval 30s
        health_timeout 5s
        
        # Headers
        header_up Host {host}
        header_up X-Real-IP {remote}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
    }
    
    # Logging
    log {
        output file $DOCUMENT_ROOT/logs/access.log
        format single_field common_log
    }
    
    # Security headers
    header {
        -Server
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        
$(if [[ "$ENABLE_SSL" == true ]]; then cat <<EOL
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
EOL
fi)
    }
}
EOF
}

# Function to test configuration
test_configuration() {
    print_info "Testing FrankenPHP configuration..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test FrankenPHP configuration"
        return 0
    fi
    
    # Test configuration syntax
    if sudo frankenphp validate --config /etc/frankenphp/Caddyfile; then
        print_success "Configuration syntax is valid"
    else
        print_error "Configuration syntax error detected"
        print_info "Check the configuration file: $VHOSTS_DIR/$DOMAIN.conf"
        exit 1
    fi
}

# Function to reload FrankenPHP service
reload_service() {
    print_info "Reloading FrankenPHP service..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would reload FrankenPHP service"
        return 0
    fi
    
    # Reload the service
    if sudo systemctl reload "$FRANKENPHP_SERVICE"; then
        print_success "FrankenPHP service reloaded successfully"
        
        # Wait a moment for the service to reload
        sleep 2
        
        # Check service status
        if sudo systemctl is-active --quiet "$FRANKENPHP_SERVICE"; then
            print_success "FrankenPHP service is running"
        else
            print_warning "FrankenPHP service may not be running properly"
            print_info "Check logs: sudo journalctl -u $FRANKENPHP_SERVICE -f"
        fi
    else
        print_error "Failed to reload FrankenPHP service"
        print_info "Check service status: sudo systemctl status $FRANKENPHP_SERVICE"
        exit 1
    fi
}

# Function to show post-creation instructions
show_post_creation_instructions() {
    echo
    print_info "=== Virtual Host Created Successfully! ==="
    echo
    cat << EOF
Virtual Host Information:
  Domain:          $DOMAIN
  Document Root:   $DOCUMENT_ROOT/public
  Template Type:   $TEMPLATE_TYPE
  SSL Enabled:     $(if [[ "$ENABLE_SSL" == true ]]; then echo "Yes"; else echo "No"; fi)
  Configuration:   $VHOSTS_DIR/$DOMAIN.conf

Quick Commands:
  Test site:       curl -H "Host: $DOMAIN" http://localhost
$(if [[ "$ENABLE_SSL" == true ]]; then echo "  Test SSL:        curl https://$DOMAIN"; fi)
  View logs:       sudo tail -f $DOCUMENT_ROOT/logs/access.log
  Edit config:     sudo nano $VHOSTS_DIR/$DOMAIN.conf
  Reload service:  sudo systemctl reload $FRANKENPHP_SERVICE

File Locations:
  Web files:       $DOCUMENT_ROOT/public/
  Logs:           $DOCUMENT_ROOT/logs/
  Temp files:     $DOCUMENT_ROOT/tmp/

Next Steps:
1. $(if [[ "$ENABLE_SSL" == false ]]; then echo "Point DNS A record for $DOMAIN to this server"; else echo "SSL certificate will be obtained automatically"; fi)
2. Upload your application files to $DOCUMENT_ROOT/public/
3. Configure any database connections needed
4. Test your site: http$(if [[ "$ENABLE_SSL" == true ]]; then echo "s"; fi)://$DOMAIN

EOF
    
    print_success "Virtual host setup completed! 🚀"
}

# Main function
main() {
    show_script_header "FrankenPHP Virtual Host Creator"
    
    # Validate domain
    validate_domain
    
    # Check prerequisites
    check_prerequisites
    
    # Setup defaults
    setup_defaults
    
    # Check existing virtual host
    check_existing_vhost
    
    # Show configuration summary
    echo
    print_info "=== Virtual Host Configuration ==="
    print_info "Domain: $DOMAIN"
    print_info "Document Root: $DOCUMENT_ROOT"
    print_info "Template Type: $TEMPLATE_TYPE"
    print_info "SSL Enabled: $(if [[ "$ENABLE_SSL" == true ]]; then echo "Yes ($SSL_EMAIL)"; else echo "No"; fi)"
    
    if ! confirm_action "Create virtual host with these settings?" "Y"; then
        print_info "Virtual host creation cancelled"
        exit 0
    fi
    
    # Create web directories
    create_web_directories
    
    # Generate virtual host configuration
    generate_vhost_config
    
    # Test configuration
    test_configuration
    
    # Reload service
    reload_service
    
    # Show post-creation instructions
    show_post_creation_instructions
}

# Run main function
main "$@"
