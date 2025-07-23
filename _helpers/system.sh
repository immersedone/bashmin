#!/bin/bash
#
# File: system.sh
# Description: System management helper functions
# Usage: source "${SCRIPT_DIR}/_helpers/system.sh"
#

# Function to add repository with GPG key
add_repository_with_gpg() {
    local gpg_url="$1"
    local gpg_path="$2"
    local repo="$3"
    local description="$4"
    
    print_info "Adding $description repository..."
    
    # Add GPG key
    execute_command "curl -fsSL $gpg_url | sudo gpg --dearmor -o $gpg_path" "Adding $description GPG key"
    
    # Add repository
    execute_command "sudo add-apt-repository -y $repo" "Adding $description repository"
    
    # Update package lists
    execute_command "sudo apt update" "Updating package lists with new repository"
}

# Function to install packages
install_packages() {
    local packages=("$@")
    local package_list="${packages[*]}"
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        print_warning "No packages specified for installation"
        return 1
    fi
    
    execute_command "sudo apt install -y $package_list" "Installing packages: $package_list"
}

# Function to check if package is installed
is_package_installed() {
    local package="$1"
    dpkg -l | grep -q "^ii  $package "
}

# Function to get service status
get_service_status() {
    local service_name="$1"
    sudo systemctl is-active "$service_name" 2>/dev/null || echo "inactive"
}
