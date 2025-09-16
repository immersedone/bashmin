#!/bin/bash

# BashMin phpMyAdmin Installer
# Downloads latest phpMyAdmin, extracts, backs up existing installation, and configures
# Author: BashMin Team
# Version: 1.0

set -euo pipefail

# Load helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/system.sh"

# Import colors from common.sh
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
PHPMYADMIN_DIR="/usr/share/phpmyadmin"
BACKUP_DIR="/var/backups/phpmyadmin"
CONFIG_DIR="/etc/phpmyadmin"
TEMP_DIR="/tmp/phpmyadmin-install"
DOWNLOAD_URL="https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz"
APACHE_CONFIG="/etc/apache2/conf-available/phpmyadmin.conf"

# Function to print header
print_header() {
    echo
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}            $1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_info "Running as root"
    elif sudo -n true 2>/dev/null; then
        print_info "Sudo access confirmed"
    else
        print_error "This script requires sudo access"
        exit 1
    fi
    
    # Check required commands
    local required_commands=("wget" "tar" "openssl" "php")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            print_success "✓ $cmd is available"
        else
            print_error "✗ $cmd is required but not installed"
            exit 1
        fi
    done
    
    # Check if Apache is installed
    if systemctl list-unit-files apache2.service &> /dev/null; then
        print_success "✓ Apache2 is installed"
    else
        print_warning "Apache2 not detected - manual web server configuration may be needed"
    fi
    
    # Check if MySQL/MariaDB is running
    if systemctl is-active --quiet mysql || systemctl is-active --quiet mariadb; then
        print_success "✓ Database server is running"
    else
        print_warning "Database server not detected or not running"
    fi
}

