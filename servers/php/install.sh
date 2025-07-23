#!/bin/bash
#
# Script: install.sh
# Description: Interactive PHP CLI/FPM installer for Ubuntu-based systems
# Usage: ./install.sh [OPTIONS]
#

set -euo pipefail

# Get script directory and source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$BASE_DIR/_helpers/common.sh"
source "$BASE_DIR/_helpers/system.sh"
source "$BASE_DIR/_helpers/cli.sh"

# Global variables
VERBOSE=false
DRY_RUN=false
SILENT=false
SELECTED_VERSION=""
INSTALL_CLI=true
INSTALL_FPM=true
INSTALL_EXTENSIONS=true
INSTALL_APACHE_MOD=false

# Available PHP versions (Modern versions for Ubuntu 20.04+)
PHP_VERSIONS=("8.3" "8.4" "8.5")
PHP_VERSION_LABELS=("8.3 (Stable)" "8.4 (Stable)" "8.5 (Beta)")
DEFAULT_VERSION="8.3"

# Common PHP extensions
PHP_EXTENSIONS=(
    "common" "bcmath" "bz2" "curl" "gd" "gmp" "intl" "mbstring" 
    "opcache" "readline" "xml" "zip" "redis" "mysql" "imagick" "xdebug"
)

# Function to show help
show_help() {
    cat << EOF
PHP Installer for Ubuntu-based Systems

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    --dry-run           Test mode, show commands without executing
    --silent            Silent mode, use defaults without prompts
    --version VERSION   Specify PHP version (8.3, 8.4, 8.5)
    --no-extensions     Skip PHP extensions installation
    --with-apache       Install Apache2 and PHP module

Description:
    This script installs PHP CLI and FPM on Ubuntu-based systems (20.04+).
    It uses the ondrej/php PPA repository to provide access to multiple PHP versions.
    
    PHP CLI is always installed. FPM is installed if available for the selected version.
    In silent mode, defaults are: PHP ${DEFAULT_VERSION}, CLI+FPM(if available)+Extensions enabled.
    Web server modules can be installed optionally.

    Note: On Ubuntu 20.04, some newer PHP versions may have limited FPM/extension availability.
    The script automatically detects and installs only available packages.

Examples:
    $0                          # Interactive installation
    $0 --silent                 # Silent install with defaults (PHP ${DEFAULT_VERSION})
    $0 --silent --version 8.4   # Silent install PHP 8.4 Stable
    $0 --verbose --dry-run      # Show what would be installed
    $0 --silent --no-extensions # Install without extensions
    $0 --silent --with-apache   # Install with Apache2 module

EOF
}

# Function to add ondrej/php repository
add_php_repository() {
    print_info "Adding ondrej/php PPA repository..."
    execute_command "sudo add-apt-repository -y ppa:ondrej/php" "Adding ondrej/php PPA"
    execute_command "sudo apt update" "Updating package lists with new repository"
}

# Function to check Ubuntu version and PHP compatibility
check_php_compatibility() {
    local ubuntu_version
    ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "unknown")
    
    case "$ubuntu_version" in
        "20.04")
            # Ubuntu 20.04: Some limitations for newer PHP versions
            case "$SELECTED_VERSION" in
                "8.4")
                    print_warning "PHP 8.4 on Ubuntu 20.04: FPM package may not be available"
                    print_info "CLI and most extensions should work fine"
                    ;;
                "8.5")
                    print_warning "PHP 8.5 on Ubuntu 20.04: Limited package availability"
                    print_info "CLI and basic extensions may be available"
                    ;;
                "8.3")
                    print_info "PHP 8.3 is fully supported on Ubuntu 20.04"
                    ;;
            esac
            ;;
        "22.04"|"24.04")
            # Ubuntu 22.04+: Better support for newer versions
            case "$SELECTED_VERSION" in
                "8.5")
                    print_info "PHP 8.5 should have better availability on Ubuntu $ubuntu_version"
                    ;;
                *)
                    print_info "PHP $SELECTED_VERSION is well supported on Ubuntu $ubuntu_version"
                    ;;
            esac
            ;;
        *)
            print_warning "Ubuntu version $ubuntu_version compatibility not verified"
            print_info "The script will check package availability during installation"
            ;;
    esac
}

# Function to check if PHP extension is available
is_php_extension_available() {
    local version="$1"
    local extension="$2"
    local package_name="php${version}-${extension}"
    
    if apt-cache show "$package_name" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to display PHP version selection menu
select_php_version() {
    if [[ "$SILENT" == true ]]; then
        if [[ -z "$SELECTED_VERSION" ]]; then
            SELECTED_VERSION="$DEFAULT_VERSION"
        fi
        print_info "Using PHP $SELECTED_VERSION (silent mode)"
        return
    fi
    
    # Find default version index
    local default_index=0
    for i in "${!PHP_VERSIONS[@]}"; do
        if [[ "${PHP_VERSIONS[$i]}" == "$DEFAULT_VERSION" ]]; then
            default_index=$i
            break
        fi
    done
    
    # Create reordered arrays with default first
    local reordered_versions=()
    local reordered_labels=()
    
    # Add default version first
    reordered_versions+=("${PHP_VERSIONS[$default_index]}")
    reordered_labels+=("${PHP_VERSION_LABELS[$default_index]}")
    
    # Add other versions
    for i in "${!PHP_VERSIONS[@]}"; do
        if [[ "$i" != "$default_index" ]]; then
            reordered_versions+=("${PHP_VERSIONS[$i]}")
            reordered_labels+=("${PHP_VERSION_LABELS[$i]}")
        fi
    done
    
    SELECTED_VERSION=$(show_selection_menu "Available PHP versions" "${reordered_labels[@]}")
    
    # Convert label back to version number
    for i in "${!reordered_labels[@]}"; do
        if [[ "${reordered_labels[$i]}" == "$SELECTED_VERSION" ]]; then
            SELECTED_VERSION="${reordered_versions[$i]}"
            break
        fi
    done
    
    print_success "Selected PHP $SELECTED_VERSION"
}

# Function to configure installation options
configure_installation() {
    if [[ "$SILENT" == true ]]; then
        print_info "Using default configuration (silent mode):"
        echo "  PHP CLI: Yes (auto-install)"
        echo "  PHP FPM: $([ "$INSTALL_FPM" == true ] && echo "Yes (auto-install)" || echo "Depends on availability")"
        echo "  Extensions: $([ "$INSTALL_EXTENSIONS" == true ] && echo "Yes" || echo "No")"
        echo "  Apache2: $([ "$INSTALL_APACHE_MOD" == true ] && echo "Yes" || echo "No")"
        return
    fi
    
    echo
    print_info "Installation Configuration:"
    print_info "PHP CLI will be installed automatically."
    print_info "PHP FPM will be installed if available for the selected version."
    
    # PHP Extensions
    if ! confirm_action "Install common PHP extensions?" "Y"; then
        INSTALL_EXTENSIONS=false
    fi
    
    # Web server modules
    echo
    print_info "Web Server Integration:"
    if confirm_action "Install Apache2 with PHP module?"; then
        INSTALL_APACHE_MOD=true
    fi
}

# Function to install PHP packages
install_php() {
    local packages=()
    local available_extensions=()
    local unavailable_extensions=()
    
    # Add base PHP package
    packages+=("php${SELECTED_VERSION}")
    
    # Add CLI (always installed)
    packages+=("php${SELECTED_VERSION}-cli")
    
    # Add FPM if available
    if apt-cache show "php${SELECTED_VERSION}-fpm" >/dev/null 2>&1; then
        packages+=("php${SELECTED_VERSION}-fpm")
        print_info "PHP FPM will be installed"
    else
        print_warning "PHP ${SELECTED_VERSION}-FPM is not available on this system"
        print_info "Only PHP CLI will be installed"
        INSTALL_FPM=false
    fi
    
    # Add extensions if selected
    if [[ "$INSTALL_EXTENSIONS" == true ]]; then
        print_info "Checking extension availability for PHP ${SELECTED_VERSION}..."
        
        for ext in "${PHP_EXTENSIONS[@]}"; do
            if is_php_extension_available "$SELECTED_VERSION" "$ext"; then
                packages+=("php${SELECTED_VERSION}-${ext}")
                available_extensions+=("$ext")
            else
                unavailable_extensions+=("$ext")
            fi
        done
        
        if [[ ${#available_extensions[@]} -gt 0 ]]; then
            print_info "Available extensions: ${available_extensions[*]}"
        fi
        
        if [[ ${#unavailable_extensions[@]} -gt 0 ]]; then
            print_warning "Skipping unavailable extensions: ${unavailable_extensions[*]}"
        fi
    fi
    
    install_packages "${packages[@]}"
}

# Function to configure PHP FPM
configure_php_fpm() {
    if [[ "$INSTALL_FPM" == true ]]; then
        print_info "Configuring PHP FPM..."
        enable_start_service "php${SELECTED_VERSION}-fpm"
    else
        print_info "Skipping PHP FPM configuration (not installed)"
    fi
}

# Function to install Apache2 and PHP module
install_apache_mod() {
    if [[ "$INSTALL_APACHE_MOD" == true ]]; then
        print_info "Installing Apache2 and PHP module..."
        
        install_packages "apache2" "libapache2-mod-php${SELECTED_VERSION}"
        
        # Enable PHP module and mod_rewrite
        execute_command "sudo a2enmod php${SELECTED_VERSION}" "Enabling PHP module"
        execute_command "sudo a2enmod rewrite" "Enabling mod_rewrite"
        
        enable_start_service "apache2"
        execute_command "sudo systemctl restart apache2" "Restarting Apache2 to load PHP module"
    fi
}

# Function to display installation summary
show_summary() {
    echo
    print_success "Installation Summary:"
    echo "  PHP Version: $SELECTED_VERSION"
    echo "  PHP CLI: $([ "$INSTALL_CLI" == true ] && echo "✓ Installed" || echo "✗ Skipped")"
    echo "  PHP FPM: $([ "$INSTALL_FPM" == true ] && echo "✓ Installed" || echo "✗ Skipped")"
    echo "  Extensions: $([ "$INSTALL_EXTENSIONS" == true ] && echo "✓ Installed" || echo "✗ Skipped")"
    echo "  Apache2: $([ "$INSTALL_APACHE_MOD" == true ] && echo "✓ Installed" || echo "✗ Skipped")"
    
    if [[ "$DRY_RUN" == false ]]; then
        echo
        print_info "Verification:"
        
        if [[ "$INSTALL_CLI" == true ]]; then
            php_version=$(php -v 2>/dev/null | head -n1 || echo "Not found")
            echo "  PHP CLI Version: $php_version"
        fi
        
        if [[ "$INSTALL_FPM" == true ]]; then
            fpm_status=$(sudo systemctl is-active "php${SELECTED_VERSION}-fpm" 2>/dev/null || echo "inactive")
            echo "  PHP FPM Status: $fpm_status"
            echo "  FPM Socket: /run/php/php${SELECTED_VERSION}-fpm.sock"
        fi
        
        echo
        print_info "Configuration files:"
        echo "  PHP CLI Config: /etc/php/${SELECTED_VERSION}/cli/php.ini"
        if [[ "$INSTALL_FPM" == true ]]; then
            echo "  PHP FPM Config: /etc/php/${SELECTED_VERSION}/fpm/php.ini"
            echo "  FPM Pool Config: /etc/php/${SELECTED_VERSION}/fpm/pool.d/www.conf"
        fi
    fi
}

# Function to show post-installation notes
show_post_install_notes() {
    echo
    print_info "Post-Installation Notes:"
    
    if [[ "$INSTALL_APACHE_MOD" == true ]]; then
        cat << EOF
  • Apache2 with PHP module is installed and configured
  • Document root: /var/www/html
  • Test PHP: Create /var/www/html/info.php with <?php phpinfo(); ?>
  • Apache configuration: /etc/apache2/
  • Service commands: sudo systemctl start|stop|restart|status apache2
    
EOF
    fi
    
    if [[ "$INSTALL_FPM" == true && "$INSTALL_APACHE_MOD" == false ]]; then
        cat << EOF
  • PHP FPM is configured to run on socket: /run/php/php${SELECTED_VERSION}-fpm.sock
  • For Nginx, add this to your server block:
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${SELECTED_VERSION}-fpm.sock;
    }
    
  • For Apache, install libapache2-mod-fcgid and configure:
    sudo apt install libapache2-mod-fcgid
    
EOF
    fi
    
    cat << EOF
  • To install additional extensions:
    sudo apt install php${SELECTED_VERSION}-[extension-name]
    
  • Common additional extensions (install manually if needed):
    sudo apt install php${SELECTED_VERSION}-gmp php${SELECTED_VERSION}-xdebug
    
  • To switch between PHP versions (if multiple installed):
    sudo update-alternatives --config php
    
  • Service management commands:
    sudo systemctl start|stop|restart|status php${SELECTED_VERSION}-fpm
    
EOF
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --silent)
                SILENT=true
                shift
                ;;
            --version)
                if [[ -n "${2:-}" ]]; then
                    if array_contains PHP_VERSIONS "$2"; then
                        SELECTED_VERSION="$2"
                    else
                        print_error "Invalid PHP version: $2. Available versions: ${PHP_VERSIONS[*]}"
                        exit 1
                    fi
                    shift 2
                else
                    print_error "--version requires a value"
                    exit 1
                fi
                ;;
            --no-extensions)
                INSTALL_EXTENSIONS=false
                shift
                ;;
            --with-apache)
                INSTALL_APACHE_MOD=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Script header
    show_script_header "PHP Installer for Ubuntu-based Systems"
    
    # Pre-installation checks
    check_ubuntu_system
    
    # Interactive configuration
    select_php_version
    check_php_compatibility
    configure_installation
    
    # Confirmation
    echo
    print_info "Installation Plan:"
    echo "  PHP Version: $SELECTED_VERSION"
    echo "  PHP CLI: Yes (auto-install)"
    echo "  PHP FPM: $([ "$INSTALL_FPM" == true ] && echo "Yes (auto-install)" || echo "Will check availability")"
    echo "  Extensions: $([ "$INSTALL_EXTENSIONS" == true ] && echo "Yes" || echo "No")"
    echo "  Apache2: $([ "$INSTALL_APACHE_MOD" == true ] && echo "Yes" || echo "No")"
    echo
    
    if [[ "$DRY_RUN" == false ]] && [[ "$SILENT" == false ]]; then
        if ! confirm_action "Proceed with installation?"; then
            print_info "Installation cancelled."
            exit 0
        fi
    elif [[ "$SILENT" == true ]]; then
        print_info "Proceeding with installation (silent mode)..."
    fi
    
    # Installation process
    echo
    print_info "Starting installation process..."
    
    update_system
    install_prerequisites "software-properties-common ca-certificates lsb-release apt-transport-https"
    add_php_repository
    install_php
    configure_php_fpm
    install_apache_mod
    
    # Post-installation
    show_summary
    show_post_install_notes
    
    echo
    print_success "PHP installation completed successfully!"
}

# Run main function
main "$@"