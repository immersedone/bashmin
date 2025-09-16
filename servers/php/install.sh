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
# SELECTED_VERSION removed - now auto-installing multiple versions
INSTALL_CLI=true
INSTALL_FPM=true
INSTALL_EXTENSIONS=true
INSTALL_APACHE_MOD=false
CONFIGURE_PHP=true
APPLY_PRODUCTION_CONFIG=false
APPLY_DEVELOPMENT_CONFIG=false

# PHP versions will be dynamically detected based on Ubuntu version
PHP_VERSIONS=()
DEFAULT_VERSION=""

# Common PHP extensions
PHP_EXTENSIONS=(
    "common" "bcmath" "bz2" "curl" "gd" "gmp" "intl" "mbstring" 
    "opcache" "readline" "xml" "zip" "redis" "mysql" "imagick" "xdebug"
)

# Default PHP configuration values for post-install setup
declare -A PHP_CONFIG=(
    ["memory_limit"]="256M"
    ["upload_max_filesize"]="128M"
    ["post_max_size"]="128M"
    ["max_execution_time"]="300"
    ["max_input_time"]="300"
    ["max_input_vars"]="3000"
    ["max_file_uploads"]="20"
    ["date.timezone"]="UTC"
    ["opcache.enable"]="1"
    ["opcache.enable_cli"]="0"
    ["opcache.memory_consumption"]="128"
    ["opcache.max_accelerated_files"]="4000"
    ["expose_php"]="Off"
    ["display_errors"]="Off"
    ["log_errors"]="On"
    ["error_reporting"]="E_ALL & ~E_DEPRECATED & ~E_STRICT"
    ["session.cookie_httponly"]="1"
    ["session.use_strict_mode"]="1"
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
    --no-configure      Skip PHP configuration after installation
    --production        Apply production-ready PHP configuration
    --development       Apply development-friendly PHP configuration
    --memory-limit SIZE Set PHP memory limit (default: 256M)
    --upload-size SIZE  Set upload max filesize (default: 128M)

Description:
    This script installs PHP CLI and FPM on Ubuntu-based systems (20.04+).
    It uses the ondrej/php PPA repository to provide access to multiple PHP versions.
    After installation, it automatically configures PHP with sensible defaults.
    
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
    $0 --silent --production    # Install with production PHP configuration
    $0 --silent --development   # Install with development PHP configuration
    $0 --version 8.3 --memory-limit 512M --upload-size 64M

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
            print_info "Installing latest available PHP versions for Ubuntu 20.04"
            print_warning "Note: Newer PHP versions may have limited FPM/extension availability on Ubuntu 20.04"
            ;;
        "22.04"|"24.04")
            # Ubuntu 22.04+: Better support for newer versions
            print_info "Installing latest available PHP versions for Ubuntu $ubuntu_version"
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

# Function to detect available PHP versions based on Ubuntu system
detect_php_versions() {
    local ubuntu_version
    ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "unknown")

    print_info "Detecting available PHP versions for Ubuntu $ubuntu_version..."

    # Add ondrej/php repository first to get latest versions
    if ! grep -q "ondrej/php" /etc/apt/sources.list.d/* 2>/dev/null; then
        print_info "Adding ondrej/php PPA repository for version detection..."
        execute_command "sudo add-apt-repository -y ppa:ondrej/php" "Adding ondrej/php PPA"
        execute_command "sudo apt update" "Updating package lists"
    fi

    # Detect all available PHP versions from repository
    local all_versions=()
    local available_versions=()

    # Get all PHP versions available in the repository
    mapfile -t all_versions < <(apt-cache search --names-only '^php[0-9]\.[0-9]$' | grep -o 'php[0-9]\.[0-9]' | sed 's/php//' | sort -V)

    print_info "Found PHP versions in repository: ${all_versions[*]}"

    # Filter to only supported/maintained versions and check CLI availability
    for version in "${all_versions[@]}"; do
        # Check if CLI package is available (basic requirement)
        if apt-cache show "php${version}-cli" >/dev/null 2>&1; then
            # Only include PHP 7.4+ (older versions are deprecated)
            if [[ $(echo "$version" | cut -d. -f1) -ge 7 ]] && [[ $(echo "$version" | cut -d. -f2) -ge 4 ]] || [[ $(echo "$version" | cut -d. -f1) -ge 8 ]]; then
                available_versions+=("$version")
            fi
        fi
    done

    # Take up to the latest 3 available versions
    local total_versions=${#available_versions[@]}
    local start_index=$((total_versions > 3 ? total_versions - 3 : 0))

    PHP_VERSIONS=("${available_versions[@]:$start_index}")

    if [[ ${#PHP_VERSIONS[@]} -eq 0 ]]; then
        print_error "No supported PHP versions found in repository"
        exit 1
    fi

    # Set the latest stable version as default (not beta/RC)
    DEFAULT_VERSION="${PHP_VERSIONS[-1]}"

    # Find the latest stable version (skip beta/RC/alpha versions)
    for i in $(seq $((${#PHP_VERSIONS[@]} - 1)) -1 0); do
        version="${PHP_VERSIONS[$i]}"
        if ! apt-cache show "php${version}" 2>/dev/null | grep -iq "beta\|rc\|alpha"; then
            DEFAULT_VERSION="$version"
            break
        fi
    done

    print_success "Selected PHP versions for installation: ${PHP_VERSIONS[*]}"
    print_success "Default version (CLI symlinks): $DEFAULT_VERSION"
}

# Function to configure installation options
configure_installation() {
    if [[ "$SILENT" == true ]]; then
        print_info "Using default configuration (silent mode):"
        echo "  PHP CLI: Yes (auto-install)"
        echo "  PHP FPM: $([ "$INSTALL_FPM" == true ] && echo "Yes (auto-install)" || echo "Depends on availability")"
        echo "  Extensions: $([ "$INSTALL_EXTENSIONS" == true ] && echo "Yes" || echo "No")"
        echo "  Apache2: $([ "$INSTALL_APACHE_MOD" == true ] && echo "Yes" || echo "No")"
        echo "  PHP Configuration: $([ "$CONFIGURE_PHP" == true ] && echo "Yes" || echo "No")"
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
    
    # PHP Configuration
    echo
    print_info "PHP Configuration:"
    if ! confirm_action "Configure PHP with optimized settings after installation?" "Y"; then
        CONFIGURE_PHP=false
    else
        echo
        print_info "Environment Configuration:"
        PS3="Select environment type: "
        select env_type in "Production (secure, optimized)" "Development (debug-friendly)" "Custom (configure manually later)" "Skip configuration"; do
            case $env_type in
                "Production (secure, optimized)")
                    APPLY_PRODUCTION_CONFIG=true
                    break
                    ;;
                "Development (debug-friendly)")
                    APPLY_DEVELOPMENT_CONFIG=true
                    break
                    ;;
                "Custom (configure manually later)"|"Skip configuration")
                    break
                    ;;
                *)
                    print_error "Invalid selection"
                    ;;
            esac
        done
    fi
}

# Function to install all PHP versions
install_php() {
    local all_packages=()
    local fmp_available_versions=()

    print_info "Installing PHP versions: ${PHP_VERSIONS[*]}"

    # Install each PHP version
    for version in "${PHP_VERSIONS[@]}"; do
        local version_packages=()
        local available_extensions=()
        local unavailable_extensions=()

        print_info "Preparing PHP ${version} packages..."

        # Add base PHP package and CLI
        version_packages+=("php${version}" "php${version}-cli")

        # Check FPM availability
        if apt-cache show "php${version}-fpm" >/dev/null 2>&1; then
            version_packages+=("php${version}-fpm")
            fmp_available_versions+=("$version")
            print_info "PHP ${version}-FPM will be installed"
        else
            print_warning "PHP ${version}-FPM is not available"
        fi

        # Add extensions if selected
        if [[ "$INSTALL_EXTENSIONS" == true ]]; then
            print_info "Checking extension availability for PHP ${version}..."

            for ext in "${PHP_EXTENSIONS[@]}"; do
                if is_php_extension_available "$version" "$ext"; then
                    version_packages+=("php${version}-${ext}")
                    available_extensions+=("$ext")
                else
                    unavailable_extensions+=("$ext")
                fi
            done

            if [[ ${#available_extensions[@]} -gt 0 ]]; then
                print_info "PHP ${version} available extensions: ${available_extensions[*]}"
            fi

            if [[ ${#unavailable_extensions[@]} -gt 0 ]]; then
                print_warning "PHP ${version} unavailable extensions: ${unavailable_extensions[*]}"
            fi
        fi

        # Add to master package list
        all_packages+=("${version_packages[@]}")
    done

    # Install all packages at once
    print_info "Installing all PHP packages..."
    install_packages "${all_packages[@]}"

    # Set up alternatives for default PHP CLI
    print_info "Configuring PHP CLI alternatives..."
    local priority=100
    for version in "${PHP_VERSIONS[@]}"; do
        if [[ "$version" == "$DEFAULT_VERSION" ]]; then
            priority=200  # Higher priority for default version
        else
            priority=100
        fi

        execute_command "sudo update-alternatives --install /usr/bin/php php /usr/bin/php${version} $priority" "Setting up PHP $version alternative"
    done

    # Set FPM availability flag
    if [[ ${#fmp_available_versions[@]} -gt 0 ]]; then
        INSTALL_FPM=true
        print_success "PHP FPM available for versions: ${fmp_available_versions[*]}"
    else
        INSTALL_FPM=false
        print_warning "PHP FPM not available for any installed versions"
    fi
}

# Function to configure PHP FPM
configure_php_fpm() {
    if [[ "$INSTALL_FPM" == true ]]; then
        print_info "Configuring PHP FPM for all installed versions..."
        for version in "${PHP_VERSIONS[@]}"; do
            if systemctl list-unit-files | grep -q "php${version}-fpm.service"; then
                print_info "Enabling PHP ${version}-FPM service..."
                enable_start_service "php${version}-fpm"
            fi
        done
    else
        print_info "Skipping PHP FPM configuration (not installed)"
    fi
}

# Function to install Apache2 and PHP module
install_apache_mod() {
    if [[ "$INSTALL_APACHE_MOD" == true ]]; then
        print_info "Installing Apache2 and PHP module..."
        
        install_packages "apache2" "libapache2-mod-php${DEFAULT_VERSION}"

        # Enable PHP module and mod_rewrite
        execute_command "sudo a2enmod php${DEFAULT_VERSION}" "Enabling PHP module"
        execute_command "sudo a2enmod rewrite" "Enabling mod_rewrite"
        
        enable_start_service "apache2"
        execute_command "sudo systemctl restart apache2" "Restarting Apache2 to load PHP module"
    fi
}

# Function to apply production-ready settings
apply_production_settings() {
    PHP_CONFIG["display_errors"]="Off"
    PHP_CONFIG["display_startup_errors"]="Off"
    PHP_CONFIG["error_reporting"]="E_ALL & ~E_DEPRECATED & ~E_STRICT"
    PHP_CONFIG["log_errors"]="On"
    PHP_CONFIG["expose_php"]="Off"
    PHP_CONFIG["session.cookie_secure"]="1"
    PHP_CONFIG["session.cookie_httponly"]="1"
    PHP_CONFIG["session.use_strict_mode"]="1"
    PHP_CONFIG["opcache.enable"]="1"
    PHP_CONFIG["opcache.validate_timestamps"]="0"
    
    print_info "Applied production security settings"
}

# Function to apply development-friendly settings
apply_development_settings() {
    PHP_CONFIG["display_errors"]="On"
    PHP_CONFIG["display_startup_errors"]="On"
    PHP_CONFIG["error_reporting"]="E_ALL"
    PHP_CONFIG["log_errors"]="On"
    PHP_CONFIG["expose_php"]="On"
    PHP_CONFIG["session.cookie_secure"]="0"
    PHP_CONFIG["opcache.enable"]="1"
    PHP_CONFIG["opcache.validate_timestamps"]="1"
    PHP_CONFIG["opcache.revalidate_freq"]="0"
    
    print_info "Applied development-friendly settings"
}

# Function to backup php.ini file
backup_php_ini() {
    local ini_file="$1"
    local backup_file="${ini_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$ini_file" ]]; then
        execute_command "sudo cp '$ini_file' '$backup_file'" "Creating backup of $ini_file"
        print_info "Backup created: $backup_file"
    fi
}

# Function to update php.ini setting
update_php_setting() {
    local ini_file="$1"
    local setting="$2"
    local value="$3"
    local dry_run="${DRY_RUN:-false}"
    
    if [[ ! -f "$ini_file" ]]; then
        print_warning "PHP ini file not found: $ini_file"
        return 1
    fi
    
    if [[ "$dry_run" == true ]]; then
        print_info "[DRY-RUN] Would update $setting = $value in $ini_file"
        return 0
    fi
    
    # Check if setting exists (commented or uncommented)
    if grep -q "^;*\s*$setting\s*=" "$ini_file"; then
        # Setting exists, update it
        sudo sed -i "s|^;*\s*$setting\s*=.*|$setting = $value|" "$ini_file"
        if [[ "$VERBOSE" == true ]]; then
            print_info "Updated $setting = $value in $ini_file"
        fi
    else
        # Setting doesn't exist, add it
        echo "$setting = $value" | sudo tee -a "$ini_file" > /dev/null
        if [[ "$VERBOSE" == true ]]; then
            print_info "Added $setting = $value to $ini_file"
        fi
    fi
}

# Function to configure PHP for specific version and SAPI
configure_php_version() {
    local version="$1"
    local sapi="$2"  # cli, fpm, apache2
    
    local ini_file="/etc/php/$version/$sapi/php.ini"
    
    if [[ ! -f "$ini_file" ]]; then
        print_warning "PHP $version $sapi configuration not found: $ini_file"
        return 1
    fi
    
    print_info "Configuring PHP $version ($sapi)..."
    
    # Create backup
    backup_php_ini "$ini_file"
    
    # Apply all configured settings
    for setting in "${!PHP_CONFIG[@]}"; do
        update_php_setting "$ini_file" "$setting" "${PHP_CONFIG[$setting]}"
    done
    
    print_success "✓ PHP $version ($sapi) configuration updated"
}

# Function to configure PHP after installation
configure_php_installation() {
    if [[ "$CONFIGURE_PHP" == false ]]; then
        print_info "Skipping PHP configuration as requested"
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would configure PHP versions: ${PHP_VERSIONS[*]}"
        return 0
    fi
    
    print_info "Configuring PHP versions ${PHP_VERSIONS[*]} with optimized settings..."
    
    # Apply environment-specific settings
    if [[ "$APPLY_PRODUCTION_CONFIG" == true ]]; then
        apply_production_settings
    elif [[ "$APPLY_DEVELOPMENT_CONFIG" == true ]]; then
        apply_development_settings
    fi
    
    # Configure CLI for all versions
    for version in "${PHP_VERSIONS[@]}"; do
        if [[ "$INSTALL_CLI" == true ]]; then
            configure_php_version "$version" "cli"
        fi

        # Configure FPM for this version if available
        if [[ "$INSTALL_FPM" == true ]] && systemctl list-unit-files | grep -q "php${version}-fpm.service"; then
            configure_php_version "$version" "fpm"

            # Restart FPM service to apply new configuration
            execute_command "sudo systemctl restart php${version}-fpm" "Restarting PHP $version FPM"
        fi
    done

    # Configure Apache module (only for default version)
    if [[ "$INSTALL_APACHE_MOD" == true ]]; then
        configure_php_version "$DEFAULT_VERSION" "apache2"

        # Reload Apache to apply new configuration
        execute_command "sudo systemctl reload apache2" "Reloading Apache configuration"
    fi
    
    print_success "✓ PHP configuration completed successfully!"
}

# Function to display installation summary
show_summary() {
    echo
    print_success "Installation Summary:"
    echo "  PHP Versions: ${PHP_VERSIONS[*]}"
    echo "  Default Version: $DEFAULT_VERSION"
    echo "  PHP CLI: $([ "$INSTALL_CLI" == true ] && echo "✓ Installed" || echo "✗ Skipped")"
    echo "  PHP FPM: $([ "$INSTALL_FPM" == true ] && echo "✓ Installed" || echo "✗ Skipped")"
    echo "  Extensions: $([ "$INSTALL_EXTENSIONS" == true ] && echo "✓ Installed" || echo "✗ Skipped")"
    echo "  Apache2: $([ "$INSTALL_APACHE_MOD" == true ] && echo "✓ Installed" || echo "✗ Skipped")"
    echo "  PHP Configuration: $([ "$CONFIGURE_PHP" == true ] && echo "✓ Applied" || echo "✗ Skipped")"
    
    if [[ "$CONFIGURE_PHP" == true ]]; then
        echo "  Environment: $([ "$APPLY_PRODUCTION_CONFIG" == true ] && echo "Production" || [ "$APPLY_DEVELOPMENT_CONFIG" == true ] && echo "Development" || echo "Default")"
        echo "  Memory Limit: ${PHP_CONFIG["memory_limit"]}"
        echo "  Upload Size: ${PHP_CONFIG["upload_max_filesize"]}"
        echo "  Max Input Vars: ${PHP_CONFIG["max_input_vars"]}"
    fi
    
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
    
    if [[ "$CONFIGURE_PHP" == true ]]; then
        cat << EOF
  • PHP has been configured with optimized settings for your environment
  • Configuration backups created with timestamps for easy rollback
  • Key settings applied:
    - Memory limit: ${PHP_CONFIG["memory_limit"]}
    - Upload max filesize: ${PHP_CONFIG["upload_max_filesize"]}
    - Max execution time: ${PHP_CONFIG["max_execution_time"]}
    - Max input vars: ${PHP_CONFIG["max_input_vars"]}
    - OPcache: $([ "${PHP_CONFIG["opcache.enable"]}" == "1" ] && echo "Enabled" || echo "Disabled")
    
EOF
    fi
    
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
  • To reconfigure PHP settings, run the configuration script:
    ${SCRIPT_DIR}/configure.sh --version ${SELECTED_VERSION}
    
  • To install additional extensions:
    sudo apt install php${SELECTED_VERSION}-[extension-name]
    
  • Common additional extensions (install manually if needed):
    sudo apt install php${SELECTED_VERSION}-gmp php${SELECTED_VERSION}-xdebug
    
  • To switch between PHP versions (if multiple installed):
    sudo update-alternatives --config php
    
  • Service management commands:
    sudo systemctl start|stop|restart|status php${SELECTED_VERSION}-fpm
    
  • Check current PHP configuration:
    ${SCRIPT_DIR}/debug_version.sh --version ${SELECTED_VERSION}
    
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
            --no-configure)
                CONFIGURE_PHP=false
                shift
                ;;
            --production)
                APPLY_PRODUCTION_CONFIG=true
                shift
                ;;
            --development)
                APPLY_DEVELOPMENT_CONFIG=true
                shift
                ;;
            --memory-limit)
                if [[ -n "${2:-}" ]]; then
                    PHP_CONFIG["memory_limit"]="$2"
                    shift 2
                else
                    print_error "--memory-limit requires a value"
                    exit 1
                fi
                ;;
            --upload-size)
                if [[ -n "${2:-}" ]]; then
                    PHP_CONFIG["upload_max_filesize"]="$2"
                    PHP_CONFIG["post_max_size"]="$2"
                    shift 2
                else
                    print_error "--upload-size requires a value"
                    exit 1
                fi
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
    
    # Auto-detect and configure PHP versions
    detect_php_versions
    configure_installation
    
    # Confirmation
    echo
    print_info "Installation Plan:"
    echo "  PHP Versions: ${PHP_VERSIONS[*]}"
    echo "  Default Version: $DEFAULT_VERSION"
    echo "  PHP CLI: Yes (auto-install)"
    echo "  PHP FPM: $([ "$INSTALL_FPM" == true ] && echo "Yes (auto-install)" || echo "Will check availability")"
    echo "  Extensions: $([ "$INSTALL_EXTENSIONS" == true ] && echo "Yes" || echo "No")"
    echo "  Apache2: $([ "$INSTALL_APACHE_MOD" == true ] && echo "Yes" || echo "No")"
    echo "  PHP Configuration: $([ "$CONFIGURE_PHP" == true ] && echo "Yes" || echo "No")"
    
    if [[ "$CONFIGURE_PHP" == true ]]; then
        echo "  Environment: $([ "$APPLY_PRODUCTION_CONFIG" == true ] && echo "Production" || [ "$APPLY_DEVELOPMENT_CONFIG" == true ] && echo "Development" || echo "Default")"
        echo "  Memory Limit: ${PHP_CONFIG["memory_limit"]}"
        echo "  Upload Size: ${PHP_CONFIG["upload_max_filesize"]}"
    fi
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
    
    # Configure PHP after installation
    configure_php_installation
    
    # Post-installation
    show_summary
    show_post_install_notes
    
    echo
    print_success "PHP installation and configuration completed successfully!"
}

# Run main function
main "$@"