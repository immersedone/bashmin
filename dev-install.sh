#!/bin/bash
#
# File: dev-install.sh
# Description: bashmin Suite Development Environment Installer
# Author: bashmin Security Team
# Version: 1.0.0
# Usage: ./dev-install.sh [options]
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/_helpers/common.sh"
source "${SCRIPT_DIR}/_helpers/cli.sh"
source "${SCRIPT_DIR}/_helpers/system.sh"

# Default configuration
INSTALLATION_MODE="interactive"  # interactive, quiet, auto
DRY_RUN=false
VERBOSE=false
LOG_FILE="/var/log/bashmin/dev-install-$(date +%Y%m%d_%H%M%S).log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Development modules in order from dev-install.md
DEV_MODULES=(
    "dev-nvm"           # nvm + global packages
    "aliases"           # aliases
    "server-nginx"      # nginx
    "server-mariadb"    # mariadb
    "server-frankenphp" # frankenphp
    "server-apache2"    # apache2
    "server-php"        # php
    "software-phpmyadmin" # phpmyadmin
    "server-redis"      # redis
    "sshd"              # sshd
)

# Module descriptions
declare -A MODULE_DESCRIPTIONS=(
    ["dev-nvm"]="Node Version Manager with global packages"
    ["aliases"]="Bash aliases and shortcuts"
    ["server-nginx"]="Nginx Web Server"
    ["server-mariadb"]="MariaDB Database Server"
    ["server-frankenphp"]="FrankenPHP Modern Server"
    ["server-apache2"]="Apache2 Web Server"
    ["server-php"]="PHP Configuration and Optimization"
    ["software-phpmyadmin"]="phpMyAdmin Database Interface"
    ["server-redis"]="Redis Cache Server"
    ["sshd"]="SSH Daemon Configuration"
)

# Function to show usage information
show_usage() {
    cat << 'EOF'
bashmin Suite Development Environment Installer

USAGE:
    ./dev-install.sh [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -i, --interactive       Interactive mode (default)
    -q, --quiet             Quiet mode - minimal output
    -a, --auto              Automatic mode - install all modules
    -d, --dry-run           Show what would be installed without executing
    -v, --verbose           Enable verbose output
    -l, --log FILE          Custom log file location
    --list-modules          List all development modules

DESCRIPTION:
    This script installs the bashmin development environment in the correct
    order as specified in dev-install.md:

    1. nvm + global packages
    2. aliases
    3. nginx
    4. mariadb
    5. frankenphp
    6. apache2
    7. php
    8. phpmyadmin
    9. redis
    10. sshd

EXAMPLES:
    # Interactive installation
    sudo ./dev-install.sh

    # Automatic installation (all modules)
    sudo ./dev-install.sh --auto

    # Dry run to see what would be installed
    sudo ./dev-install.sh --dry-run

    # Quiet installation with custom log
    sudo ./dev-install.sh --quiet --log /tmp/dev-install.log

EOF
}

# Function to list development modules
list_modules() {
    echo "Development Environment Modules:"
    echo "==============================="
    echo

    local i=1
    for module in "${DEV_MODULES[@]}"; do
        printf "%2d) %-20s %s\n" "$i" "$module" "${MODULE_DESCRIPTIONS[$module]}"
        ((i++))
    done
    echo
}

# Function to get module install script path
get_module_script() {
    local module="$1"

    case "$module" in
        "dev-"*)
            local dev_component="${module#dev-}"
            if [[ "$dev_component" == "nvm" ]]; then
                echo "${SCRIPT_DIR}/software/nvm/install.sh"
            else
                echo "${SCRIPT_DIR}/development/${dev_component}/install.sh"
            fi
            ;;
        "server-"*)
            local server_component="${module#server-}"
            echo "${SCRIPT_DIR}/servers/${server_component}/install.sh"
            ;;
        "software-"*)
            local software_component="${module#software-}"
            echo "${SCRIPT_DIR}/software/${software_component}/install.sh"
            ;;
        "aliases") echo "${SCRIPT_DIR}/aliases/install.sh" ;;
        "sshd") echo "${SCRIPT_DIR}/sshd/configure.sh" ;;
        *) return 1 ;;
    esac
}

# Function to check if module is available
is_module_available() {
    local module="$1"
    local script_path=$(get_module_script "$module")
    [[ -f "$script_path" ]]
}

# Function to show main menu
show_main_menu() {
    clear
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║              bashmin Development Environment                 ║
║                     Custom Installation                     ║
╚══════════════════════════════════════════════════════════════╝

Development environment installation in the correct order:

EOF

    echo -e "${BLUE}Installation Options:${NC}"
    echo "1) Install All Development Modules (Recommended)"
    echo "2) Select Individual Modules"
    echo "3) Show Module Information"
    echo "4) View Installation Log"
    echo "5) Exit"
    echo
}

# Function to show module selection menu
show_module_selection() {
    clear
    echo -e "${BLUE}Development Module Selection:${NC}"
    echo "============================="
    echo

    local i=1
    for module in "${DEV_MODULES[@]}"; do
        printf "%2d) %-20s %s\n" "$i" "$module" "${MODULE_DESCRIPTIONS[$module]}"
        ((i++))
    done
    echo
    echo "11) Install Selected Modules"
    echo "0) Back to Main Menu"
    echo
}

# Function to run interactive mode
run_interactive_mode() {
    local selected_modules=()

    while true; do
        show_main_menu
        read -p "Select an option (1-5): " choice

        case $choice in
            1)
                selected_modules=("${DEV_MODULES[@]}")
                install_modules "${selected_modules[@]}"
                ;;
            2)
                run_module_selection selected_modules
                ;;
            3)
                show_module_info
                ;;
            4)
                show_install_log
                ;;
            5)
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-5."
                sleep 1
                ;;
        esac
    done
}

