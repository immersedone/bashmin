#!/bin/bash

# BashMin phpMyAdmin Web Server Configuration Script
# Configures phpMyAdmin for nginx, Apache2, or FrankenPHP
# Author: BashMin Team
# Version: 1.0

set -euo pipefail

# Load helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh" 2>/dev/null || {
    echo "Error: Helper functions not found. Make sure this script is in the bashmin directory structure."
    exit 1
}

# Import colors from common.sh
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration defaults
PHPMYADMIN_DIR="/usr/share/phpmyadmin"
CONFIG_DIR="/etc/phpmyadmin"
WEB_SERVER=""
URL_TYPE=""
URL_PATH="pma-1337"
SUBDOMAIN=""
DOMAIN=""
PHP_VERSION="8.3"
FORCE_OVERWRITE=false
DRY_RUN=false

# Web server config paths
APACHE_CONFIG="/etc/apache2/conf-available/phpmyadmin.conf"
NGINX_CONFIG="/etc/nginx/sites-available/phpmyadmin"
FRANKENPHP_CONFIG="/etc/frankenphp/sites-available/phpmyadmin.json"

# Function to show help
show_help() {
    cat << EOF
BashMin phpMyAdmin Web Server Configuration Script

Usage: $0 [OPTIONS]

This script configures phpMyAdmin for nginx, Apache2, or FrankenPHP web servers.
It assumes phpMyAdmin is already installed at $PHPMYADMIN_DIR.

OPTIONS:
    -s, --server SERVER     Web server type: nginx, apache2, frankenphp, or all
    -t, --type TYPE         URL type: subdirectory or subdomain
    -p, --path PATH         Subdirectory path (default: pma-1337)
    -d, --domain DOMAIN     Base domain for subdomain configuration
    --subdomain PREFIX      Subdomain prefix (default: pma)
    --php-version VERSION   PHP version for FPM socket (default: 8.3)
    --phpmyadmin-dir DIR    phpMyAdmin installation directory (default: $PHPMYADMIN_DIR)
    -f, --force             Overwrite existing configurations without prompting
    --dry-run               Show what would be configured without making changes
    -h, --help              Show this help message

EXAMPLES:
    $0                                          # Interactive configuration
    $0 -s nginx -t subdirectory                # nginx with /pma-1337 path
    $0 -s apache2 -t subdomain -d example.com  # Apache2 with pma.example.com
    $0 -s frankenphp -p admin-db               # FrankenPHP with /admin-db path
    $0 -s all -t subdirectory -p secure-db     # All servers with /secure-db path
    $0 --dry-run -s nginx -t subdomain         # Preview nginx subdomain config

SUPPORTED CONFIGURATIONS:
    nginx:      Full support with optimized PHP-FPM integration
    apache2:    Virtual hosts and alias configurations with security headers
    frankenphp: Modern PHP server with automatic HTTPS and JSON config
    all:        Configure all detected web servers simultaneously

URL TYPES:
    subdirectory: Access via http://yoursite.com/path
    subdomain:    Access via http://subdomain.domain.com

REQUIREMENTS:
    - phpMyAdmin installed at specified directory
    - Target web server installed and running
    - PHP-FPM configured (for nginx and FrankenPHP)
    - Sudo privileges for configuration file creation

EOF
}

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
    local servers=()

    # Check for nginx
    if command -v nginx &> /dev/null && systemctl list-unit-files nginx.service &> /dev/null; then
        servers+=("nginx")
        print_success "✓ nginx detected"
    fi

    # Check for Apache2
    if command -v apache2 &> /dev/null && systemctl list-unit-files apache2.service &> /dev/null; then
        servers+=("apache2")
        print_success "✓ Apache2 detected"
    fi

    # Check for FrankenPHP
    if command -v frankenphp &> /dev/null || systemctl list-unit-files frankenphp.service &> /dev/null; then
        servers+=("frankenphp")
        print_success "✓ FrankenPHP detected"
    fi

    if [[ ${#servers[@]} -eq 0 ]]; then
        print_error "No supported web servers detected (nginx, Apache2, or FrankenPHP)"
        exit 1
    fi

    echo "${servers[@]}"
}

# Function to validate prerequisites
validate_prerequisites() {
    print_info "Validating prerequisites..."

    # Check sudo access
    if [[ $EUID -eq 0 ]]; then
        print_info "Running as root"
    elif ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. Please enter your password when prompted."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges"
            exit 1
        fi
    fi

    # Check if phpMyAdmin directory exists
    if [[ ! -d "$PHPMYADMIN_DIR" ]]; then
        print_error "phpMyAdmin directory not found: $PHPMYADMIN_DIR"
        print_info "Please install phpMyAdmin first or specify the correct path with --phpmyadmin-dir"
        exit 1
    fi

    # Check if phpMyAdmin index.php exists
    if [[ ! -f "$PHPMYADMIN_DIR/index.php" ]]; then
        print_error "phpMyAdmin installation appears incomplete: missing index.php"
        exit 1
    fi

    print_success "Prerequisites validated"
}

# Function for interactive web server selection
interactive_server_selection() {
    if [[ -n "$WEB_SERVER" ]]; then
        return 0
    fi

    local available_servers
    available_servers=($(detect_web_servers))

    echo
    print_info "Available web servers:"
    for i in "${!available_servers[@]}"; do
        echo "$((i+1))) ${available_servers[$i]}"
    done
    echo "$((${#available_servers[@]}+1))) all (configure all detected servers)"

    while true; do
        read -p "Select web server (1-$((${#available_servers[@]}+1))): " choice
        if [[ "$choice" -ge 1 && "$choice" -le ${#available_servers[@]} ]]; then
            WEB_SERVER="${available_servers[$((choice-1))]}"
            break
        elif [[ "$choice" -eq $((${#available_servers[@]}+1)) ]]; then
            WEB_SERVER="all"
            break
        else
            print_error "Invalid selection. Please choose 1-$((${#available_servers[@]}+1))."
        fi
    done

    print_success "Selected: $WEB_SERVER"
}

# Function for interactive URL configuration
interactive_url_configuration() {
    if [[ -n "$URL_TYPE" ]]; then
        return 0
    fi

    echo
    print_info "URL Configuration:"
    echo "1) Subdirectory (e.g., http://yoursite.com/pma-1337)"
    echo "2) Subdomain (e.g., http://pma.yoursite.com)"

    while true; do
        read -p "Select URL type (1-2): " choice
        case $choice in
            1) URL_TYPE="subdirectory"; break ;;
            2) URL_TYPE="subdomain"; break ;;
            *) print_error "Invalid choice. Please enter 1 or 2." ;;
        esac
    done

    if [[ "$URL_TYPE" == "subdirectory" ]]; then
        read -p "Enter subdirectory path (default: $URL_PATH): " input_path
        if [[ -n "$input_path" ]]; then
            URL_PATH="${input_path#/}"
            URL_PATH="${URL_PATH%/}"
        fi
        print_success "phpMyAdmin will be accessible at: /${URL_PATH}"

    elif [[ "$URL_TYPE" == "subdomain" ]]; then
        if [[ -z "$DOMAIN" ]]; then
            read -p "Enter your base domain (e.g., example.com): " DOMAIN
            while [[ -z "$DOMAIN" ]]; do
                print_error "Domain is required for subdomain configuration"
                read -p "Enter your base domain: " DOMAIN
            done
        fi

        if [[ -z "$SUBDOMAIN" ]]; then
            read -p "Enter subdomain prefix (default: pma): " input_subdomain
            SUBDOMAIN="${input_subdomain:-pma}"
        fi

        print_success "phpMyAdmin will be accessible at: http://${SUBDOMAIN}.${DOMAIN}"
    fi
}

# Function to configure nginx
configure_nginx() {
    print_info "Configuring nginx for phpMyAdmin..."

    # Backup existing config
    if [[ -f "$NGINX_CONFIG" ]]; then
        if [[ "$FORCE_OVERWRITE" == false ]]; then
            print_warning "nginx configuration already exists: $NGINX_CONFIG"
            read -p "Overwrite existing configuration? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Skipping nginx configuration"
                return 0
            fi
        fi

        local backup_config="${NGINX_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
        sudo cp "$NGINX_CONFIG" "$backup_config"
        print_info "Backup created: $backup_config"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create nginx configuration: $NGINX_CONFIG"
        return 0
    fi

    # Create nginx sites-available directory if it doesn't exist
    sudo mkdir -p "$(dirname "$NGINX_CONFIG")"

    if [[ "$URL_TYPE" == "subdomain" ]]; then
        # Subdomain configuration
        sudo tee "$NGINX_CONFIG" > /dev/null << EOF
# phpMyAdmin nginx configuration - Subdomain
server {
    listen 80;
    listen [::]:80;

    server_name ${SUBDOMAIN}.${DOMAIN};
    root ${PHPMYADMIN_DIR};
    index index.php index.html index.htm;

    # Security headers
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Main location block
    location / {
        try_files \$uri \$uri/ =404;
    }

    # PHP handling
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        # Security for phpMyAdmin
        fastcgi_param HTTP_PROXY "";
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_connect_timeout 300;
    }

    # Deny access to sensitive directories
    location ~ ^/(templates|libraries|setup/lib)/ {
        deny all;
        return 404;
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
        return 404;
    }

    # Static files optimization
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options nosniff always;
    }

    # Logs
    access_log /var/log/nginx/${SUBDOMAIN}.${DOMAIN}-access.log;
    error_log /var/log/nginx/${SUBDOMAIN}.${DOMAIN}-error.log;
}

# HTTPS server block (uncomment when you have SSL certificates)
# server {
#     listen 443 ssl http2;
#     listen [::]:443 ssl http2;
#
#     server_name ${SUBDOMAIN}.${DOMAIN};
#     root ${PHPMYADMIN_DIR};
#     index index.php index.html index.htm;
#
#     # SSL Configuration (update paths to your certificates)
#     # ssl_certificate /path/to/your/${SUBDOMAIN}.${DOMAIN}.crt;
#     # ssl_certificate_key /path/to/your/${SUBDOMAIN}.${DOMAIN}.key;
#     # ssl_protocols TLSv1.2 TLSv1.3;
#     # ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
#     # ssl_prefer_server_ciphers off;
#
#     # Include same location blocks as HTTP version above
#     # ... (copy all location blocks from HTTP server)
# }
EOF

        print_success "nginx subdomain configuration created: $NGINX_CONFIG"

        # Enable the site
        if sudo ln -sf "$NGINX_CONFIG" "/etc/nginx/sites-enabled/phpmyadmin" 2>/dev/null; then
            print_success "nginx site enabled"
        else
            print_warning "Failed to enable nginx site - you may need to do this manually"
        fi

    else
        # Subdirectory configuration
        sudo tee "$NGINX_CONFIG" > /dev/null << EOF
# phpMyAdmin nginx configuration - Subdirectory
# Include this in your main server block or create a separate server block

# Alias configuration for subdirectory access
location /${URL_PATH} {
    alias ${PHPMYADMIN_DIR};
    index index.php index.html index.htm;

    # Security headers
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Try files in the aliased directory
    try_files \$uri \$uri/ =404;

    # Handle PHP files
    location ~ /${URL_PATH}/(.+\.php)\$ {
        alias ${PHPMYADMIN_DIR};
        fastcgi_split_path_info ^/${URL_PATH}/(.+\.php)(/.*)$;
        fastcgi_param SCRIPT_FILENAME ${PHPMYADMIN_DIR}/\$1;
        fastcgi_param PATH_INFO \$2;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        include fastcgi_params;

        # Security for phpMyAdmin
        fastcgi_param HTTP_PROXY "";
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_connect_timeout 300;
    }

    # Deny access to sensitive directories
    location ~ ^/${URL_PATH}/(templates|libraries|setup/lib)/ {
        deny all;
        return 404;
    }

    # Static files optimization
    location ~* ^/${URL_PATH}/.*\.(css|js|png|jpg|jpeg|gif|ico|svg)\$ {
        alias ${PHPMYADMIN_DIR};
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options nosniff always;
    }
}

# Alternative: Full server block for subdirectory (if you prefer isolation)
# server {
#     listen 80;
#     server_name your-domain.com;
#
#     location /${URL_PATH} {
#         # Include the location block content above
#     }
#
#     # Your other site configurations...
# }
EOF

        print_success "nginx subdirectory configuration created: $NGINX_CONFIG"
        print_info "Note: For subdirectory access, include this configuration in your main nginx server block"
    fi

    # Test nginx configuration
    if sudo nginx -t 2>/dev/null; then
        print_success "nginx configuration test passed"

        # Reload nginx
        if sudo systemctl reload nginx 2>/dev/null; then
            print_success "nginx reloaded"
        else
            print_warning "Failed to reload nginx - you may need to do this manually"
        fi
    else
        print_error "nginx configuration test failed - please check the configuration"
    fi
}

# Function to configure Apache2 (reused from main script with modifications)
configure_apache() {
    print_info "Configuring Apache2 for phpMyAdmin..."

    local config_file="$APACHE_CONFIG"

    # For subdomain, create a virtual host file instead
    if [[ "$URL_TYPE" == "subdomain" ]]; then
        config_file="/etc/apache2/sites-available/${SUBDOMAIN}.${DOMAIN}.conf"
    fi

    # Backup existing config
    if [[ -f "$config_file" ]]; then
        if [[ "$FORCE_OVERWRITE" == false ]]; then
            print_warning "Apache2 configuration already exists: $config_file"
            read -p "Overwrite existing configuration? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Skipping Apache2 configuration"
                return 0
            fi
        fi

        local backup_config="${config_file}.backup-$(date +%Y%m%d-%H%M%S)"
        sudo cp "$config_file" "$backup_config"
        print_info "Backup created: $backup_config"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create Apache2 configuration: $config_file"
        return 0
    fi

    if [[ "$URL_TYPE" == "subdomain" ]]; then
        # Create virtual host for subdomain
        sudo tee "$config_file" > /dev/null << EOF
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

    ErrorLog \${APACHE_LOG_DIR}/${SUBDOMAIN}.${DOMAIN}-error.log
    CustomLog \${APACHE_LOG_DIR}/${SUBDOMAIN}.${DOMAIN}-access.log combined
</VirtualHost>

# HTTPS Virtual Host (uncomment when you have SSL certificates)
# <VirtualHost *:443>
#     ServerName ${SUBDOMAIN}.${DOMAIN}
#     DocumentRoot ${PHPMYADMIN_DIR}
#
#     # SSL Configuration
#     # SSLEngine on
#     # SSLCertificateFile /path/to/your/${SUBDOMAIN}.${DOMAIN}.crt
#     # SSLCertificateKeyFile /path/to/your/${SUBDOMAIN}.${DOMAIN}.key
#
#     # Include same directory and security settings as HTTP version
#     # ... (copy Directory blocks and headers from above)
# </VirtualHost>
EOF

        print_success "Apache2 virtual host created: $config_file"

        # Enable the site
        if sudo a2ensite "${SUBDOMAIN}.${DOMAIN}" 2>/dev/null; then
            print_success "Virtual host enabled"
        else
            print_warning "Failed to enable virtual host - you may need to do this manually"
        fi

    else
        # Create alias configuration for subdirectory access
        sudo tee "$config_file" > /dev/null << EOF
# phpMyAdmin Apache2 configuration - Subdirectory Access
Alias /${URL_PATH} ${PHPMYADMIN_DIR}

<Directory ${PHPMYADMIN_DIR}>
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    AllowOverride None
    Require all granted

    <IfModule mod_php.c>
        php_admin_value upload_tmp_dir /var/lib/phpmyadmin/tmp
        php_admin_value open_basedir ${PHPMYADMIN_DIR}/:/var/lib/phpmyadmin/:/etc/phpmyadmin/:/usr/share/php/php-gettext/:/usr/share/php/php-php-gettext/:/usr/share/javascript/:/usr/share/php/tcpdf/:/usr/share/doc/phpmyadmin/:/usr/share/php/phpseclib/:/usr/share/php/PhpMyAdmin/:/usr/share/php/Symfony/:/usr/share/php/Twig/:/usr/share/php/Twig-Extensions/:/usr/share/php/ReCaptcha/:/usr/share/php/Psr/Container/:/usr/share/php/Psr/Cache/:/usr/share/php/Psr/Log/:/usr/share/php/Psr/SimpleCache/
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

# Security headers for this alias
<Location /${URL_PATH}>
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
</Location>
EOF

        print_success "Apache2 configuration created: $config_file"

        # Enable the configuration
        if sudo a2enconf phpmyadmin 2>/dev/null; then
            print_success "phpMyAdmin configuration enabled"
        else
            print_warning "Failed to enable configuration - you may need to do this manually"
        fi
    fi

    # Enable required modules
    sudo a2enmod headers 2>/dev/null || print_warning "Headers module already enabled or not available"
    if [[ "$URL_TYPE" == "subdomain" ]]; then
        sudo a2enmod ssl 2>/dev/null || print_warning "SSL module already enabled or not available"
    fi

    # Test Apache configuration
    if sudo apache2ctl configtest 2>/dev/null; then
        print_success "Apache2 configuration test passed"

        # Reload Apache
        if sudo systemctl reload apache2 2>/dev/null; then
            print_success "Apache2 reloaded"
        else
            print_warning "Failed to reload Apache2 - you may need to do this manually"
        fi
    else
        print_error "Apache2 configuration test failed - please check the configuration"
    fi
}

# Function to configure FrankenPHP (reused from main script)
configure_frankenphp() {
    print_info "Configuring FrankenPHP for phpMyAdmin..."

    # Backup existing config
    if [[ -f "$FRANKENPHP_CONFIG" ]]; then
        if [[ "$FORCE_OVERWRITE" == false ]]; then
            print_warning "FrankenPHP configuration already exists: $FRANKENPHP_CONFIG"
            read -p "Overwrite existing configuration? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Skipping FrankenPHP configuration"
                return 0
            fi
        fi

        local backup_config="${FRANKENPHP_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
        sudo cp "$FRANKENPHP_CONFIG" "$backup_config"
        print_info "Backup created: $backup_config"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would create FrankenPHP configuration: $FRANKENPHP_CONFIG"
        return 0
    fi

    # Create FrankenPHP sites directory if it doesn't exist
    sudo mkdir -p "$(dirname "$FRANKENPHP_CONFIG")"

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
                          "php_fastcgi": "unix//run/php/php${PHP_VERSION}-fpm.sock"
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
        # Subdirectory configuration
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
                  "php_fastcgi": "unix//run/php/php${PHP_VERSION}-fpm.sock"
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
    sudo chown -R www-data:www-data /var/log/frankenphp 2>/dev/null || true

    # Test and reload FrankenPHP configuration
    if command -v frankenphp &> /dev/null; then
        if frankenphp validate --config "$FRANKENPHP_CONFIG" 2>/dev/null; then
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

# Function to show configuration summary
show_summary() {
    echo
    print_header "Configuration Summary"

    echo "phpMyAdmin Directory: $PHPMYADMIN_DIR"
    echo "URL Type: $URL_TYPE"

    if [[ "$URL_TYPE" == "subdomain" ]]; then
        echo "Access URL: http://${SUBDOMAIN}.${DOMAIN}"
        echo "HTTPS URL: https://${SUBDOMAIN}.${DOMAIN} (when SSL is configured)"
    else
        echo "Access Path: /${URL_PATH}"
        echo "Access URL: http://your-server/${URL_PATH}"
    fi

    echo "PHP Version: $PHP_VERSION"
    echo

    print_info "Configured web servers:"

    local configured_any=false

    if [[ "$WEB_SERVER" == "nginx" || "$WEB_SERVER" == "all" ]] && command -v nginx &> /dev/null; then
        echo "├── nginx: $NGINX_CONFIG"
        configured_any=true
    fi

    if [[ "$WEB_SERVER" == "apache2" || "$WEB_SERVER" == "all" ]] && command -v apache2 &> /dev/null; then
        if [[ "$URL_TYPE" == "subdomain" ]]; then
            echo "├── Apache2: /etc/apache2/sites-available/${SUBDOMAIN}.${DOMAIN}.conf"
        else
            echo "├── Apache2: $APACHE_CONFIG"
        fi
        configured_any=true
    fi

    if [[ "$WEB_SERVER" == "frankenphp" || "$WEB_SERVER" == "all" ]] && (command -v frankenphp &> /dev/null || systemctl list-unit-files frankenphp.service &> /dev/null); then
        echo "└── FrankenPHP: $FRANKENPHP_CONFIG"
        configured_any=true
    fi

    if [[ "$configured_any" == false ]]; then
        echo "└── No web servers were configured"
    fi

    echo
    print_info "Next steps:"
    echo "1. Ensure your database server (MySQL/MariaDB) is running"
    echo "2. Ensure PHP-FPM is running: sudo systemctl status php${PHP_VERSION}-fpm"

    if [[ "$URL_TYPE" == "subdomain" ]]; then
        echo "3. Configure DNS to point ${SUBDOMAIN}.${DOMAIN} to your server"
        echo "4. Access phpMyAdmin at http://${SUBDOMAIN}.${DOMAIN}"
        echo "5. Set up SSL certificate for production use"
    else
        echo "3. Access phpMyAdmin at http://your-server/${URL_PATH}"
        echo "4. Consider setting up SSL for production use"
    fi

    echo
    if [[ "$WEB_SERVER" == "all" ]]; then
        print_warning "Multiple web servers configured - ensure only one is running on each port to avoid conflicts"
    fi
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--server)
                WEB_SERVER="$2"
                shift 2
                ;;
            -t|--type)
                URL_TYPE="$2"
                shift 2
                ;;
            -p|--path)
                URL_PATH="$2"
                shift 2
                ;;
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            --subdomain)
                SUBDOMAIN="$2"
                shift 2
                ;;
            --php-version)
                PHP_VERSION="$2"
                shift 2
                ;;
            --phpmyadmin-dir)
                PHPMYADMIN_DIR="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_OVERWRITE=true
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

    print_header "phpMyAdmin Web Server Configuration"

    # Validate prerequisites
    validate_prerequisites

    # Interactive configuration if not provided via arguments
    interactive_server_selection
    interactive_url_configuration

    # Set default subdomain if not provided
    if [[ "$URL_TYPE" == "subdomain" && -z "$SUBDOMAIN" ]]; then
        SUBDOMAIN="pma"
    fi

    echo
    print_info "Configuration Plan:"
    echo "Web Server: $WEB_SERVER"
    echo "URL Type: $URL_TYPE"
    if [[ "$URL_TYPE" == "subdomain" ]]; then
        echo "Domain: ${SUBDOMAIN}.${DOMAIN}"
    else
        echo "Path: /${URL_PATH}"
    fi
    echo "PHP Version: $PHP_VERSION"
    echo "phpMyAdmin Dir: $PHPMYADMIN_DIR"

    if [[ "$DRY_RUN" == false ]]; then
        echo
        read -p "Proceed with configuration? (Y/n): " -r
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            print_info "Configuration cancelled"
            exit 0
        fi
    fi

    echo
    print_info "Starting configuration..."

    # Configure selected web servers
    case "$WEB_SERVER" in
        "nginx")
            configure_nginx
            ;;
        "apache2")
            configure_apache
            ;;
        "frankenphp")
            configure_frankenphp
            ;;
        "all")
            # Configure all detected servers
            local available_servers
            available_servers=($(detect_web_servers))

            for server in "${available_servers[@]}"; do
                echo
                print_info "Configuring $server..."
                case "$server" in
                    "nginx") configure_nginx ;;
                    "apache2") configure_apache ;;
                    "frankenphp") configure_frankenphp ;;
                esac
            done
            ;;
    esac

    # Show summary
    show_summary

    if [[ "$DRY_RUN" == false ]]; then
        print_success "phpMyAdmin web server configuration completed!"
    else
        print_info "Dry run completed - no changes were made"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi