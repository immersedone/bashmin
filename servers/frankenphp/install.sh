#!/bin/bash
#
# Script: servers/frankenphp/install.sh
# Description: Install FrankenPHP Server with secure configuration
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
readonly FRANKENPHP_SERVICE="frankenphp"
readonly FRANKENPHP_CONFIG_SOURCE="$SCRIPT_DIR/Caddyfile.template"
readonly FRANKENPHP_CONFIG_TARGET="/etc/frankenphp/Caddyfile"
readonly FRANKENPHP_SERVICE_SOURCE="$SCRIPT_DIR/frankenphp.service"
readonly FRANKENPHP_SERVICE_TARGET="/etc/systemd/system/frankenphp.service"
readonly FRANKENPHP_BINARY="/usr/local/bin/frankenphp"
readonly FRANKENPHP_VERSION="latest"

# Configuration
VERBOSE=false
DRY_RUN=false
FORCE_REINSTALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            FRANKENPHP_VERSION="$2"
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

Install FrankenPHP Server with secure configuration.

OPTIONS:
    --version VERSION   FrankenPHP version to install (default: latest)
    --force            Force reinstallation even if already installed
    --verbose          Enable verbose output
    --dry-run          Show what would be done without executing
    -h, --help         Show this help message

EXAMPLES:
    $0                          # Install latest FrankenPHP
    $0 --version v1.9.1         # Install specific version
    $0 --force                  # Force reinstall
    $0 --dry-run --verbose      # See what would be installed

NOTES:
    - Requires sudo privileges
    - Installs PHP extensions and dependencies
    - Creates systemd service for auto-start
    - Configures secure defaults

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
    
    # Check if FrankenPHP is already installed
    if [[ -f "$FRANKENPHP_BINARY" && "$FORCE_REINSTALL" == false ]]; then
        local current_version
        current_version=$($FRANKENPHP_BINARY version 2>/dev/null | head -1 || echo "unknown")
        print_warning "FrankenPHP is already installed: $current_version"
        if ! confirm_action "Reinstall FrankenPHP?"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    print_success "Prerequisites check completed"
}

# Function to install dependencies
install_dependencies() {
    print_info "Installing system dependencies..."
    
    local packages=(
        "curl"
        "unzip"
        "ca-certificates"
        "gnupg"
        "software-properties-common"
    )
    
    execute_command "sudo apt update" "Updating package lists"
    execute_command "sudo apt install -y ${packages[*]}" "Installing base dependencies"
    
    print_info "Installing PHP and extensions..."

    # Note: php-opcache and php-json are included in php-cli/php-fpm packages in PHP 7.0+
    # OPcache is enabled by default in PHP 5.5+ and JSON is a core extension in PHP 8.0+
    local php_packages=(
        "php-cli"
        "php-fpm"
        "php-curl"
        "php-mbstring"
        "php-xml"
        "php-mysql"
        "php-pgsql"
        "php-sqlite3"
        "php-bcmath"
        "php-gd"
        "php-zip"
        "php-intl"
        "php-redis"
        "php-imagick"
    )
    
    execute_command "sudo apt install -y ${php_packages[*]}" "Installing PHP extensions"
    
    print_success "Dependencies installed successfully"
}

# Function to create directories
create_directories() {
    print_info "Creating FrankenPHP directories..."
    
    local directories=(
        "/etc/frankenphp"
        "/etc/frankenphp/vhosts"
        "/var/www/vhosts"
        "/var/www/html"
        "/var/log/frankenphp"
    )
    
    for dir in "${directories[@]}"; do
        execute_command "sudo mkdir -p '$dir'" "Creating directory: $dir"
    done
    
    # Set proper ownership
    execute_command "sudo chown -R www-data:www-data /var/www" "Setting ownership for web directories"
    execute_command "sudo chown -R www-data:www-data /var/log/frankenphp" "Setting ownership for log directory"
    
    print_success "Directories created successfully"
}

# Function to download FrankenPHP binary
download_frankenphp() {
    print_info "Downloading FrankenPHP binary..."

    # Detect system architecture
    local arch
    case "$(uname -m)" in
        x86_64)
            arch="x86_64"
            ;;
        aarch64|arm64)
            arch="aarch64"
            ;;
        *)
            print_error "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac

    local download_url
    if [[ "$FRANKENPHP_VERSION" == "latest" ]]; then
        download_url="https://github.com/php/frankenphp/releases/latest/download/frankenphp-linux-${arch}"
    else
        download_url="https://github.com/php/frankenphp/releases/download/$FRANKENPHP_VERSION/frankenphp-linux-${arch}"
    fi

    print_info "Download URL: $download_url"

    # Download to temporary location first
    local temp_binary="/tmp/frankenphp-$(date +%s)"

    # Use curl with follow redirects and better error handling
    execute_command "curl -fsSL --retry 3 --retry-delay 2 '$download_url' -o '$temp_binary'" "Downloading FrankenPHP binary"
    execute_command "sudo install '$temp_binary' '$FRANKENPHP_BINARY'" "Installing FrankenPHP binary"
    execute_command "rm -f '$temp_binary'" "Cleaning up temporary files"
    
    # Verify installation
    if [[ "$DRY_RUN" == false ]]; then
        local version_output
        version_output=$($FRANKENPHP_BINARY version 2>/dev/null | head -1 || echo "Version check failed")
        print_success "FrankenPHP installed: $version_output"
    fi
}

