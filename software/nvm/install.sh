#!/bin/bash
#
# Script: software/nvm/install.sh
# Description: Install Node Version Manager (NVM) with user or system-wide scope
# Usage: ./software/nvm/install.sh [--user|--system] [--version=VERSION] [--verbose] [--dry-run]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/_helpers/common.sh"
source "${SCRIPT_DIR}/_helpers/cli.sh"

# Script configuration
readonly NVM_DEFAULT_VERSION="v0.40.1"
readonly NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm"
readonly NVM_SYSTEM_DIR="/usr/local/nvm"

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Install Node Version Manager (NVM) with user or system-wide scope.

OPTIONS:
    --user          Install NVM for current user only (default if no scope specified)
    --system        Install NVM system-wide for all users
    --version=VER   Specify NVM version to install (default: $NVM_DEFAULT_VERSION)
    --verbose       Enable verbose output
    --dry-run       Show what would be done without executing
    -h, --help      Show this help message

EXAMPLES:
    $0                              # Interactive prompt for scope
    $0 --user                       # Install for current user
    $0 --system                     # Install system-wide
    $0 --user --version=v0.39.0     # Install specific version for user

EOF
}

# Parse command line arguments
INSTALL_SCOPE=""
NVM_VERSION=""
VERBOSE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            INSTALL_SCOPE="user"
            shift
            ;;
        --system)
            INSTALL_SCOPE="system"
            shift
            ;;
        --version=*)
            NVM_VERSION="${1#*=}"
            shift
            ;;
        --verbose)
            VERBOSE=true
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

# Function to detect existing NVM installation
detect_existing_nvm() {
    local user_nvm_dir="${HOME}/.nvm"
    local system_nvm_dir="$NVM_SYSTEM_DIR"
    
    if [[ -d "$user_nvm_dir" ]]; then
        print_warning "NVM is already installed for current user at: $user_nvm_dir"
        if confirm_action "Reinstall NVM for current user?"; then
            return 0
        else
            print_info "Skipping NVM installation"
            exit 0
        fi
    fi
    
    if [[ -d "$system_nvm_dir" ]]; then
        print_warning "NVM is already installed system-wide at: $system_nvm_dir"
        if confirm_action "Reinstall NVM system-wide?"; then
            return 0
        else
            print_info "Skipping NVM installation"
            exit 0
        fi
    fi
}

# Function to prompt for installation scope
prompt_for_scope() {
    if [[ -n "$INSTALL_SCOPE" ]]; then
        return 0
    fi
    
    local options=("Current user only" "All users (system-wide)")
    local selection
    
    selection=$(show_selection_menu "Choose NVM installation scope" "${options[@]}")
    
    case "$selection" in
        "Current user only")
            INSTALL_SCOPE="user"
            ;;
        "All users (system-wide)")
            INSTALL_SCOPE="system"
            ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac
}

# Function to install NVM prerequisites
install_nvm_prerequisites() {
    print_info "Installing prerequisites for NVM..."
    install_prerequisites "curl git"
}

# Function to install NVM for current user
install_nvm_user() {
    local nvm_dir="${HOME}/.nvm"
    local install_script_url="${NVM_INSTALL_URL}/${NVM_VERSION}/install.sh"
    
    print_info "Installing NVM $NVM_VERSION for current user..."
    
    # Download the install script first for verification
    execute_command "curl -fsSL -o /tmp/nvm-install.sh '$install_script_url'" "Downloading NVM install script"
    
    # Verify the script is not empty and contains expected content
    if [[ "$DRY_RUN" == false ]]; then
        if [[ ! -s /tmp/nvm-install.sh ]]; then
            print_error "Downloaded script is empty"
            return 1
        fi
        
        # Basic validation - check for NVM signature in the script
        if ! grep -q "nvm_install_dir" /tmp/nvm-install.sh; then
            print_error "Downloaded script doesn't appear to be valid NVM installer"
            rm -f /tmp/nvm-install.sh
            return 1
        fi
    fi
    
    # Run the install script
    execute_command "bash /tmp/nvm-install.sh" "Installing NVM"
    
    # Clean up
    execute_command "rm -f /tmp/nvm-install.sh" "Cleaning up temporary files"
    
    # Source NVM for immediate use
    if [[ "$DRY_RUN" == false ]]; then
        export NVM_DIR="$nvm_dir"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    fi
    
    print_success "NVM installed to: $nvm_dir"
}

