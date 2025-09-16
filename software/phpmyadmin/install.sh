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
DOWNLOAD_URL="https://files.phpmyadmin.net/phpMyAdmin/5.2.2/phpMyAdmin-5.2.2-all-languages.tar.gz"

# Web server configuration
WEB_SERVER=""  # apache2, frankenphp, or both
URL_TYPE=""    # subdirectory or subdomain
URL_PATH="pma-1337"  # default subdirectory path
SUBDOMAIN=""   # for subdomain configuration
DOMAIN=""      # base domain for subdomain setup

# Web server config paths
APACHE_CONFIG="/etc/apache2/conf-available/phpmyadmin.conf"
FRANKENPHP_CONFIG="/etc/frankenphp/sites-available/phpmyadmin.json"

# Function to print header
print_header() {
    echo
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}            $1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

# Function to detect available web servers
detect_web_servers() {
    local apache_available=false
    local frankenphp_available=false

    # Check for Apache2
    if systemctl list-unit-files apache2.service &> /dev/null || command -v apache2 &> /dev/null; then
        apache_available=true
        print_success "✓ Apache2 detected"
    fi

    # Check for FrankenPHP
    if systemctl list-unit-files frankenphp.service &> /dev/null || command -v frankenphp &> /dev/null; then
        frankenphp_available=true
        print_success "✓ FrankenPHP detected"
    fi

    if [[ "$apache_available" == false && "$frankenphp_available" == false ]]; then
        print_warning "No supported web server detected (Apache2 or FrankenPHP)"
        print_info "You can install a web server first or configure phpMyAdmin manually later"
        WEB_SERVER="none"
        return 0
    fi

    # Prompt user for web server selection
    echo
    print_info "Web Server Configuration:"

    if [[ "$apache_available" == true && "$frankenphp_available" == true ]]; then
        echo "Multiple web servers detected. Please choose:"
        echo "1) Apache2 only"
        echo "2) FrankenPHP only"
        echo "3) Both Apache2 and FrankenPHP"
        echo "4) Skip web server configuration"

        while true; do
            read -p "Enter your choice (1-4): " choice
            case $choice in
                1) WEB_SERVER="apache2"; break ;;
                2) WEB_SERVER="frankenphp"; break ;;
                3) WEB_SERVER="both"; break ;;
                4) WEB_SERVER="none"; break ;;
                *) echo "Invalid choice. Please enter 1-4." ;;
            esac
        done
    elif [[ "$apache_available" == true ]]; then
        read -p "Configure phpMyAdmin for Apache2? (Y/n): " -r
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            WEB_SERVER="none"
        else
            WEB_SERVER="apache2"
        fi
    elif [[ "$frankenphp_available" == true ]]; then
        read -p "Configure phpMyAdmin for FrankenPHP? (Y/n): " -r
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            WEB_SERVER="none"
        else
            WEB_SERVER="frankenphp"
        fi
    fi
}

