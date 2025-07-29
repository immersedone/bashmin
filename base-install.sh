#!/bin/bash
#
# File: base-install.sh
# Description: bashmin Suite Base Installer - Interactive CLI GUI and Automation
# Author: bashmin Security Team
# Version: 1.0.0
# Usage: ./base-install.sh [options]
#

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/_helpers/common.sh"
source "${SCRIPT_DIR}/_helpers/cli.sh"
source "${SCRIPT_DIR}/_helpers/system.sh"

# Default configuration
INSTALLATION_MODE="interactive"  # interactive, quiet, auto
SELECTED_MODULES=()
DRY_RUN=false
VERBOSE=false
LOG_FILE="/var/log/bashmin/base-install-$(date +%Y%m%d_%H%M%S).log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Module definitions with categories
declare -A MODULES=(
    # Core System
    ["system"]="System Configuration and Basic Setup"
    ["structure"]="Directory Structure and Permissions"
    ["users"]="User Management and Security"
    
    # Security Suite (8-layer defense)
    ["security-ufw"]="Network Security (UFW Firewall)"
    ["security-clamav"]="Malware Detection (ClamAV)"
    ["security-fail2ban"]="Intrusion Prevention (fail2ban)"
    ["security-letsencrypt"]="SSL/TLS Management (Let's Encrypt)"
    ["security-lynis"]="Security Auditing (Lynis)"
    ["security-rkhunter"]="Rootkit Detection (rkhunter)"
    ["security-nikto"]="Web Vulnerability Scanning (Nikto)"
    ["security-hardening"]="System Hardening (Ubuntu 24.04+)"
    
    # Web Servers
    ["server-apache2"]="Apache2 Web Server"
    ["server-nginx"]="Nginx Web Server"
    ["server-frankenphp"]="FrankenPHP Modern Server"
    
    # Databases
    ["server-mariadb"]="MariaDB Database Server"
    ["server-mongodb"]="MongoDB Database"
    ["server-redis"]="Redis Cache Server"
    ["server-elasticsearch"]="Elasticsearch Search Engine"
    ["server-typesense"]="Typesense Search Engine"
    
    # Application Servers
    ["server-php"]="PHP Configuration and Optimization"
    ["server-varnish"]="Varnish Cache Server"
    
    # Development Tools
    ["dev-composer"]="PHP Composer Package Manager"
    ["dev-nvm"]="Node Version Manager"
    ["dev-pnpm"]="PNPM Package Manager"
    ["dev-cghooks"]="Git Hooks Configuration"
    ["dev-tldr"]="TLDR Command Documentation"
    
    # System Software
    ["software-phpmyadmin"]="phpMyAdmin Database Interface"
    ["software-nodemon"]="Node.js Development Monitor"
    ["software-upgrades"]="Unattended Security Updates"
    
    # Network & Infrastructure
    ["sshd"]="SSH Daemon Configuration"
    ["hosts"]="Host File Management"
    
    # Automation
    ["crons"]="Automated Tasks and Scheduling"
    ["self-healing"]="Self-Healing System Services"
    
    # Virtualization
    ["wsl"]="Windows Subsystem for Linux Configuration"
)

# Module categories for organized display
declare -A MODULE_CATEGORIES=(
    ["Core System"]="system structure users"
    ["Security Suite"]="security-ufw security-clamav security-fail2ban security-letsencrypt security-lynis security-rkhunter security-nikto security-hardening"
    ["Web Servers"]="server-apache2 server-nginx server-frankenphp"
    ["Databases"]="server-mariadb server-mongodb server-redis server-elasticsearch server-typesense"
    ["Application Servers"]="server-php server-varnish"
    ["Development Tools"]="dev-composer dev-nvm dev-pnpm dev-cghooks dev-tldr"
    ["System Software"]="software-phpmyadmin software-nodemon software-upgrades"
    ["Network & Infrastructure"]="sshd hosts"
    ["Automation"]="crons self-healing"
    ["Virtualization"]="wsl"
)

# Preset configurations for common use cases
declare -A PRESETS=(
    ["minimal"]="system structure users"
    ["security"]="system structure users security-ufw security-clamav security-fail2ban security-letsencrypt security-lynis security-rkhunter security-nikto security-hardening"
    ["webserver"]="system structure users security-ufw security-clamav security-fail2ban security-letsencrypt server-apache2 server-php server-mariadb"
    ["development"]="system structure users security-ufw dev-composer dev-nvm dev-pnpm dev-cghooks dev-tldr software-nodemon"
    ["full"]="system structure users security-ufw security-clamav security-fail2ban security-letsencrypt security-lynis security-rkhunter security-nikto security-hardening server-apache2 server-nginx server-php server-mariadb server-redis dev-composer dev-nvm software-phpmyadmin crons"
)