# Function to get latest phpMyAdmin version
get_latest_version() {
    print_info "Checking for latest phpMyAdmin version..."
    
    # Try to get version from GitHub API
    local version
    if command -v curl &> /dev/null; then
        version=$(curl -s https://api.github.com/repos/phpmyadmin/phpmyadmin/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "")
    elif command -v wget &> /dev/null; then
        version=$(wget -qO- https://api.github.com/repos/phpmyadmin/phpmyadmin/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "")
    fi
    
    if [[ -n "$version" ]]; then
        DOWNLOAD_URL="https://files.phpmyadmin.net/phpMyAdmin/${version}/phpMyAdmin-${version}-all-languages.tar.gz"
        print_success "Latest version found: $version"
    else
        print_warning "Could not determine latest version, using default download URL"
    fi
}

# Function to backup existing installation
backup_existing() {
    if [[ -d "$PHPMYADMIN_DIR" ]]; then
        print_info "Backing up existing phpMyAdmin installation..."
        
        # Create backup directory
        sudo mkdir -p "$BACKUP_DIR"
        
        # Create timestamped backup
        local backup_name="phpmyadmin-backup-$(date +%Y%m%d-%H%M%S)"
        local backup_path="$BACKUP_DIR/$backup_name"
        
        if sudo cp -r "$PHPMYADMIN_DIR" "$backup_path"; then
            print_success "Backup created: $backup_path"
            
            # Also backup config if it exists
            if [[ -d "$CONFIG_DIR" ]]; then
                sudo cp -r "$CONFIG_DIR" "$backup_path-config"
                print_success "Config backup created: $backup_path-config"
            fi
        else
            print_error "Failed to create backup"
            return 1
        fi
    else
        print_info "No existing phpMyAdmin installation found"
    fi
}

# Function to download and extract phpMyAdmin
download_and_extract() {
    print_info "Downloading and extracting phpMyAdmin..."
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Download phpMyAdmin
    print_info "Downloading from: $DOWNLOAD_URL"
    if wget -O phpmyadmin.tar.gz "$DOWNLOAD_URL"; then
        print_success "Download completed"
    else
        print_error "Failed to download phpMyAdmin"
        return 1
    fi
    
    # Extract archive
    print_info "Extracting archive..."
    if tar -xzf phpmyadmin.tar.gz; then
        print_success "Extraction completed"
    else
        print_error "Failed to extract archive"
        return 1
    fi
    
    # Find extracted directory (it will have version in name)
    local extracted_dir=$(find . -maxdepth 1 -type d -name "phpMyAdmin-*" | head -1)
    if [[ -z "$extracted_dir" ]]; then
        print_error "Could not find extracted phpMyAdmin directory"
        return 1
    fi
    
    # Remove old installation and move new one
    sudo rm -rf "$PHPMYADMIN_DIR"
    sudo mv "$extracted_dir" "$PHPMYADMIN_DIR"
    print_success "phpMyAdmin installed to $PHPMYADMIN_DIR"
    
    # Set proper permissions
    sudo chown -R www-data:www-data "$PHPMYADMIN_DIR"
    sudo chmod -R 755 "$PHPMYADMIN_DIR"
    print_success "Permissions set"
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
}

# Function to generate blowfish secret
generate_blowfish_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to create configuration
create_configuration() {
    print_info "Creating phpMyAdmin configuration..."
    
    # Create config directory
    sudo mkdir -p "$CONFIG_DIR"
    
    # Generate blowfish secret
    local blowfish_secret=$(generate_blowfish_secret)
    print_success "Generated new blowfish secret"
    
    # Check if config.sample.inc.php exists in the phpMyAdmin directory
    local sample_config="$PHPMYADMIN_DIR/config.sample.inc.php"
    if [[ ! -f "$sample_config" ]]; then
        # Try alternative naming patterns
        if [[ -f "$PHPMYADMIN_DIR/config.inc.php.sample" ]]; then
            sample_config="$PHPMYADMIN_DIR/config.inc.php.sample"
        elif [[ -f "$PHPMYADMIN_DIR/examples/config.inc.php" ]]; then
            sample_config="$PHPMYADMIN_DIR/examples/config.inc.php"
        else
            print_error "Sample configuration file not found in phpMyAdmin directory"
            print_error "Looked for: config.sample.inc.php, config.inc.php.sample, examples/config.inc.php"
            return 1
        fi
    fi
    
    print_info "Using official sample configuration as template: $(basename "$sample_config")"
    
    # Copy the sample config and modify the blowfish secret
    sudo cp "$sample_config" "$CONFIG_DIR/config.inc.php"
    
    # Replace the blowfish secret placeholder with our generated one
    # The sample config typically has: $cfg['blowfish_secret'] = ''; /* YOU MUST FILL IN THIS FOR COOKIE AUTH! */
    sudo sed -i "s/\$cfg\['blowfish_secret'\] = ''/\$cfg['blowfish_secret'] = '$blowfish_secret'/" "$CONFIG_DIR/config.inc.php"
    
    # Also handle variations of the blowfish secret line
    sudo sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg['blowfish_secret'] = '$blowfish_secret';/" "$CONFIG_DIR/config.inc.php"
    sudo sed -i "s/\$cfg\['blowfish_secret'\] = '.*';/\$cfg['blowfish_secret'] = '$blowfish_secret';/" "$CONFIG_DIR/config.inc.php"
    
    print_success "Updated blowfish secret in configuration"
    
    # Set proper permissions on config
    sudo chown www-data:www-data "$CONFIG_DIR/config.inc.php"
    sudo chmod 644 "$CONFIG_DIR/config.inc.php"
    print_success "Configuration created: $CONFIG_DIR/config.inc.php"
    
    # Create symlink in phpMyAdmin directory
    sudo ln -sf "$CONFIG_DIR/config.inc.php" "$PHPMYADMIN_DIR/config.inc.php"
    print_success "Configuration symlink created"
    
    # Create temp directories if they don't exist
    sudo mkdir -p /var/lib/phpmyadmin/{upload,save,tmp}
    sudo chown -R www-data:www-data /var/lib/phpmyadmin
    sudo chmod -R 755 /var/lib/phpmyadmin
    print_success "Temporary directories created"
}

# Function to configure Apache
configure_apache() {
    print_info "Configuring Apache for phpMyAdmin..."
    
    # Check if Apache config already exists
    if [[ -f "$APACHE_CONFIG" ]]; then
        print_warning "Apache configuration already exists: $APACHE_CONFIG"
        print_info "Backing up existing configuration..."
        
        # Create backup of existing config
        local backup_config="${APACHE_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
        if sudo cp "$APACHE_CONFIG" "$backup_config"; then
            print_success "Backup created: $backup_config"
        else
            print_warning "Failed to backup existing configuration"
        fi
    fi
    
    # Create Apache configuration
    sudo tee "$APACHE_CONFIG" > /dev/null << 'EOF'
# phpMyAdmin Apache configuration
Alias /phpmyadmin /usr/share/phpmyadmin

<Directory /usr/share/phpmyadmin>
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    Require all granted

    <IfModule mod_php.c>
        php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
        php_admin_value open_basedir /usr/share/phpmyadmin/:/var/lib/phpmyadmin/:/etc/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/:/usr/share/php/PhpMyAdmin/:/usr/share/php/Symfony/:/usr/share/php/Twig/:/usr/share/php/Twig-Extensions/:/usr/share/php/ReCaptcha/:/usr/share/php/Psr/Container/:/usr/share/php/Psr/Cache/:/usr/share/php/Psr/Log/:/usr/share/php/Psr/SimpleCache/
        php_admin_value mbstring.func_overload 0
    </IfModule>
    <IfModule mod_php.c>
        php_admin_value mbstring.func_overload 0
    </IfModule>

</Directory>

# Disallow web access to directories that don't need it
<Directory /usr/share/phpmyadmin/templates>
    Require all denied
</Directory>
<Directory /usr/share/phpmyadmin/libraries>
    Require all denied
</Directory>
<Directory /usr/share/phpmyadmin/setup/lib>
    Require all denied
</Directory>
EOF
    
    print_success "Apache configuration created: $APACHE_CONFIG"
    
    # Check if the configuration is already enabled
    if sudo a2enconf phpmyadmin 2>/dev/null | grep -q "already enabled"; then
        print_info "phpMyAdmin configuration already enabled"
    elif sudo a2enconf phpmyadmin; then
        print_success "phpMyAdmin configuration enabled"
    else
        print_warning "Failed to enable phpMyAdmin configuration"
    fi
    
    # Reload Apache
    if sudo systemctl reload apache2; then
        print_success "Apache reloaded"
    else
        print_warning "Failed to reload Apache"
    fi
}

# Function to verify installation
verify_installation() {
    print_info "Verifying installation..."
    
    local all_good=true
    
    # Check if phpMyAdmin directory exists
    if [[ -d "$PHPMYADMIN_DIR" ]]; then
        print_success "✓ phpMyAdmin directory exists"
    else
        print_error "✗ phpMyAdmin directory missing"
        all_good=false
    fi
    
    # Check if config file exists
    if [[ -f "$CONFIG_DIR/config.inc.php" ]]; then
        print_success "✓ Configuration file exists"
    else
        print_error "✗ Configuration file missing"
        all_good=false
    fi
    
    # Check if Apache config exists
    if [[ -f "$APACHE_CONFIG" ]]; then
        print_success "✓ Apache configuration exists"
    else
        print_error "✗ Apache configuration missing"
        all_good=false
    fi
    
    # Check if index.php exists
    if [[ -f "$PHPMYADMIN_DIR/index.php" ]]; then
        print_success "✓ phpMyAdmin index.php exists"
    else
        print_error "✗ phpMyAdmin index.php missing"
        all_good=false
    fi
    
    if $all_good; then
        print_success "Installation verification passed!"
        return 0
    else
        print_error "Installation verification failed!"
        return 1
    fi
}

# Function to show installation summary
show_summary() {
    echo
    print_info "Installation Summary:"
    echo
    echo "├── phpMyAdmin installed to: $PHPMYADMIN_DIR"
    echo "├── Configuration file: $CONFIG_DIR/config.inc.php"
    echo "├── Apache config: $APACHE_CONFIG"
    echo "├── Temporary directories: /var/lib/phpmyadmin/"
    if [[ -d "$BACKUP_DIR" ]]; then
        echo "├── Backups stored in: $BACKUP_DIR"
    fi
    echo "└── Web access: http://your-server/phpmyadmin"
    echo
    print_info "Next steps:"
    echo "1. Ensure your database server is running"
    echo "2. Access phpMyAdmin at http://your-server/phpmyadmin"
    echo "3. Login with your MySQL/MariaDB credentials"
    echo "4. Consider enabling SSL for production use"
    echo
}

# Main installation function
main() {
    print_header "BashMin phpMyAdmin Installer"
    
    # Check prerequisites
    check_prerequisites
    
    # Get latest version
    get_latest_version
    
    # Backup existing installation
    backup_existing
    
    # Download and extract
    download_and_extract
    
    # Create configuration
    create_configuration
    
    # Configure Apache
    configure_apache
    
    # Verify installation
    if verify_installation; then
        print_success "phpMyAdmin installation completed successfully!"
        show_summary
        return 0
    else
        print_error "phpMyAdmin installation failed!"
        return 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
