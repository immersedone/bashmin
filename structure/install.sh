#!/bin/bash

# BashMin Structure Installer
# Creates essential directory structure for web hosting and self-healing services
# Author: BashMin Team
# Version: 1.0

# Load helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/system.sh"

# Import colors from common.sh
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DIRECTORIES=(
    # General Directories
    "/var/www/vhosts"
    "/var/www/self-healing"
    "/var/www/ai"

    # User Directories
    "/home/${USER}/.bashmin"

    # Shared Directories
    "/usr/share/bashmin"

    # Logs
    "/var/log/bashmin/security"
    "/var/log/bashmin/monitoring"
    "/var/log/bashmin/automation"

    # TODO: Move these to individual install scripts
    "/var/log/apache2"
    "/var/log/clamav"
    "/var/log/fail2ban"
    "/var/log/lynis"
    "/var/log/mongodb"
    "/var/log/mysql"
    "/var/log/php"
    "/var/log/redis"
    "/var/log/rkhunter"
    "/var/log/ufw"
    "/var/log/unattended-upgrades"
    "/var/log/varnish"
)

# Detect the real user (not root when using sudo)
REAL_USER="${SUDO_USER:-$USER}"

# Directory permissions
VHOSTS_OWNER="$REAL_USER:www-data"
VHOSTS_PERMS="755"
SELF_HEALING_OWNER="root:root"
SELF_HEALING_PERMS="755"
AI_OWNER="$REAL_USER:www-data"
AI_PERMS="755"

# Function to print header
print_header() {
    echo
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}            $1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

# Function to create directory with proper ownership and permissions
create_directory_structure() {
    local dir_path="$1"
    local owner="$2"
    local perms="$3"
    
    print_info "Creating directory: $dir_path"
    
    if [[ -d "$dir_path" ]]; then
        print_warning "Directory $dir_path already exists"
    else
        if sudo mkdir -p "$dir_path"; then
            print_success "Created directory: $dir_path"
        else
            print_error "Failed to create directory: $dir_path"
            return 1
        fi
    fi
    
    # Set ownership
    if sudo chown "$owner" "$dir_path"; then
        print_success "Set ownership $owner on $dir_path"
    else
        print_warning "Failed to set ownership on $dir_path"
    fi
    
    # Set permissions
    if sudo chmod "$perms" "$dir_path"; then
        print_success "Set permissions $perms on $dir_path"
    else
        print_warning "Failed to set permissions on $dir_path"
    fi
}

# Function to verify directory structure
verify_structure() {
    print_info "Verifying directory structure..."
    
    local all_good=true
    
    for dir in "${DIRECTORIES[@]}"; do
        if [[ -d "$dir" ]]; then
            print_success "✓ $dir exists"
        else
            print_error "✗ $dir missing"
            all_good=false
        fi
    done
    
    if $all_good; then
        print_success "All directories are present!"
        return 0
    else
        print_error "Some directories are missing"
        return 1
    fi
}

# Main installation function
main() {
    print_header "BashMin Structure Installer"
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_info "Running as root"
    elif sudo -n true 2>/dev/null; then
        print_info "Sudo access confirmed"
    else
        print_error "This script requires sudo access"
        exit 1
    fi
    
    # Create vhosts directory
    create_directory_structure "/var/www/vhosts" "$VHOSTS_OWNER" "$VHOSTS_PERMS"
    
    # Create self-healing directory  
    create_directory_structure "/var/www/self-healing" "$SELF_HEALING_OWNER" "$SELF_HEALING_PERMS"
    
    # Create AI directory
    create_directory_structure "/var/www/ai" "$AI_OWNER" "$AI_PERMS"
    
    # Verify everything is created properly
    if verify_structure; then
        print_success "Directory structure installation completed successfully!"
        
        # Show the structure
        echo
        print_info "Created structure:"
        echo "├── /var/www/"
        echo "    ├── vhosts/     (for virtual hosts)"
        echo "    ├── self-healing/ (for monitoring & automation)"
        echo "    └── ai/         (for AI applications)"
        echo
        
        return 0
    else
        print_error "Directory structure installation failed!"
        return 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