# Function to show usage information
show_usage() {
    cat << 'EOF'
bashmin Suite Base Installer

USAGE:
    ./base-install.sh [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -i, --interactive       Interactive mode with CLI GUI (default)
    -q, --quiet             Quiet mode - minimal output
    -a, --auto              Automatic mode - use preset configuration
    -m, --modules LIST      Comma-separated list of modules to install
    -p, --preset NAME       Use predefined configuration preset
    -d, --dry-run           Show what would be installed without executing
    -v, --verbose           Enable verbose output
    -l, --log FILE          Custom log file location
    --list-modules          List all available modules
    --list-presets          List all available presets
    --no-deps               Skip dependency installation
    --force                 Force installation even if components exist

PRESETS:
    minimal                 Core system components only
    security                Complete 8-layer security suite
    webserver               Web server with database and security
    development             Development environment with tools
    full                    Complete installation (all modules)

EXAMPLES:
    # Interactive installation with CLI GUI
    sudo ./base-install.sh

    # Install security preset quietly
    sudo ./base-install.sh --quiet --preset security

    # Install specific modules
    sudo ./base-install.sh --modules "system,security-ufw,server-nginx"

    # Dry run to see what would be installed
    sudo ./base-install.sh --dry-run --preset webserver

    # Verbose installation with custom log
    sudo ./base-install.sh --verbose --log /tmp/install.log

EOF
}

# Function to list available modules
list_modules() {
    echo "Available bashmin Modules:"
    echo "========================="
    echo
    
    for category in "${!MODULE_CATEGORIES[@]}"; do
        echo -e "${BLUE}$category:${NC}"
        for module in ${MODULE_CATEGORIES[$category]}; do
            printf "  %-20s %s\n" "$module" "${MODULES[$module]}"
        done
        echo
    done
}

# Function to list available presets
list_presets() {
    echo "Available Installation Presets:"
    echo "==============================="
    echo
    
    for preset in "${!PRESETS[@]}"; do
        echo -e "${BLUE}$preset:${NC}"
        echo "  Modules: ${PRESETS[$preset]}"
        echo
    done
}

# Function to validate module exists
validate_module() {
    local module="$1"
    [[ -n "${MODULES[$module]}" ]]
}

# Function to get module install script path
get_module_script() {
    local module="$1"
    
    case "$module" in
        "system") echo "${SCRIPT_DIR}/system/install.sh" ;;
        "structure") echo "${SCRIPT_DIR}/structure/install.sh" ;;
        "users") echo "${SCRIPT_DIR}/users/install.sh" ;;
        "security-"*) 
            local security_component="${module#security-}"
            if [[ "$security_component" == "hardening" ]]; then
                echo "${SCRIPT_DIR}/security/ubuntu/harden.sh"
            else
                echo "${SCRIPT_DIR}/security/${security_component}/install.sh"
            fi
            ;;
        "server-"*)
            local server_component="${module#server-}"
            echo "${SCRIPT_DIR}/servers/${server_component}/install.sh"
            ;;
        "dev-"*)
            local dev_component="${module#dev-}"
            echo "${SCRIPT_DIR}/development/${dev_component}/install.sh"
            ;;
        "software-"*)
            local software_component="${module#software-}"
            echo "${SCRIPT_DIR}/software/${software_component}/install.sh"
            ;;
        "sshd") echo "${SCRIPT_DIR}/sshd/configure.sh" ;;
        "hosts") echo "${SCRIPT_DIR}/hosts/update-hosts.sh" ;;
        "crons") echo "${SCRIPT_DIR}/crons/security-kit.sh" ;;
        "self-healing") echo "${SCRIPT_DIR}/self-healing/systemd/install.sh" ;;
        "wsl") echo "${SCRIPT_DIR}/wsl/configure.sh" ;;
        *) return 1 ;;
    esac
}

# Function to check if module is available
is_module_available() {
    local module="$1"
    local script_path=$(get_module_script "$module")
    [[ -f "$script_path" ]]
}

# Function to show main menu in interactive mode
show_main_menu() {
    clear
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                    bashmin Suite Installer                  ║
║                  Enterprise Server Management               ║
╚══════════════════════════════════════════════════════════════╝

Welcome to the bashmin Suite - Your comprehensive server management toolkit

EOF

    echo -e "${BLUE}Installation Options:${NC}"
    echo "1) Quick Install (Preset Configurations)"
    echo "2) Custom Install (Select Individual Modules)"
    echo "3) Security Suite Only (8-Layer Defense)"
    echo "4) Development Environment"
    echo "5) Web Server Stack"
    echo "6) Full Installation (All Modules)"
    echo "7) Show Module Information"
    echo "8) View Installation Log"
    echo "9) Exit"
    echo
}