# Function to install configuration files
install_configuration() {
    print_info "Installing FrankenPHP configuration..."
    
    # Install main Caddyfile
    if [[ -f "$FRANKENPHP_CONFIG_SOURCE" ]]; then
        execute_command "sudo cp '$FRANKENPHP_CONFIG_SOURCE' '$FRANKENPHP_CONFIG_TARGET'" "Installing main Caddyfile"
    else
        print_warning "Caddyfile template not found, creating basic configuration"
        execute_command "sudo tee '$FRANKENPHP_CONFIG_TARGET' > /dev/null" "Creating basic Caddyfile" <<EOF
# FrankenPHP Main Configuration
{
	frankenphp
	order php_server before file_server
	order php before file_server
}

# Import all virtual hosts
import vhosts/*

# Default development site
# FrankenPHP uses port range 8100-8199
:8100 {
	root * /var/www/html
	php_server
	file_server
}
EOF
    fi
    
    # Set proper permissions
    execute_command "sudo chown root:root '$FRANKENPHP_CONFIG_TARGET'" "Setting config file ownership"
    execute_command "sudo chmod 644 '$FRANKENPHP_CONFIG_TARGET'" "Setting config file permissions"
    
    print_success "Configuration installed successfully"
}

# Function to install systemd service
install_systemd_service() {
    print_info "Installing systemd service..."
    
    # Install service file from template
    if [[ -f "$FRANKENPHP_SERVICE_SOURCE" ]]; then
        execute_command "sudo cp '$FRANKENPHP_SERVICE_SOURCE' '$FRANKENPHP_SERVICE_TARGET'" "Installing systemd service file"
    else
        print_error "Service template not found: $FRANKENPHP_SERVICE_SOURCE"
        exit 1
    fi
    
    # Reload systemd
    execute_command "sudo systemctl daemon-reload" "Reloading systemd configuration"
    
    print_success "Systemd service installed successfully"
}

# Function to start and enable service
start_service() {
    print_info "Starting FrankenPHP service..."
    
    # Enable service for auto-start
    execute_command "sudo systemctl enable $FRANKENPHP_SERVICE" "Enabling FrankenPHP service"
    
    # Start the service
    execute_command "sudo systemctl start $FRANKENPHP_SERVICE" "Starting FrankenPHP service"
    
    # Check service status
    if [[ "$DRY_RUN" == false ]]; then
        sleep 2  # Give service time to start
        if sudo systemctl is-active --quiet $FRANKENPHP_SERVICE; then
            print_success "FrankenPHP service is running"
        else
            print_warning "FrankenPHP service may not be running properly"
            print_info "Check logs with: sudo journalctl -u $FRANKENPHP_SERVICE"
        fi
    fi
}

# Function to create default index page
create_default_page() {
    print_info "Creating default index page..."
    
    local index_file="/var/www/html/index.php"
    
    execute_command "sudo tee '$index_file' > /dev/null" "Creating default PHP page" <<'EOF'
<?php
$frankenphp_version = 'Unknown';
if (function_exists('frankenphp_request_context')) {
    $frankenphp_version = 'Available';
}

$php_version = PHP_VERSION;
$server_software = $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FrankenPHP - It Works!</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; text-align: center; margin-bottom: 30px; }
        .info { background: #ecf0f1; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .success { background: #d5edda; border: 1px solid #c3e6cb; color: #155724; }
        .code { background: #f8f9fa; border: 1px solid #e9ecef; padding: 15px; border-radius: 4px; font-family: monospace; }
        .footer { text-align: center; margin-top: 40px; color: #7f8c8d; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 FrankenPHP is Working!</h1>
        
        <div class="info success">
            <h3>✅ Installation Successful</h3>
            <p>Your FrankenPHP server is up and running successfully!</p>
        </div>
        
        <div class="info">
            <h3>📊 Server Information</h3>
            <ul>
                <li><strong>Server Software:</strong> <?= htmlspecialchars($server_software) ?></li>
                <li><strong>PHP Version:</strong> <?= htmlspecialchars($php_version) ?></li>
                <li><strong>FrankenPHP:</strong> <?= htmlspecialchars($frankenphp_version) ?></li>
                <li><strong>Document Root:</strong> <?= htmlspecialchars($_SERVER['DOCUMENT_ROOT'] ?? '/var/www/html') ?></li>
            </ul>
        </div>
        
        <div class="info">
            <h3>🔧 Next Steps</h3>
            <ul>
                <li>Add virtual hosts with: <code>./add-vhost.sh domain.com</code></li>
                <li>Place your PHP files in: <code>/var/www/vhosts/domain.com/</code></li>
                <li>View service status: <code>sudo systemctl status frankenphp</code></li>
                <li>View logs: <code>sudo journalctl -u frankenphp -f</code></li>
            </ul>
        </div>
        
        <div class="code">
            <strong>Test PHP:</strong><br>
            &lt;?php phpinfo(); ?&gt;
        </div>
        
        <div class="footer">
            <p>FrankenPHP - The Modern PHP Application Server</p>
            <p><a href="https://frankenphp.dev/" target="_blank">Documentation</a> | <a href="https://github.com/dunglas/frankenphp" target="_blank">GitHub</a></p>
        </div>
    </div>
</body>
</html>
EOF
    
    execute_command "sudo chown www-data:www-data '$index_file'" "Setting index file ownership"
    
    print_success "Default index page created"
}

# Function to show post-installation instructions
show_post_install_instructions() {
    echo
    print_info "=== Post-Installation Instructions ==="
    echo
    cat << EOF
FrankenPHP has been installed successfully! 🚀

Service Management:
  sudo systemctl status frankenphp     # Check service status
  sudo systemctl restart frankenphp    # Restart service
  sudo systemctl stop frankenphp       # Stop service
  sudo systemctl start frankenphp      # Start service

Configuration:
  Main config:     $FRANKENPHP_CONFIG_TARGET
  Virtual hosts:   /etc/frankenphp/vhosts/
  Web root:        /var/www/html
  Logs:           /var/log/frankenphp/

Add Virtual Hosts:
  ./add-vhost.sh domain.com            # Add new virtual host

View Logs:
  sudo journalctl -u frankenphp -f     # Follow service logs
  sudo tail -f /var/log/frankenphp/access.log

Test Installation:
  curl http://localhost:8100          # Test default site
  curl -H "Host: domain.com" http://localhost:8100  # Test vhost

Next Steps:
1. Configure your virtual hosts in /etc/frankenphp/vhosts/
2. Place your PHP applications in /var/www/vhosts/
3. Customize the main Caddyfile as needed
4. Set up SSL certificates for production use

EOF
    
    print_success "FrankenPHP installation completed! 🎉"
}

# Main installation function
main() {
    show_script_header "FrankenPHP Installation Script"
    
    # Check prerequisites
    check_prerequisites
    
    # Confirm installation
    print_info "This will install FrankenPHP $FRANKENPHP_VERSION with the following components:"
    print_info "  - FrankenPHP binary ($FRANKENPHP_BINARY)"
    print_info "  - PHP extensions and dependencies"
    print_info "  - Systemd service configuration"
    print_info "  - Default Caddyfile configuration"
    print_info "  - Web directories and permissions"
    
    if ! confirm_action "Proceed with FrankenPHP installation?" "Y"; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Installation steps
    install_dependencies
    create_directories
    download_frankenphp
    install_configuration
    install_systemd_service
    create_default_page
    start_service
    
    # Show post-installation instructions
    show_post_install_instructions
}

# Run main function
main "$@"