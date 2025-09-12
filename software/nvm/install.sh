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
    --user                  Install NVM for current user only (default if no scope specified)
    --system                Install NVM system-wide for all users
    --version=VER           Specify NVM version to install (default: $NVM_DEFAULT_VERSION)
    --no-node               Skip Node.js installation (only install NVM)
    --no-global-packages    Skip global package installation (pnpm, puppeteer, claude-code)
    --verbose               Enable verbose output
    --dry-run               Show what would be done without executing
    -h, --help              Show this help message

EXAMPLES:
    $0                                      # Install NVM + Node.js + global packages
    $0 --user                               # Install for current user
    $0 --system                             # Install system-wide
    $0 --user --version=v0.39.0             # Install specific version for user
    $0 --no-node                            # Install only NVM (no Node.js versions)
    $0 --no-global-packages                 # Install NVM + Node.js (no global packages)
    $0 --no-node --no-global-packages       # Install only NVM

DEFAULT BEHAVIOR:
    - Installs NVM (Node Version Manager)
    - Installs latest 3 Node.js versions (one per major version)
    - Sets up 'latest' alias and default version
    - Installs global packages: pnpm, puppeteer, @anthropic-ai/claude-code

EOF
}

# Parse command line arguments
INSTALL_SCOPE=""
NVM_VERSION=""
VERBOSE=false
DRY_RUN=false
INSTALL_NODE=true  # Install Node.js versions by default
INSTALL_GLOBAL_PACKAGES=true  # Install global packages by default

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
        --no-node)
            INSTALL_NODE=false
            shift
            ;;
        --no-global-packages)
            INSTALL_GLOBAL_PACKAGES=false
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
        
        # Ensure NVM is available in parent shell if possible
        if [[ -n "$BASH_VERSION" ]] && [[ -f "${HOME}/.bashrc" ]]; then
            print_info "Ensuring NVM is configured in ~/.bashrc..."
            if ! grep -q "NVM_DIR" "${HOME}/.bashrc"; then
                print_warning "NVM configuration not found in ~/.bashrc, may need manual setup"
            fi
        fi
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
    local shell_rc_file
    
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        nvm_dir="${HOME}/.nvm"
    else
        nvm_dir="$NVM_SYSTEM_DIR"
    fi
    
    # Determine the shell configuration file
    if [[ -n "$BASH_VERSION" ]]; then
        shell_rc_file="${HOME}/.bashrc"
    elif [[ -n "$ZSH_VERSION" ]]; then
        shell_rc_file="${HOME}/.zshrc"
    else
        shell_rc_file="${HOME}/.bashrc"  # Default to bashrc
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
                
                # Reload shell configuration for immediate use
                if [[ -f "$shell_rc_file" ]]; then
                    print_info "Reloading shell configuration from $shell_rc_file..."
                    source "$shell_rc_file" 2>/dev/null || true
                fi
                
                # Verify NVM is now available as a function
                if type nvm &>/dev/null; then
                    print_success "NVM is now available in current shell"
                else
                    print_info "NVM function loaded but may require a new shell session"
                fi
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
IMPORTANT: NVM is a shell function, not a binary program.
This means 'which nvm' will not find it - use 'type nvm' instead.

To start using NVM immediately in this session, run:
  source ~/.bashrc

Or simply open a new terminal window/tab.

Verify NVM is loaded:
  type nvm                  # Should show "nvm is a function"
  nvm --version             # Should display version number

Basic NVM usage:
  nvm install node          # Install latest Node.js
  nvm install --lts         # Install latest LTS version
  nvm install 18            # Install Node.js v18
  nvm use 18                # Switch to Node.js v18
  nvm list                  # List installed versions
  nvm list-remote           # List available versions
  nvm alias default 18      # Set default Node.js version

NVM is installed at: ${HOME}/.nvm
EOF
    else
        cat << EOF
IMPORTANT: NVM is a shell function, not a binary program.
This means 'which nvm' will not find it - use 'type nvm' instead.

To start using NVM immediately in this session, run:
  source /etc/profile.d/nvm.sh

Or simply open a new terminal window/tab.

Verify NVM is loaded:
  type nvm                  # Should show "nvm is a function"
  nvm --version             # Should display version number

Basic NVM usage:
  nvm install node          # Install latest Node.js
  nvm install --lts         # Install latest LTS version
  nvm install 18            # Install Node.js v18
  nvm use 18                # Switch to Node.js v18
  nvm list                  # List installed versions
  nvm list-remote           # List available versions
  nvm alias default 18      # Set default Node.js version

NVM is installed system-wide at: $NVM_SYSTEM_DIR
All users will have access to NVM after their next login.
EOF
    fi
    
    echo
    print_success "NVM installation completed successfully! 🚀"
    
    # Try to make NVM available immediately
    if [[ "$DRY_RUN" == false ]]; then
        echo
        print_info "Attempting to make NVM available in current shell..."
        if [[ "$INSTALL_SCOPE" == "user" ]]; then
            export NVM_DIR="${HOME}/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        else
            source /etc/profile.d/nvm.sh 2>/dev/null || true
        fi
        
        if type nvm &>/dev/null; then
            print_success "✓ NVM is now available in this shell session!"
            print_info "You can start using 'nvm' commands immediately."
        else
            print_info "NVM will be available after running: source ~/.bashrc"
        fi
    fi
}

# Function to install latest Node.js versions
install_node_versions() {
    print_info "=== Setting up Node.js versions ==="
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install latest 3 Node.js versions and set up aliases"
        return 0
    fi
    
    # Ensure NVM is loaded
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        export NVM_DIR="${HOME}/.nvm"
    else
        export NVM_DIR="$NVM_SYSTEM_DIR"
    fi
    
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    if ! type nvm &>/dev/null; then
        print_warning "NVM not available in current shell, skipping Node.js installation"
        print_info "You can manually install Node.js versions later with: nvm install node"
        return 0
    fi
    
    print_info "Fetching available Node.js versions..."
    
    # Get the latest 3 stable versions (excluding pre-releases and old versions)
    local versions_to_install=()
    local latest_version=""
    
    # Get latest stable version numbers (major versions only)
    # Temporarily disable strict mode to avoid NVM unbound variable issues
    set +u
    local available_versions=$(nvm ls-remote --no-colors 2>/dev/null | grep -E "v[0-9]+\.[0-9]+\.[0-9]+$" | tail -50 | tac)
    set -u
    
    # Extract unique major versions and get latest patch for each
    local major_versions=()
    local count=0
    
    while IFS= read -r version; do
        version=$(echo "$version" | tr -d ' ' | sed 's/->.*//g')
        major=$(echo "$version" | sed 's/v\([0-9]*\)\..*/\1/')
        
        # Check if we already have this major version
        local already_have=false
        for mv in "${major_versions[@]}"; do
            if [[ "$mv" == "$major" ]]; then
                already_have=true
                break
            fi
        done
        
        if [[ "$already_have" == false ]]; then
            major_versions+=("$major")
            versions_to_install+=("$version")
            
            # First version is the latest
            if [[ -z "$latest_version" ]]; then
                latest_version="$version"
            fi
            
            count=$((count + 1))
            if [[ $count -ge 3 ]]; then
                break
            fi
        fi
    done <<< "$available_versions"
    
    if [[ ${#versions_to_install[@]} -eq 0 ]]; then
        print_warning "Could not determine Node.js versions to install"
        return 0
    fi
    
    print_info "Will install the following Node.js versions:"
    for v in "${versions_to_install[@]}"; do
        echo "  - $v"
    done
    echo
    
    # Install each version
    for version in "${versions_to_install[@]}"; do
        print_info "Installing Node.js $version..."
        set +u  # Disable strict mode for NVM commands
        if nvm install "$version" &>/dev/null; then
            print_success "✓ Node.js $version installed"
        else
            print_warning "Failed to install Node.js $version"
        fi
        set -u  # Re-enable strict mode
    done
    
    # Set up aliases
    if [[ -n "$latest_version" ]]; then
        print_info "Setting up aliases..."
        
        set +u  # Disable strict mode for NVM commands
        
        # Create 'latest' alias
        if nvm alias latest "$latest_version" &>/dev/null; then
            print_success "✓ Created alias 'latest' -> $latest_version"
        fi
        
        # Set as default
        if nvm alias default "$latest_version" &>/dev/null; then
            print_success "✓ Set $latest_version as default"
        fi
        
        # Use the latest version now
        if nvm use "$latest_version" &>/dev/null; then
            print_success "✓ Now using Node.js $latest_version"
        fi
        
        set -u  # Re-enable strict mode
        
        echo
        print_info "Node.js setup complete!"
        echo "  Current version: $(node --version 2>/dev/null || echo 'unknown')"
        echo "  NPM version: $(npm --version 2>/dev/null || echo 'unknown')"
        echo
        print_info "Installed versions:"
        set +u
        nvm list 2>/dev/null | head -10 || echo "  Run 'nvm list' to see installed versions"
        set -u
    fi
}

# Function to install global packages
install_global_packages() {
    print_info "=== Installing Global Packages ==="
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install global packages using ./software/nvm/global-packages.sh"
        return 0
    fi
    
    # Check if the global packages script exists
    local global_packages_script="${SCRIPT_DIR}/software/nvm/global-packages.sh"
    
    if [[ ! -f "$global_packages_script" ]]; then
        print_warning "Global packages script not found at: $global_packages_script"
        print_info "Skipping global package installation"
        return 0
    fi
    
    # Make sure the script is executable
    chmod +x "$global_packages_script"
    
    print_info "Running global packages installer..."
    echo
    
    # Run the global packages script with appropriate flags
    local global_flags=""
    if [[ "$VERBOSE" == true ]]; then
        global_flags="--verbose"
    fi
    
    # Ensure NVM is loaded for the global packages script
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        export NVM_DIR="${HOME}/.nvm"
    else
        export NVM_DIR="$NVM_SYSTEM_DIR"
    fi
    
    # Source NVM to ensure it's available
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Run the global packages script automatically (non-interactive)
    if "$global_packages_script" $global_flags <<< "y"; then
        print_success "Global packages installed successfully"
    else
        print_warning "Some global packages may have failed to install"
        print_info "You can manually install them later using: $global_packages_script"
    fi
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
    
    # Install Node.js versions if requested
    if [[ "$INSTALL_NODE" == true ]] && [[ "$DRY_RUN" == false ]]; then
        echo
        if confirm_action "Would you like to install the latest 3 Node.js versions?" "Y"; then
            install_node_versions
            
            # Install global packages after Node.js is installed
            if [[ "$INSTALL_GLOBAL_PACKAGES" == true ]]; then
                echo
                if confirm_action "Would you like to install essential global packages (pnpm, puppeteer, claude-code)?" "Y"; then
                    install_global_packages
                else
                    print_info "Skipping global packages. You can install them later with: ./software/nvm/global-packages.sh"
                fi
            fi
        else
            print_info "Skipping Node.js installation. You can install it later with: nvm install node"
        fi
    elif [[ "$DRY_RUN" == true ]] && [[ "$INSTALL_NODE" == true ]]; then
        echo
        echo "[DRY-RUN] Would prompt to install latest 3 Node.js versions"
        if [[ "$INSTALL_GLOBAL_PACKAGES" == true ]]; then
            echo "[DRY-RUN] Would prompt to install global packages"
        fi
    fi
}

# Run main function
main "$@"