# Function to show preset menu
show_preset_menu() {
    clear
    echo -e "${BLUE}Quick Install Presets:${NC}"
    echo "===================="
    echo
    
    local i=1
    for preset in minimal security webserver development full; do
        echo "$i) $preset - ${PRESETS[$preset]}"
        ((i++))
    done
    echo
    echo "0) Back to Main Menu"
    echo
}

# Function to show module selection menu
show_module_menu() {
    clear
    echo -e "${BLUE}Module Selection:${NC}"
    echo "================"
    echo
    
    local category_num=1
    for category in "Core System" "Security Suite" "Web Servers" "Databases" "Application Servers" "Development Tools" "System Software" "Network & Infrastructure" "Automation" "Virtualization"; do
        echo "$category_num) $category"
        ((category_num++))
    done
    echo
    echo "11) Show Selected Modules"
    echo "12) Install Selected Modules"
    echo "0) Back to Main Menu"
    echo
}

# Function to show category modules
show_category_modules() {
    local category="$1"
    local modules="${MODULE_CATEGORIES[$category]}"
    
    clear
    echo -e "${BLUE}$category Modules:${NC}"
    echo "$(printf '=%.0s' $(seq 1 $((${#category} + 9))))"
    echo
    
    local i=1
    for module in $modules; do
        local status=""
        if [[ " ${SELECTED_MODULES[@]} " =~ " ${module} " ]]; then
            status=" ${GREEN}[SELECTED]${NC}"
        fi
        printf "%2d) %-20s %s%s\n" "$i" "$module" "${MODULES[$module]}" "$status"
        ((i++))
    done
    echo
    echo "0) Back to Module Menu"
    echo
}

# Function to toggle module selection
toggle_module() {
    local module="$1"
    
    if [[ " ${SELECTED_MODULES[@]} " =~ " ${module} " ]]; then
        # Remove module
        SELECTED_MODULES=($(printf '%s\n' "${SELECTED_MODULES[@]}" | grep -v "^${module}$"))
        print_info "Removed $module from selection"
    else
        # Add module
        SELECTED_MODULES+=("$module")
        print_success "Added $module to selection"
    fi
}

# Function to show selected modules
show_selected_modules() {
    clear
    echo -e "${BLUE}Selected Modules:${NC}"
    echo "================"
    echo
    
    if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
        echo "No modules selected."
    else
        local i=1
        for module in "${SELECTED_MODULES[@]}"; do
            printf "%2d) %-20s %s\n" "$i" "$module" "${MODULES[$module]}"
            ((i++))
        done
    fi
    echo
    echo "Press Enter to continue..."
    read
}

# Function to run interactive CLI GUI
run_interactive_mode() {
    while true; do
        show_main_menu
        read -p "Select an option (1-9): " choice
        
        case $choice in
            1) run_preset_selection ;;
            2) run_module_selection ;;
            3) SELECTED_MODULES=(${PRESETS[security]}); install_selected_modules ;;
            4) SELECTED_MODULES=(${PRESETS[development]}); install_selected_modules ;;
            5) SELECTED_MODULES=(${PRESETS[webserver]}); install_selected_modules ;;
            6) SELECTED_MODULES=(${PRESETS[full]}); install_selected_modules ;;
            7) show_module_info ;;
            8) show_install_log ;;
            9) exit 0 ;;
            *) print_error "Invalid option. Please select 1-9." ;;
        esac
    done
}

# Function to run preset selection
run_preset_selection() {
    while true; do
        show_preset_menu
        read -p "Select preset (0-5): " choice
        
        case $choice in
            1) SELECTED_MODULES=(${PRESETS[minimal]}); install_selected_modules; return ;;
            2) SELECTED_MODULES=(${PRESETS[security]}); install_selected_modules; return ;;
            3) SELECTED_MODULES=(${PRESETS[webserver]}); install_selected_modules; return ;;
            4) SELECTED_MODULES=(${PRESETS[development]}); install_selected_modules; return ;;
            5) SELECTED_MODULES=(${PRESETS[full]}); install_selected_modules; return ;;
            0) return ;;
            *) print_error "Invalid option. Please select 0-5." ;;
        esac
    done
}