# Function to configure URL options
configure_url_options() {
    if [[ "$WEB_SERVER" == "none" ]]; then
        return 0
    fi

    echo
    print_info "URL Configuration:"
    echo "How would you like to access phpMyAdmin?"
    echo "1) Subdirectory (e.g., https://yoursite.com/pma-1337)"
    echo "2) Subdomain (e.g., https://pma.yoursite.com)"

    while true; do
        read -p "Enter your choice (1-2): " choice
        case $choice in
            1) URL_TYPE="subdirectory"; break ;;
            2) URL_TYPE="subdomain"; break ;;
            *) echo "Invalid choice. Please enter 1 or 2." ;;
        esac
    done

    if [[ "$URL_TYPE" == "subdirectory" ]]; then
        read -p "Enter the subdirectory path (default: pma-1337): " input_path
        if [[ -n "$input_path" ]]; then
            # Remove leading/trailing slashes
            URL_PATH="${input_path#/}"
            URL_PATH="${URL_PATH%/}"
        fi
        print_success "phpMyAdmin will be accessible at: /${URL_PATH}"

    elif [[ "$URL_TYPE" == "subdomain" ]]; then
        read -p "Enter your base domain (e.g., yoursite.com): " DOMAIN
        while [[ -z "$DOMAIN" ]]; do
            print_error "Domain is required for subdomain configuration"
            read -p "Enter your base domain: " DOMAIN
        done

        read -p "Enter subdomain prefix (default: pma): " input_subdomain
        SUBDOMAIN="${input_subdomain:-pma}"

        print_success "phpMyAdmin will be accessible at: https://${SUBDOMAIN}.${DOMAIN}"
    fi
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
        print_info "This script requires sudo privileges. Please enter your password when prompted."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges"
            exit 1
        fi
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

    # Detect and configure web servers
    detect_web_servers
    configure_url_options

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

    # Try to get version from GitHub API with timeout
    local version
    if command -v curl &> /dev/null; then
        version=$(timeout 10 curl -s --max-time 10 https://api.github.com/repos/phpmyadmin/phpmyadmin/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "")
    elif command -v wget &> /dev/null; then
        version=$(timeout 10 wget --timeout=10 -qO- https://api.github.com/repos/phpmyadmin/phpmyadmin/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "")
    fi

    if [[ -n "$version" ]]; then
        # Strip "RELEASE_" prefix if present to get clean version number
        local clean_version="${version#RELEASE_}"

        # Define primary and fallback download URLs
        local primary_url="https://files.phpmyadmin.net/phpMyAdmin/${clean_version}/phpMyAdmin-${clean_version}-all-languages.tar.gz"
        local fallback_url="https://github.com/phpmyadmin/phpmyadmin/archive/refs/tags/${version}.tar.gz"

        # Test if primary URL is accessible
        if curl -s --head --max-time 5 "$primary_url" | head -n 1 | grep -q "200 OK"; then
            DOWNLOAD_URL="$primary_url"
            print_success "Latest version found: $version (using $clean_version for download)"
        else
            print_warning "Primary download URL not accessible, using GitHub fallback"
            DOWNLOAD_URL="$fallback_url"
        fi
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
    
    # Find extracted directory (it will have version in name or be named differently for GitHub archives)
    local extracted_dir
    # Try phpMyAdmin-version pattern first (official releases)
    extracted_dir=$(find . -maxdepth 1 -type d -name "phpMyAdmin-*" | head -1)

    # If not found, try phpmyadmin-RELEASE_version pattern (GitHub archives)
    if [[ -z "$extracted_dir" ]]; then
        extracted_dir=$(find . -maxdepth 1 -type d -name "phpmyadmin-RELEASE_*" | head -1)
    fi

    # If still not found, try any directory starting with phpmyadmin
    if [[ -z "$extracted_dir" ]]; then
        extracted_dir=$(find . -maxdepth 1 -type d -name "phpmyadmin*" | head -1)
    fi

    if [[ -z "$extracted_dir" ]]; then
        print_error "Could not find extracted phpMyAdmin directory"
        return 1
    fi

    print_info "Found phpMyAdmin directory: $extracted_dir"

    # Validate the extracted directory has required files
    if [[ ! -f "$extracted_dir/index.php" ]]; then
        print_error "Downloaded archive doesn't appear to contain a valid phpMyAdmin installation"
        print_error "Missing index.php in extracted directory"
        return 1
    fi

    # For GitHub archives, we may need to build/prepare the files
    if [[ -f "$extracted_dir/composer.json" && ! -f "$extracted_dir/vendor/autoload.php" ]]; then
        print_warning "Downloaded source requires build process - this may not work without composer install"
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

    # Create Apache configuration based on URL type
    if [[ "$URL_TYPE" == "subdomain" ]]; then
        # Create virtual host for subdomain
        local vhost_config="/etc/apache2/sites-available/${SUBDOMAIN}.${DOMAIN}.conf"

        sudo tee "$vhost_config" > /dev/null << EOF
# phpMyAdmin Virtual Host for ${SUBDOMAIN}.${DOMAIN}
<VirtualHost *:80>
    ServerName ${SUBDOMAIN}.${DOMAIN}
    DocumentRoot ${PHPMYADMIN_DIR}

    <Directory ${PHPMYADMIN_DIR}>
        Options SymLinksIfOwnerMatch
        DirectoryIndex index.php
        AllowOverride None
        Require all granted

        <IfModule mod_php.c>
            php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
            php_admin_value open_basedir ${PHPMYADMIN_DIR}/:/var/lib/phpmyadmin/:/etc/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/:/usr/share/php/PhpMyAdmin/:/usr/share/php/Symfony/:/usr/share/php/Twig/:/usr/share/php/Twig-Extensions/:/usr/share/php/ReCaptcha/:/usr/share/php/Psr/Container/:/usr/share/php/Psr/Cache/:/usr/share/php/Psr/Log/:/usr/share/php/Psr/SimpleCache/
            php_admin_value mbstring.func_overload 0
        </IfModule>
    </Directory>

    # Disallow web access to directories that don't need it
    <Directory ${PHPMYADMIN_DIR}/templates>
        Require all denied
    </Directory>
    <Directory ${PHPMYADMIN_DIR}/libraries>
        Require all denied
    </Directory>
    <Directory ${PHPMYADMIN_DIR}/setup/lib>
        Require all denied
    </Directory>

    # Security headers
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # Logs
    ErrorLog \${APACHE_LOG_DIR}/${SUBDOMAIN}.${DOMAIN}-error.log
    CustomLog \${APACHE_LOG_DIR}/${SUBDOMAIN}.${DOMAIN}-access.log combined
</VirtualHost>

# HTTPS Virtual Host (placeholder - requires SSL certificate)
<VirtualHost *:443>
    ServerName ${SUBDOMAIN}.${DOMAIN}
    DocumentRoot ${PHPMYADMIN_DIR}

    # SSL Configuration (uncomment when you have certificates)
    # SSLEngine on
    # SSLCertificateFile /path/to/your/certificate.crt
    # SSLCertificateKeyFile /path/to/your/private.key

    # Include same directory and security settings as HTTP version
    <Directory ${PHPMYADMIN_DIR}>
        Options SymLinksIfOwnerMatch
        DirectoryIndex index.php
        AllowOverride None
        Require all granted

        <IfModule mod_php.c>
            php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
            php_admin_value open_basedir ${PHPMYADMIN_DIR}/:/var/lib/phpmyadmin/:/etc/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/:/usr/share/php/PhpMyAdmin/:/usr/share/php/Symfony/:/usr/share/php/Twig/:/usr/share/php/Twig-Extensions/:/usr/share/php/ReCaptcha/:/usr/share/php/Psr/Container/:/usr/share/php/Psr/Cache/:/usr/share/php/Psr/Log/:/usr/share/php/Psr/SimpleCache/
            php_admin_value mbstring.func_overload 0
        </IfModule>
    </Directory>

    # Security directories
    <Directory ${PHPMYADMIN_DIR}/templates>
        Require all denied
    </Directory>
    <Directory ${PHPMYADMIN_DIR}/libraries>
        Require all denied
    </Directory>
    <Directory ${PHPMYADMIN_DIR}/setup/lib>
        Require all denied
    </Directory>

    # Security headers
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # Logs
    ErrorLog \${APACHE_LOG_DIR}/${SUBDOMAIN}.${DOMAIN}-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/${SUBDOMAIN}.${DOMAIN}-ssl-access.log combined
</VirtualHost>
EOF

        print_success "Apache virtual host created: $vhost_config"

        # Enable the site
        if sudo a2ensite "${SUBDOMAIN}.${DOMAIN}"; then
            print_success "Virtual host enabled"
        else
            print_warning "Failed to enable virtual host"
        fi

        # Enable required modules
        sudo a2enmod headers 2>/dev/null || print_warning "Headers module already enabled or not available"
        sudo a2enmod ssl 2>/dev/null || print_warning "SSL module already enabled or not available"

    else
        # Create alias configuration for subdirectory access
        sudo tee "$APACHE_CONFIG" > /dev/null << EOF
# phpMyAdmin Apache configuration - Subdirectory Access
Alias /${URL_PATH} ${PHPMYADMIN_DIR}

<Directory ${PHPMYADMIN_DIR}>
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    AllowOverride None
    Require all granted

    <IfModule mod_php.c>
        php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
        php_admin_value open_basedir ${PHPMYADMIN_DIR}/:/var/lib/phpmyadmin/:/etc/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/:/usr/share/php/PhpMyAdmin/:/usr/share/php/Symfony/:/usr/share/php/Twig/:/usr/share/php/Twig-Extensions/:/usr/share/php/ReCaptcha/:/usr/share/php/Psr/Container/:/usr/share/php/Psr/Cache/:/usr/share/php/Psr/Log/:/usr/share/php/Psr/SimpleCache/
        php_admin_value mbstring.func_overload 0
    </IfModule>
</Directory>

# Disallow web access to directories that don't need it
<Directory ${PHPMYADMIN_DIR}/templates>
    Require all denied
</Directory>
<Directory ${PHPMYADMIN_DIR}/libraries>
    Require all denied
</Directory>
<Directory ${PHPMYADMIN_DIR}/setup/lib>
    Require all denied
</Directory>

# Security headers for this alias
<Location /${URL_PATH}>
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
</Location>
EOF

        print_success "Apache configuration created: $APACHE_CONFIG"

        # Enable the configuration
        if sudo a2enconf phpmyadmin 2>/dev/null | grep -q "already enabled"; then
            print_info "phpMyAdmin configuration already enabled"
        elif sudo a2enconf phpmyadmin; then
            print_success "phpMyAdmin configuration enabled"
        else
            print_warning "Failed to enable phpMyAdmin configuration"
        fi

        # Enable required modules
        sudo a2enmod headers 2>/dev/null || print_warning "Headers module already enabled or not available"
    fi

    # Test Apache configuration
    if sudo apache2ctl configtest; then
        print_success "Apache configuration test passed"

        # Reload Apache
        if sudo systemctl reload apache2; then
            print_success "Apache reloaded"
        else
            print_warning "Failed to reload Apache"
        fi
    else
        print_error "Apache configuration test failed - please check the configuration"
    fi
}

# Function to configure FrankenPHP
configure_frankenphp() {
    print_info "Configuring FrankenPHP for phpMyAdmin..."

    # Create FrankenPHP sites directory if it doesn't exist
    sudo mkdir -p "$(dirname "$FRANKENPHP_CONFIG")"

    # Check if FrankenPHP config already exists
    if [[ -f "$FRANKENPHP_CONFIG" ]]; then
        print_warning "FrankenPHP configuration already exists: $FRANKENPHP_CONFIG"
        print_info "Backing up existing configuration..."

        # Create backup of existing config
        local backup_config="${FRANKENPHP_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
        if sudo cp "$FRANKENPHP_CONFIG" "$backup_config"; then
            print_success "Backup created: $backup_config"
        else
            print_warning "Failed to backup existing configuration"
        fi
    fi

    # Create FrankenPHP configuration
    if [[ "$URL_TYPE" == "subdomain" ]]; then
        # Subdomain configuration
        sudo tee "$FRANKENPHP_CONFIG" > /dev/null << EOF
{
  "apps": {
    "http": {
      "servers": {
        "phpmyadmin": {
          "listen": [":80", ":443"],
          "routes": [
            {
              "match": [
                {
                  "host": ["${SUBDOMAIN}.${DOMAIN}"]
                }
              ],
              "handle": [
                {
                  "handler": "subroute",
                  "routes": [
                    {
                      "handle": [
                        {
                          "handler": "php_server",
                          "root": "${PHPMYADMIN_DIR}",
                          "index": ["index.php"],
                          "php_fastcgi": "unix//run/php/php8.3-fpm.sock"
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ],
          "automatic_https": {
            "disable": false
          },
          "logs": {
            "logger_names": {
              "phpmyadmin": {
                "output": "file",
                "filename": "/var/log/frankenphp/${SUBDOMAIN}.${DOMAIN}.log"
              }
            }
          }
        }
      }
    }
  },
  "logging": {
    "logs": {
      "phpmyadmin": {
        "level": "INFO"
      }
    }
  }
}
EOF
    else
        # Subdirectory configuration - this is more complex with FrankenPHP
        sudo tee "$FRANKENPHP_CONFIG" > /dev/null << EOF
{
  "apps": {
    "http": {
      "servers": {
        "default": {
          "routes": [
            {
              "match": [
                {
                  "path": ["/${URL_PATH}", "/${URL_PATH}/*"]
                }
              ],
              "handle": [
                {
                  "handler": "rewrite",
                  "uri": "{path}",
                  "strip_path_prefix": "/${URL_PATH}"
                },
                {
                  "handler": "php_server",
                  "root": "${PHPMYADMIN_DIR}",
                  "index": ["index.php"],
                  "php_fastcgi": "unix//run/php/php8.3-fpm.sock"
                }
              ]
            }
          ]
        }
      }
    }
  },
  "logging": {
    "logs": {
      "default": {
        "level": "INFO"
      }
    }
  }
}
EOF
    fi

    print_success "FrankenPHP configuration created: $FRANKENPHP_CONFIG"

    # Create log directory
    sudo mkdir -p /var/log/frankenphp
    sudo chown -R www-data:www-data /var/log/frankenphp

    # Test and reload FrankenPHP configuration
    if command -v frankenphp &> /dev/null; then
        if frankenphp validate --config "$FRANKENPHP_CONFIG"; then
            print_success "FrankenPHP configuration test passed"

            # Reload FrankenPHP
            if sudo systemctl reload frankenphp 2>/dev/null; then
                print_success "FrankenPHP reloaded"
            else
                print_warning "Failed to reload FrankenPHP (service may not be running)"
            fi
        else
            print_error "FrankenPHP configuration test failed - please check the configuration"
        fi
    else
        print_warning "FrankenPHP binary not found - configuration created but not tested"
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

    # Show web server configurations
    if [[ "$WEB_SERVER" == "apache2" || "$WEB_SERVER" == "both" ]]; then
        if [[ "$URL_TYPE" == "subdomain" ]]; then
            echo "├── Apache virtual host: /etc/apache2/sites-available/${SUBDOMAIN}.${DOMAIN}.conf"
        else
            echo "├── Apache config: $APACHE_CONFIG"
        fi
    fi

    if [[ "$WEB_SERVER" == "frankenphp" || "$WEB_SERVER" == "both" ]]; then
        echo "├── FrankenPHP config: $FRANKENPHP_CONFIG"
    fi

    echo "├── Temporary directories: /var/lib/phpmyadmin/"
    if [[ -d "$BACKUP_DIR" ]]; then
        echo "├── Backups stored in: $BACKUP_DIR"
    fi

    # Show access URLs based on configuration
    if [[ "$WEB_SERVER" == "none" ]]; then
        echo "└── Web access: Manual configuration required"
    else
        if [[ "$URL_TYPE" == "subdomain" ]]; then
            echo "└── Web access: http://${SUBDOMAIN}.${DOMAIN} (and https:// when SSL is configured)"
        else
            echo "└── Web access: http://your-server/${URL_PATH}"
        fi
    fi

    echo
    print_info "Next steps:"
    echo "1. Ensure your database server is running"

    if [[ "$WEB_SERVER" != "none" ]]; then
        if [[ "$URL_TYPE" == "subdomain" ]]; then
            echo "2. Configure DNS to point ${SUBDOMAIN}.${DOMAIN} to your server"
            echo "3. Access phpMyAdmin at http://${SUBDOMAIN}.${DOMAIN}"
            echo "4. Set up SSL certificate for https://${SUBDOMAIN}.${DOMAIN}"
        else
            echo "2. Access phpMyAdmin at http://your-server/${URL_PATH}"
            echo "3. Consider setting up SSL for production use"
        fi
        if [[ "$URL_TYPE" == "subdomain" ]]; then
            echo "5. Login with your MySQL/MariaDB credentials"
        else
            echo "4. Login with your MySQL/MariaDB credentials"
        fi
    else
        echo "2. Configure your web server manually to serve phpMyAdmin"
        echo "3. Access phpMyAdmin through your configured URL"
        echo "4. Login with your MySQL/MariaDB credentials"
    fi

    if [[ "$WEB_SERVER" == "both" ]]; then
        echo
        print_info "Multiple Web Servers Configured:"
        echo "├── Apache2: Available on configured URLs"
        echo "└── FrankenPHP: Available on configured URLs"
        echo "Note: Make sure only one web server is running on the same port to avoid conflicts"
    fi

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

    # Configure web servers based on user selection
    if [[ "$WEB_SERVER" == "apache2" ]]; then
        configure_apache
    elif [[ "$WEB_SERVER" == "frankenphp" ]]; then
        configure_frankenphp
    elif [[ "$WEB_SERVER" == "both" ]]; then
        configure_apache
        configure_frankenphp
    else
        print_info "Skipping web server configuration as requested"
    fi

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