# Function to install NVM system-wide
install_nvm_system() {
    local nvm_dir="$NVM_SYSTEM_DIR"
    local install_script_url="${NVM_INSTALL_URL}/${NVM_VERSION}/install.sh"
    
    print_info "Installing NVM $NVM_VERSION system-wide..."
    
    # Create system NVM directory
    execute_command "sudo mkdir -p '$nvm_dir'" "Creating system NVM directory"
    
    # Download NVM installation script
    execute_command "curl -fsSL -o /tmp/nvm-install.sh '$install_script_url'" "Downloading NVM install script"
    
    # Verify the script is not empty and contains expected content
    if [[ "$DRY_RUN" == false ]]; then
        if [[ ! -s /tmp/nvm-install.sh ]]; then
            print_error "Downloaded script is empty"
            return 1
        fi
        
        # Basic validation - check for NVM signature in the script
        if ! grep -q "nvm_install_dir" /tmp/nvm-install.sh; then
            print_error "Downloaded script doesn't appear to be valid NVM installer"
            rm -f /tmp/nvm-install.sh
            return 1
        fi
    fi
    
    # Set environment for system installation and run
    execute_command "sudo env NVM_DIR='$nvm_dir' bash /tmp/nvm-install.sh" "Installing NVM system-wide"
    
    # Clean up temp file
    execute_command "rm -f /tmp/nvm-install.sh" "Cleaning up temporary files"
    
    # Create system-wide profile script
    create_system_profile_script "$nvm_dir"
    
    print_success "NVM installed system-wide to: $nvm_dir"
}

# Function to create system-wide NVM profile script
create_system_profile_script() {
    local nvm_dir="$1"
    local profile_script="/etc/profile.d/nvm.sh"
    
    print_info "Creating system-wide NVM profile script..."
    
    local nvm_script_content="#!/bin/bash
# NVM system-wide configuration
export NVM_DIR=\"$nvm_dir\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
[ -s \"\$NVM_DIR/bash_completion\" ] && \\. \"\$NVM_DIR/bash_completion\"
"
    
    if [[ "$DRY_RUN" == false ]]; then
        echo "$nvm_script_content" | sudo tee "$profile_script" > /dev/null
        sudo chmod +x "$profile_script"
    else
        echo "[DRY-RUN] Would create $profile_script with NVM configuration"
    fi
    
    print_success "System-wide NVM profile created at: $profile_script"
}

# Function to verify NVM installation
verify_installation() {
    local nvm_dir
    
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        nvm_dir="${HOME}/.nvm"
    else
        nvm_dir="$NVM_SYSTEM_DIR"
    fi
    
    print_info "Verifying NVM installation..."
    
    if [[ "$DRY_RUN" == false ]]; then
        if [[ -s "$nvm_dir/nvm.sh" ]]; then
            # Source NVM and check version
            export NVM_DIR="$nvm_dir"
            source "$NVM_DIR/nvm.sh"
            
            local nvm_version_output
            nvm_version_output=$(nvm --version 2>/dev/null || echo "")
            
            if [[ -n "$nvm_version_output" ]]; then
                print_success "NVM installation verified. Version: $nvm_version_output"
            else
                print_warning "NVM installed but version check failed. You may need to restart your shell."
            fi
        else
            print_error "NVM installation verification failed"
            return 1
        fi
    else
        echo "[DRY-RUN] Would verify NVM installation at $nvm_dir"
    fi
}

# Function to show post-installation instructions
show_post_install_instructions() {
    echo
    print_info "=== Post-Installation Instructions ==="
    echo
    
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        cat << EOF
To start using NVM immediately, run:
  source ~/.bashrc

Or restart your terminal session.

Basic NVM usage:
  nvm install node          # Install latest Node.js
  nvm install 18            # Install Node.js v18
  nvm use 18                # Switch to Node.js v18
  nvm list                  # List installed versions
  nvm list-remote           # List available versions

NVM is installed at: ${HOME}/.nvm
EOF
    else
        cat << EOF
To start using NVM immediately, run:
  source /etc/profile.d/nvm.sh

Or restart your terminal session.

Basic NVM usage:
  nvm install node          # Install latest Node.js
  nvm install 18            # Install Node.js v18
  nvm use 18                # Switch to Node.js v18
  nvm list                  # List installed versions
  nvm list-remote           # List available versions

NVM is installed system-wide at: $NVM_SYSTEM_DIR
All users will have access to NVM after their next login.
EOF
    fi
    
    echo
    print_success "NVM installation completed successfully! 🚀"
}

# Main installation function
main() {
    show_script_header "NVM Installation Script"
    
    # Check system compatibility
    check_ubuntu_system
    
    # Set default version if not specified
    if [[ -z "$NVM_VERSION" ]]; then
        NVM_VERSION="$NVM_DEFAULT_VERSION"
    fi
    
    print_info "NVM version to install: $NVM_VERSION"
    
    # Detect existing installations
    detect_existing_nvm
    
    # Prompt for installation scope if not specified
    prompt_for_scope
    
    print_info "Installation scope: $INSTALL_SCOPE"
    
    # Confirm installation
    if ! confirm_action "Proceed with NVM installation?" "Y"; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Install prerequisites
    update_system
    install_nvm_prerequisites
    
    # Install NVM based on scope
    case "$INSTALL_SCOPE" in
        "user")
            install_nvm_user
            ;;
        "system")
            # Check for root/sudo access for system installation
            if [[ $EUID -eq 0 ]]; then
                print_warning "Running as root for system installation"
            elif ! sudo -n true 2>/dev/null; then
                print_error "System-wide installation requires sudo access"
                exit 1
            fi
            install_nvm_system
            ;;
        *)
            print_error "Invalid installation scope: $INSTALL_SCOPE"
            exit 1
            ;;
    esac
    
    # Verify installation
    verify_installation
    
    # Show post-installation instructions
    show_post_install_instructions
}

# Run main function
main "$@"