# Function to run module selection
run_module_selection() {
    while true; do
        show_module_menu
        read -p "Select category (0-12): " choice
        
        case $choice in
            1) run_category_selection "Core System" ;;
            2) run_category_selection "Security Suite" ;;
            3) run_category_selection "Web Servers" ;;
            4) run_category_selection "Databases" ;;
            5) run_category_selection "Application Servers" ;;
            6) run_category_selection "Development Tools" ;;
            7) run_category_selection "System Software" ;;
            8) run_category_selection "Network & Infrastructure" ;;
            9) run_category_selection "Automation" ;;
            10) run_category_selection "Virtualization" ;;
            11) show_selected_modules ;;
            12) install_selected_modules; return ;;
            0) return ;;
            *) print_error "Invalid option. Please select 0-12." ;;
        esac
    done
}

# Function to run category selection
run_category_selection() {
    local category="$1"
    local modules="${MODULE_CATEGORIES[$category]}"
    local modules_array=($modules)
    
    while true; do
        show_category_modules "$category"
        read -p "Select module (0-${#modules_array[@]}): " choice
        
        if [[ $choice -eq 0 ]]; then
            return
        elif [[ $choice -ge 1 && $choice -le ${#modules_array[@]} ]]; then
            local selected_module="${modules_array[$((choice-1))]}"
            toggle_module "$selected_module"
            sleep 1
        else
            print_error "Invalid option. Please select 0-${#modules_array[@]}."
            sleep 1
        fi
    done
}

# Function to show module information
show_module_info() {
    clear
    list_modules
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

# Function to install selected modules
install_selected_modules() {
    if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
        print_error "No modules selected for installation."
        return 1
    fi
    
    clear
    echo -e "${BLUE}Installation Summary:${NC}"
    echo "===================="
    echo
    echo "The following modules will be installed:"
    for module in "${SELECTED_MODULES[@]}"; do
        echo "  • $module - ${MODULES[$module]}"
    done
    echo
    
    if [[ "$INSTALLATION_MODE" == "interactive" ]]; then
        read -p "Proceed with installation? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled."
            return 0
        fi
    fi
    
    print_info "Starting installation of ${#SELECTED_MODULES[@]} modules..."
    echo "Installation started at $(date)" >> "$LOG_FILE"
    
    local failed_modules=()
    local installed_count=0
    
    for module in "${SELECTED_MODULES[@]}"; do
        if install_module "$module"; then
            ((installed_count++))
        else
            failed_modules+=("$module")
        fi
    done
    
    echo
    print_success "Installation completed!"
    print_info "Successfully installed: $installed_count/${#SELECTED_MODULES[@]} modules"
    
    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        print_warning "Failed modules: ${failed_modules[*]}"
        echo "Check log file for details: $LOG_FILE"
    fi
    
    echo "Installation completed at $(date)" >> "$LOG_FILE"
    
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
            -m|--modules)
                if [[ -n "$2" ]]; then
                    IFS=',' read -ra SELECTED_MODULES <<< "$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            -p|--preset)
                if [[ -n "$2" && -n "${PRESETS[$2]}" ]]; then
                    IFS=' ' read -ra SELECTED_MODULES <<< "${PRESETS[$2]}"
                    shift 2
                else
                    print_error "Invalid preset: $2"
                    list_presets
                    exit 1
                fi
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
            --list-presets)
                list_presets
                exit 0
                ;;
            --no-deps)
                # TODO: Implement dependency skipping
                shift
                ;;
            --force)
                # TODO: Implement force installation
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to validate selected modules
validate_selected_modules() {
    local invalid_modules=()
    
    for module in "${SELECTED_MODULES[@]}"; do
        if ! validate_module "$module"; then
            invalid_modules+=("$module")
        elif ! is_module_available "$module"; then
            print_warning "Module script not found for: $module"
        fi
    done
    
    if [[ ${#invalid_modules[@]} -gt 0 ]]; then
        print_error "Invalid modules: ${invalid_modules[*]}"
        echo "Use --list-modules to see available modules"
        exit 1
    fi
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
    if [[ $available_space -lt 1048576 ]]; then  # 1GB in KB
        print_warning "Low disk space available. Installation may fail."
    fi
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Validate selected modules
    if [[ ${#SELECTED_MODULES[@]} -gt 0 ]]; then
        validate_selected_modules
    fi
    
    # Show header
    if [[ "$INSTALLATION_MODE" != "quiet" ]]; then
        show_script_header "bashmin Suite Base Installer v1.0.0" 60
        print_info "Log file: $LOG_FILE"
        echo
    fi
    
    # Execute based on mode
    case "$INSTALLATION_MODE" in
        "interactive")
            if [[ ${#SELECTED_MODULES[@]} -gt 0 ]]; then
                install_selected_modules
            else
                run_interactive_mode
            fi
            ;;
        "quiet"|"auto")
            if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
                print_error "No modules specified for automatic installation"
                echo "Use -p/--preset or -m/--modules to specify what to install"
                exit 1
            fi
            install_selected_modules
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
