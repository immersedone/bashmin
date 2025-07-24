#!/bin/bash
#
# Script: configure.sh
# Description: Configure PHP settings across all installed PHP versions
# Usage: ./configure.sh [OPTIONS]
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
BACKUP_EXISTING=true
SPECIFIC_VERSION=""
APPLY_TO_CLI=true
APPLY_TO_FPM=true
APPLY_TO_APACHE=true

# Default PHP configuration values
declare -A PHP_CONFIG=(
    ["memory_limit"]="256M"
    ["upload_max_filesize"]="128M"
    ["post_max_size"]="128M"
    ["max_execution_time"]="300"
    ["max_input_time"]="300"
    ["max_input_vars"]="3000"
    ["max_file_uploads"]="20"
    ["default_socket_timeout"]="60"
    ["auto_prepend_file"]=""
    ["auto_append_file"]=""
    ["precision"]="14"
    ["output_buffering"]="4096"
    ["zlib.output_compression"]="Off"
    ["implicit_flush"]="Off"
    ["unserialize_callback_func"]=""
    ["serialize_precision"]="-1"
    ["disable_functions"]=""
    ["disable_classes"]=""
    ["expose_php"]="Off"
    ["max_input_nesting_level"]="64"
    ["request_order"]="GP"
    ["variables_order"]="GPCS"
    ["auto_globals_jit"]="On"
    ["short_open_tag"]="Off"
    ["asp_tags"]="Off"
    ["log_errors"]="On"
    ["error_log"]="syslog"
    ["error_reporting"]="E_ALL & ~E_DEPRECATED & ~E_STRICT"
    ["display_errors"]="Off"
    ["display_startup_errors"]="Off"
    ["log_errors_max_len"]="1024"
    ["ignore_repeated_errors"]="Off"
    ["track_errors"]="Off"
    ["html_errors"]="On"
    ["date.timezone"]="UTC"
    ["session.save_handler"]="files"
    ["session.save_path"]="/var/lib/php/sessions"
    ["session.use_strict_mode"]="1"
    ["session.use_cookies"]="1"
    ["session.use_only_cookies"]="1"
    ["session.name"]="PHPSESSID"
    ["session.auto_start"]="0"
    ["session.cookie_lifetime"]="0"
    ["session.cookie_path"]="/"
    ["session.cookie_domain"]=""
    ["session.cookie_httponly"]="1"
    ["session.cookie_secure"]="0"
    ["session.gc_probability"]="1"
    ["session.gc_divisor"]="1000"
    ["session.gc_maxlifetime"]="1440"
    ["opcache.enable"]="1"
    ["opcache.enable_cli"]="0"
    ["opcache.memory_consumption"]="128"
    ["opcache.interned_strings_buffer"]="8"
    ["opcache.max_accelerated_files"]="4000"
    ["opcache.revalidate_freq"]="2"
    ["opcache.fast_shutdown"]="1"
    ["opcache.enable_file_override"]="0"
)

# Function to show help
show_help() {
    cat << EOF
PHP Configuration Script for Ubuntu-based Systems

Usage: $0 [OPTIONS]

Options:
    -h, --help                    Show this help message
    -v, --verbose                 Enable verbose output
    --dry-run                     Test mode, show changes without applying
    --silent                      Silent mode, use defaults without prompts
    --no-backup                   Don't create backup files
    --version VERSION             Configure specific PHP version only (e.g., 8.3)
    --cli-only                    Apply changes to CLI configuration only
    --fpm-only                    Apply changes to FPM configuration only
    --apache-only                 Apply changes to Apache module only
    
Configuration Options:
    --memory-limit SIZE           Set memory_limit (default: 512M)
    --upload-size SIZE            Set upload_max_filesize and post_max_size (default: 64M)
    --max-execution-time SEC      Set max_execution_time (default: 300)
    --max-input-vars NUM          Set max_input_vars (default: 3000)
    --timezone TZ                 Set date.timezone (default: UTC)
    --enable-opcache              Enable OPcache optimization
    --disable-opcache             Disable OPcache optimization
    --production                  Apply production-ready security settings
    --development                 Apply development-friendly settings

Examples:
    $0                            Interactive configuration
    $0 --silent                   Apply default settings to all PHP versions
    $0 --version 8.3 --memory-limit 1G --upload-size 128M
    $0 --fpm-only --production    Apply production settings to FPM only
    $0 --dry-run --verbose        Preview changes without applying

EOF
}

# Function to parse command line arguments
parse_arguments() {
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
            --no-backup)
                BACKUP_EXISTING=false
                shift
                ;;
            --version)
                SPECIFIC_VERSION="$2"
                shift 2
                ;;
            --cli-only)
                APPLY_TO_CLI=true
                APPLY_TO_FPM=false
                APPLY_TO_APACHE=false
                shift
                ;;
            --fpm-only)
                APPLY_TO_CLI=false
                APPLY_TO_FPM=true
                APPLY_TO_APACHE=false
                shift
                ;;
            --apache-only)
                APPLY_TO_CLI=false
                APPLY_TO_FPM=false
                APPLY_TO_APACHE=true
                shift
                ;;
            --memory-limit)
                PHP_CONFIG["memory_limit"]="$2"
                shift 2
                ;;
            --upload-size)
                PHP_CONFIG["upload_max_filesize"]="$2"
                PHP_CONFIG["post_max_size"]="$2"
                shift 2
                ;;
            --max-execution-time)
                PHP_CONFIG["max_execution_time"]="$2"
                shift 2
                ;;
            --max-input-vars)
                PHP_CONFIG["max_input_vars"]="$2"
                shift 2
                ;;
            --timezone)
                PHP_CONFIG["date.timezone"]="$2"
                shift 2
                ;;
            --enable-opcache)
                PHP_CONFIG["opcache.enable"]="1"
                PHP_CONFIG["opcache.enable_cli"]="1"
                shift
                ;;
            --disable-opcache)
                PHP_CONFIG["opcache.enable"]="0"
                PHP_CONFIG["opcache.enable_cli"]="0"
                shift
                ;;
            --production)
                apply_production_settings
                shift
                ;;
            --development)
                apply_development_settings
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
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

# Function to detect installed PHP versions
detect_php_versions() {
    local versions=()
    
    # Check for PHP versions in common locations
    for version_dir in /etc/php/*/; do
        if [[ -d "$version_dir" ]]; then
            local version=$(basename "$version_dir")
            # Validate it's a proper PHP version format (e.g., 8.3)
            if [[ $version =~ ^[0-9]+\.[0-9]+$ ]]; then
                versions+=("$version")
            fi
        fi
    done
    
    if [[ ${#versions[@]} -eq 0 ]]; then
        print_error "No PHP installations found in /etc/php/"
        exit 1
    fi
    
    printf '%s\n' "${versions[@]}" | sort -V
}

# Function to backup php.ini file
backup_php_ini() {
    local ini_file="$1"
    local backup_file="${ini_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ "$BACKUP_EXISTING" == true && -f "$ini_file" ]]; then
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
    
    # Create backup if enabled
    backup_php_ini "$ini_file"
    
    # Apply all configured settings
    for setting in "${!PHP_CONFIG[@]}"; do
        update_php_setting "$ini_file" "$setting" "${PHP_CONFIG[$setting]}"
    done
    
    print_success "✓ PHP $version ($sapi) configuration updated"
}

# Function to restart PHP services
restart_php_services() {
    local version="$1"
    local dry_run="${DRY_RUN:-false}"
    
    if [[ "$dry_run" == true ]]; then
        print_info "[DRY-RUN] Would restart PHP $version services"
        return 0
    fi
    
    # Restart PHP-FPM if it exists and is enabled
    if [[ "$APPLY_TO_FPM" == true ]] && systemctl list-units --full -all | grep -Fq "php$version-fpm.service"; then
        if systemctl is-enabled "php$version-fpm" &>/dev/null; then
            execute_command "sudo systemctl restart php$version-fpm" "Restarting PHP $version FPM"
        fi
    fi
    
    # Restart Apache if it's running and we modified Apache module
    if [[ "$APPLY_TO_APACHE" == true ]] && systemctl is-active --quiet apache2; then
        execute_command "sudo systemctl reload apache2" "Reloading Apache configuration"
    fi
    
    # Restart Nginx if it's running (for FPM)
    if [[ "$APPLY_TO_FPM" == true ]] && systemctl is-active --quiet nginx; then
        execute_command "sudo systemctl reload nginx" "Reloading Nginx configuration"
    fi
}

# Function to show configuration summary
show_configuration_summary() {
    print_info "Configuration Summary:"
    echo "===================="
    
    for setting in "${!PHP_CONFIG[@]}"; do
        printf "%-30s = %s\n" "$setting" "${PHP_CONFIG[$setting]}"
    done | sort
    
    echo ""
    print_info "Target Applications:"
    [[ "$APPLY_TO_CLI" == true ]] && echo "  ✓ CLI"
    [[ "$APPLY_TO_FPM" == true ]] && echo "  ✓ FPM"
    [[ "$APPLY_TO_APACHE" == true ]] && echo "  ✓ Apache Module"
    echo ""
}

# Function to prompt for configuration values
prompt_for_configuration() {
    if [[ "$SILENT" == true ]]; then
        return 0
    fi
    
    print_info "Interactive PHP Configuration"
    echo "=============================="
    echo ""
    
    # Memory settings
    read -p "Memory limit [${PHP_CONFIG["memory_limit"]}]: " input
    [[ -n "$input" ]] && PHP_CONFIG["memory_limit"]="$input"
    
    read -p "Upload max filesize [${PHP_CONFIG["upload_max_filesize"]}]: " input
    [[ -n "$input" ]] && PHP_CONFIG["upload_max_filesize"]="$input" && PHP_CONFIG["post_max_size"]="$input"
    
    read -p "Max execution time [${PHP_CONFIG["max_execution_time"]}]: " input
    [[ -n "$input" ]] && PHP_CONFIG["max_execution_time"]="$input"
    
    read -p "Max input vars [${PHP_CONFIG["max_input_vars"]}]: " input
    [[ -n "$input" ]] && PHP_CONFIG["max_input_vars"]="$input"
    
    read -p "Timezone [${PHP_CONFIG["date.timezone"]}]: " input
    [[ -n "$input" ]] && PHP_CONFIG["date.timezone"]="$input"
    
    # OPcache settings
    if confirm_action "Enable OPcache optimization?" "Y"; then
        PHP_CONFIG["opcache.enable"]="1"
        PHP_CONFIG["opcache.enable_cli"]="1"
    else
        PHP_CONFIG["opcache.enable"]="0"
        PHP_CONFIG["opcache.enable_cli"]="0"
    fi
    
    # Environment type
    echo ""
    print_info "Environment Configuration:"
    PS3="Select environment type: "
    select env_type in "Production" "Development" "Custom" "Skip"; do
        case $env_type in
            "Production")
                apply_production_settings
                break
                ;;
            "Development")
                apply_development_settings
                break
                ;;
            "Custom"|"Skip")
                break
                ;;
            *)
                print_error "Invalid selection"
                ;;
        esac
    done
    
    echo ""
}

# Function to validate configuration values
validate_configuration() {
    local errors=0
    
    # Validate memory limit format
    if [[ ! "${PHP_CONFIG["memory_limit"]}" =~ ^[0-9]+[KMG]?$ ]]; then
        print_error "Invalid memory_limit format: ${PHP_CONFIG["memory_limit"]}"
        ((errors++))
    fi
    
    # Validate upload size format
    if [[ ! "${PHP_CONFIG["upload_max_filesize"]}" =~ ^[0-9]+[KMG]?$ ]]; then
        print_error "Invalid upload_max_filesize format: ${PHP_CONFIG["upload_max_filesize"]}"
        ((errors++))
    fi
    
    # Validate numeric values
    for setting in "max_execution_time" "max_input_vars" "max_file_uploads"; do
        if [[ ! "${PHP_CONFIG[$setting]}" =~ ^[0-9]+$ ]]; then
            print_error "Invalid $setting: ${PHP_CONFIG[$setting]} (must be numeric)"
            ((errors++))
        fi
    done
    
    # Validate timezone
    if [[ -n "${PHP_CONFIG["date.timezone"]}" ]] && ! timedatectl list-timezones | grep -q "^${PHP_CONFIG["date.timezone"]}$"; then
        print_warning "Timezone '${PHP_CONFIG["date.timezone"]}' may not be valid"
    fi
    
    return $errors
}

# Main function
main() {
    print_info "PHP Configuration Script"
    echo "========================"
    echo ""
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check system requirements
    check_ubuntu_system
    
    # Detect PHP versions
    local php_versions
    if [[ -n "$SPECIFIC_VERSION" ]]; then
        php_versions=("$SPECIFIC_VERSION")
        if [[ ! -d "/etc/php/$SPECIFIC_VERSION" ]]; then
            print_error "PHP version $SPECIFIC_VERSION not found"
            exit 1
        fi
    else
        readarray -t php_versions < <(detect_php_versions)
    fi
    
    if [[ ${#php_versions[@]} -eq 0 ]]; then
        print_error "No PHP versions found to configure"
        exit 1
    fi
    
    print_info "Found PHP versions: ${php_versions[*]}"
    echo ""
    
    # Interactive configuration if not in silent mode
    prompt_for_configuration
    
    # Validate configuration
    if ! validate_configuration; then
        print_error "Configuration validation failed"
        exit 1
    fi
    
    # Show configuration summary
    show_configuration_summary
    
    # Confirm before applying
    if [[ "$SILENT" == false && "$DRY_RUN" == false ]]; then
        echo ""
        if ! confirm_action "Apply these configurations?" "Y"; then
            print_info "Configuration cancelled"
            exit 0
        fi
    fi
    
    echo ""
    print_info "Applying PHP configurations..."
    
    # Configure each PHP version
    for version in "${php_versions[@]}"; do
        print_info "Processing PHP $version..."
        
        # Configure CLI
        if [[ "$APPLY_TO_CLI" == true ]]; then
            configure_php_version "$version" "cli"
        fi
        
        # Configure FPM
        if [[ "$APPLY_TO_FPM" == true ]]; then
            configure_php_version "$version" "fpm"
        fi
        
        # Configure Apache module
        if [[ "$APPLY_TO_APACHE" == true ]]; then
            configure_php_version "$version" "apache2"
        fi
        
        # Restart services for this version
        restart_php_services "$version"
        
        echo ""
    done
    
    print_success "✓ PHP configuration completed successfully!"
    
    # Show next steps
    echo ""
    print_info "Next steps:"
    echo "  - Test your applications to ensure they work with the new settings"
    echo "  - Monitor error logs for any issues: /var/log/php*.log"
    echo "  - Use 'php -m' to verify loaded modules"
    echo "  - Check phpinfo() output in your web applications"
    
    if [[ "$BACKUP_EXISTING" == true ]]; then
        echo "  - Backup files created with timestamp for easy rollback"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi