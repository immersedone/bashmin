#!/bin/bash
#
# File: common.sh
# Description: Common helper functions for bashmin scripts
# Usage: source "${SCRIPT_DIR}/_helpers/common.sh"
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to execute commands with error handling
execute_command() {
    local cmd="$1"
    local description="$2"
    local verbose="${VERBOSE:-false}"
    local dry_run="${DRY_RUN:-false}"
    
    if [[ "$verbose" == true ]]; then
        print_info "Executing: $cmd"
    fi
    
    if [[ "$dry_run" == true ]]; then
        echo "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    print_info "$description"
    if eval "$cmd"; then
        print_success "✓ $description completed"
        return 0
    else
        print_error "✗ $description failed"
        return 1
    fi
}

# Function to check if running on Ubuntu-based system
check_ubuntu_system() {
    if ! command -v apt &> /dev/null; then
        print_error "This script requires apt package manager (Ubuntu/Debian-based systems)"
        exit 1
    fi
    
    if ! grep -qi ubuntu /etc/os-release && ! grep -qi debian /etc/os-release; then
        print_warning "This script is designed for Ubuntu-based systems"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Consider running as regular user with sudo access."
    fi
}

# Function to update system packages
update_system() {
    execute_command "sudo apt update" "Updating package lists"
}

# Function to install prerequisites
install_prerequisites() {
    local packages="$1"
    execute_command "sudo apt install -y $packages" "Installing prerequisites"
}

# Function to check if service is active
check_service_status() {
    local service_name="$1"
    local dry_run="${DRY_RUN:-false}"
    
    if [[ "$dry_run" == false ]]; then
        if sudo systemctl is-active --quiet "$service_name"; then
            print_success "$service_name is running"
            return 0
        else
            print_warning "$service_name service may not be running properly"
            return 1
        fi
    fi
}

# Function to enable and start service
enable_start_service() {
    local service_name="$1"
    
    execute_command "sudo systemctl enable $service_name" "Enabling $service_name service"
    execute_command "sudo systemctl start $service_name" "Starting $service_name service"
    check_service_status "$service_name"
}

# Function to validate array contains value
array_contains() {
    local array_name="$1[@]"
    local value="$2"
    local array=("${!array_name}")
    
    for element in "${array[@]}"; do
        if [[ "$element" == "$value" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to get script directory
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
}

# Function to show confirmation prompt
confirm_action() {
    local message="$1"
    local default="${2:-N}"
    
    if [[ "$default" == "Y" ]]; then
        read -p "$message (Y/n): " -n 1 -r
    else
        read -p "$message (y/N): " -n 1 -r
    fi
    echo
    
    if [[ "$default" == "Y" ]]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}