# Function to run module selection
run_module_selection() {
    local -n selected_ref=$1
    local available_modules=()

    # Check which modules are available
    for module in "${DEV_MODULES[@]}"; do
        if is_module_available "$module"; then
            available_modules+=("$module")
        else
            print_warning "Module script not found for: $module"
        fi
    done

    while true; do
        show_module_selection
        read -p "Select modules (comma-separated numbers, 11 to install, 0 to go back): " input

        case $input in
            0) return ;;
            11)
                if [[ ${#selected_ref[@]} -eq 0 ]]; then
                    print_error "No modules selected."
                    sleep 1
                    continue
                fi
                install_modules "${selected_ref[@]}"
                return
                ;;
            *)
                # Parse comma-separated numbers
                IFS=',' read -ra selections <<< "$input"
                selected_ref=()
                local valid=true

                for selection in "${selections[@]}"; do
                    selection=$(echo "$selection" | xargs) # trim whitespace
                    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 && $selection -le ${#DEV_MODULES[@]} ]]; then
                        selected_ref+=("${DEV_MODULES[$((selection-1))]}")
                    else
                        print_error "Invalid selection: $selection"
                        valid=false
                        break
                    fi
                done

                if [[ "$valid" == true ]]; then
                    print_success "Selected ${#selected_ref[@]} modules: ${selected_ref[*]}"
                fi
                sleep 1
                ;;
        esac
    done
}

# Function to show module information
show_module_info() {
    clear
    list_modules
    echo
    echo "Installation Order (from dev-install.md):"
    echo "========================================="
    local i=1
    for module in "${DEV_MODULES[@]}"; do
        local available=""
        if is_module_available "$module"; then
            available="${GREEN}[AVAILABLE]${NC}"
        else
            available="${RED}[MISSING]${NC}"
        fi
        printf "%2d. %-20s %s %s\n" "$i" "$module" "$available" "${MODULE_DESCRIPTIONS[$module]}"
        ((i++))
    done
    echo
    echo "Press Enter to continue..."
    read
}

# Function to show installation log
show_install_log() {
    clear
    echo -e "${BLUE}Installation Log:${NC}"
    echo "================"
    echo

    if [[ -f "$LOG_FILE" ]]; then
        tail -n 50 "$LOG_FILE"
    else
        echo "No installation log found."
    fi
    echo
    echo "Press Enter to continue..."
    read
}

# Function to install modules
install_modules() {
    local modules=("$@")

    if [[ ${#modules[@]} -eq 0 ]]; then
        print_error "No modules specified for installation."
        return 1
    fi

    clear
    echo -e "${BLUE}Development Environment Installation:${NC}"
    echo "===================================="
    echo
    echo "The following modules will be installed in order:"
    local i=1
    for module in "${modules[@]}"; do
        printf "%2d. %-20s %s\n" "$i" "$module" "${MODULE_DESCRIPTIONS[$module]}"
        ((i++))
    done
    echo

    if [[ "$INSTALLATION_MODE" == "interactive" ]]; then
        read -p "Proceed with installation? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled."
            return 0
        fi
    fi

    print_info "Starting development environment installation..."
    echo "Development installation started at $(date)" >> "$LOG_FILE"

    local failed_modules=()
    local installed_count=0

    # Install modules in the specified order
    for module in "${modules[@]}"; do
        if install_module "$module"; then
            ((installed_count++))
        else
            failed_modules+=("$module")
            # Continue with remaining modules even if one fails
        fi
    done

    echo
    print_success "Development environment installation completed!"
    print_info "Successfully installed: $installed_count/${#modules[@]} modules"

    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        print_warning "Failed modules: ${failed_modules[*]}"
        echo "Check log file for details: $LOG_FILE"
    fi

    echo "Development installation completed at $(date)" >> "$LOG_FILE"

    if [[ "$INSTALLATION_MODE" == "interactive" ]]; then
        echo
        echo "Press Enter to continue..."
        read
    fi
}

# Function to install individual module
install_module() {
    local module="$1"
    local script_path=$(get_module_script "$module")

    if [[ ! -f "$script_path" ]]; then
        print_error "Module script not found: $script_path"
        echo "ERROR: Module script not found for $module: $script_path" >> "$LOG_FILE"
        return 1
    fi

    print_info "Installing $module..."

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would execute: $script_path"
        return 0
    fi

    # Prepare installation arguments
    local install_args=()
    if [[ "$VERBOSE" == true ]]; then
        install_args+=("--verbose")
    fi
    if [[ "$INSTALLATION_MODE" == "quiet" ]]; then
        install_args+=("--quiet")
    fi

    # Execute installation script
    {
        echo "=== Installing $module at $(date) ==="
        echo "Script: $script_path"
        echo "Args: ${install_args[*]}"
        echo
    } >> "$LOG_FILE"

    if bash "$script_path" "${install_args[@]}" >> "$LOG_FILE" 2>&1; then
        print_success "✓ $module installed successfully"
        return 0
    else
        print_error "✗ Failed to install $module"
        echo "ERROR: Installation failed for $module" >> "$LOG_FILE"
        return 1
    fi
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -i|--interactive)
                INSTALLATION_MODE="interactive"
                shift
                ;;
            -q|--quiet)
                INSTALLATION_MODE="quiet"
                shift
                ;;
            -a|--auto)
                INSTALLATION_MODE="auto"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -l|--log)
                if [[ -n "$2" ]]; then
                    LOG_FILE="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --list-modules)
                list_modules
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to check prerequisites
check_prerequisites() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Check if helper files exist
    for helper in common.sh cli.sh system.sh; do
        if [[ ! -f "${SCRIPT_DIR}/_helpers/$helper" ]]; then
            print_error "Required helper file missing: _helpers/$helper"
            exit 1
        fi
    done

    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"

    # Check available disk space
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then  # 2GB in KB
        print_warning "Low disk space available. Development environment installation may fail."
    fi
}

# Function to validate all modules are available
validate_modules() {
    local missing_modules=()

    for module in "${DEV_MODULES[@]}"; do
        if ! is_module_available "$module"; then
            missing_modules+=("$module")
        fi
    done

    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        print_warning "Missing module scripts: ${missing_modules[*]}"
        print_info "Installation will continue with available modules only."
    fi
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Check prerequisites
    check_prerequisites

    # Validate modules
    validate_modules

    # Show header
    if [[ "$INSTALLATION_MODE" != "quiet" ]]; then
        show_script_header "bashmin Development Environment Installer v1.0.0" 70
        print_info "Log file: $LOG_FILE"
        print_info "Installation order: ${DEV_MODULES[*]}"
        echo
    fi

    # Execute based on mode
    case "$INSTALLATION_MODE" in
        "interactive")
            run_interactive_mode
            ;;
        "quiet"|"auto")
            install_modules "${DEV_MODULES[@]}"
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi