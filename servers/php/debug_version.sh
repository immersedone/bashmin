#!/bin/bash
#
# Script: debug_version.sh
# Description: Debug and display PHP configuration across all installed versions
# Usage: ./debug_version.sh [OPTIONS]
#

set -euo pipefail

# Get script directory and source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$BASE_DIR/_helpers/common.sh"

# Global variables
VERBOSE=false
SPECIFIC_VERSION=""
CHECK_EXTENSIONS=false
SHOW_INI_FILES=false
CHECK_SERVICES=false

# Function to show help
show_help() {
    cat << EOF
PHP Debug and Version Information Script

Usage: $0 [OPTIONS]

Options:
    -h, --help               Show this help message
    -v, --verbose            Show detailed information
    --version VERSION        Show info for specific PHP version only
    --extensions             Show loaded extensions
    --ini-files              Show php.ini file locations and contents
    --services               Check PHP service status
    --all                    Show all available information

Examples:
    $0                       Show basic PHP version info
    $0 --version 8.3 --verbose
    $0 --extensions --services
    $0 --all                 Comprehensive debug output

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
            --version)
                SPECIFIC_VERSION="$2"
                shift 2
                ;;
            --extensions)
                CHECK_EXTENSIONS=true
                shift
                ;;
            --ini-files)
                SHOW_INI_FILES=true
                shift
                ;;
            --services)
                CHECK_SERVICES=true
                shift
                ;;
            --all)
                VERBOSE=true
                CHECK_EXTENSIONS=true
                SHOW_INI_FILES=true
                CHECK_SERVICES=true
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

# Function to detect installed PHP versions
detect_php_versions() {
    local versions=()
    
    # Check for PHP versions in common locations
    for version_dir in /etc/php/*/; do
        if [[ -d "$version_dir" ]]; then
            local version=$(basename "$version_dir")
            # Validate it's a proper PHP version format
            if [[ $version =~ ^[0-9]+\.[0-9]+$ ]]; then
                versions+=("$version")
            fi
        fi
    done
    
    printf '%s\n' "${versions[@]}" | sort -V
}

# Function to show PHP version information
show_php_version_info() {
    local version="$1"
    
    print_info "PHP $version Information"
    echo "========================"
    
    # Check if PHP CLI is available for this version
    if command -v "php$version" &> /dev/null; then
        echo "CLI Version: $(php$version --version | head -n1)"
        echo "SAPI: $(php$version -r 'echo php_sapi_name();')"
        echo "Loaded Configuration File: $(php$version --ini | grep "Loaded Configuration File" | cut -d: -f2- | xargs)"
        echo "Scan for additional .ini files in: $(php$version --ini | grep "Scan this dir" | cut -d: -f2- | xargs)"
        
        if [[ "$VERBOSE" == true ]]; then
            echo ""
            echo "Key Settings:"
            echo "-------------"
            php$version -r "
                \$settings = [
                    'memory_limit', 'upload_max_filesize', 'post_max_size',
                    'max_execution_time', 'max_input_vars', 'max_file_uploads',
                    'date.timezone', 'error_reporting', 'display_errors',
                    'log_errors', 'opcache.enable'
                ];
                foreach (\$settings as \$setting) {
                    printf('%-25s = %s\n', \$setting, ini_get(\$setting));
                }
            "
        fi
        
        if [[ "$CHECK_EXTENSIONS" == true ]]; then
            echo ""
            echo "Loaded Extensions:"
            echo "------------------"
            php$version -m | column -c 80
        fi
    else
        print_warning "PHP $version CLI not found in PATH"
    fi
    
    echo ""
}

# Function to show ini file information
show_ini_files() {
    local version="$1"
    
    print_info "PHP $version Configuration Files"
    echo "================================="
    
    for sapi in cli fpm apache2; do
        local ini_file="/etc/php/$version/$sapi/php.ini"
        if [[ -f "$ini_file" ]]; then
            echo "$sapi: $ini_file"
            if [[ "$VERBOSE" == true ]]; then
                echo "  Last modified: $(stat -c %y "$ini_file" 2>/dev/null || echo "Unknown")"
                echo "  Size: $(stat -c %s "$ini_file" 2>/dev/null || echo "Unknown") bytes"
                
                # Show recent modifications (last 10 lines with timestamps)
                echo "  Recent configuration lines (non-comments):"
                grep -v "^;" "$ini_file" | grep -v "^$" | tail -5 | sed 's/^/    /'
            fi
        else
            echo "$sapi: $ini_file (not found)"
        fi
    done
    echo ""
}

# Function to check PHP service status
check_php_services() {
    local version="$1"
    
    print_info "PHP $version Service Status"
    echo "==========================="
    
    # Check PHP-FPM
    local fpm_service="php$version-fpm"
    if systemctl list-units --full -all | grep -Fq "$fpm_service.service"; then
        if systemctl is-active --quiet "$fpm_service"; then
            print_success "✓ $fpm_service is running"
            if [[ "$VERBOSE" == true ]]; then
                echo "  Status: $(systemctl is-active "$fpm_service")"
                echo "  Enabled: $(systemctl is-enabled "$fpm_service" 2>/dev/null || echo "unknown")"
                echo "  Main PID: $(systemctl show -p MainPID --value "$fpm_service" 2>/dev/null || echo "unknown")"
                
                # Show pool configuration
                local pool_dir="/etc/php/$version/fpm/pool.d"
                if [[ -d "$pool_dir" ]]; then
                    echo "  Active pools:"
                    find "$pool_dir" -name "*.conf" -exec basename {} .conf \; | sed 's/^/    /'
                fi
            fi
        else
            print_warning "✗ $fpm_service is not running"
        fi
    else
        print_info "- $fpm_service service not found"
    fi
    
    # Check if Apache module is loaded
    if command -v apache2ctl &> /dev/null && apache2ctl -M 2>/dev/null | grep -q "php.*$version"; then
        print_success "✓ PHP $version Apache module is loaded"
        if [[ "$VERBOSE" == true ]]; then
            apache2ctl -M 2>/dev/null | grep "php.*$version" | sed 's/^/  /'
        fi
    else
        print_info "- PHP $version Apache module not detected"
    fi
    
    echo ""
}

# Function to check web server configuration
check_webserver_config() {
    print_info "Web Server Configuration"
    echo "========================"
    
    # Check Apache
    if systemctl is-active --quiet apache2 2>/dev/null; then
        print_success "✓ Apache is running"
        if [[ "$VERBOSE" == true ]]; then
            echo "  Version: $(apache2 -v 2>/dev/null | head -n1 || echo "Unknown")"
            echo "  Configuration test: $(apache2ctl configtest 2>&1 | head -n1)"
        fi
    else
        print_info "- Apache is not running"
    fi
    
    # Check Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        print_success "✓ Nginx is running"
        if [[ "$VERBOSE" == true ]]; then
            echo "  Version: $(nginx -v 2>&1 | head -n1 || echo "Unknown")"
            echo "  Configuration test: $(nginx -t 2>&1 | head -n1)"
        fi
    else
        print_info "- Nginx is not running"
    fi
    
    echo ""
}

# Function to show system information
show_system_info() {
    print_info "System Information"
    echo "=================="
    
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Uptime: $(uptime -p)"
    
    if [[ "$VERBOSE" == true ]]; then
        echo "Memory: $(free -h | awk 'NR==2{printf "%.1fG used / %.1fG total (%.1f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')"
        echo "Disk Usage: $(df -h / | awk 'NR==2{printf "%s used / %s total (%s)", $3, $2, $5}')"
    fi
    
    echo ""
}

# Function to run quick PHP test
run_php_test() {
    local version="$1"
    
    if command -v "php$version" &> /dev/null; then
        local test_result
        test_result=$(php$version -r "echo 'PHP test successful - version: ' . phpversion();" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            print_success "✓ PHP $version test: $test_result"
        else
            print_error "✗ PHP $version test failed: $test_result"
        fi
    fi
}

# Main function
main() {
    print_info "PHP Debug Information"
    echo "====================="
    echo ""
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Get PHP versions to check
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
        print_error "No PHP installations found"
        exit 1
    fi
    
    # Show system information
    show_system_info
    
    # Check web server configuration
    if [[ "$CHECK_SERVICES" == true ]]; then
        check_webserver_config
    fi
    
    # Process each PHP version
    for version in "${php_versions[@]}"; do
        show_php_version_info "$version"
        
        if [[ "$SHOW_INI_FILES" == true ]]; then
            show_ini_files "$version"
        fi
        
        if [[ "$CHECK_SERVICES" == true ]]; then
            check_php_services "$version"
        fi
        
        # Run quick test
        run_php_test "$version"
        
        echo ""
    done
    
    print_success "Debug information collection completed"
    
    # Show helpful tips
    echo ""
    print_info "Helpful commands:"
    echo "  php$version --ini                    # Show configuration file info"
    echo "  php$version -m                      # List loaded modules"
    echo "  php$version -i | grep setting       # Search for specific setting"
    echo "  systemctl status php$version-fpm    # Check FPM service status"
    echo "  tail -f /var/log/php$version-fpm.log # Monitor FPM logs"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
