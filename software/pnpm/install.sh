#!/bin/bash
#
# Script: software/pnpm/install.sh
# Description: Install pnpm (fast, disk space efficient package manager) via Node.js
# Usage: ./software/pnpm/install.sh [--method=METHOD] [--version=VERSION] [--verbose] [--dry-run]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/_helpers/common.sh"
source "${SCRIPT_DIR}/_helpers/cli.sh"

# Script configuration
readonly PNPM_DEFAULT_VERSION="latest"
readonly MIN_NODE_VERSION="16.14.0"
readonly PNPM_INSTALL_URL="https://get.pnpm.io/install.sh"

# Parse command line arguments
INSTALL_METHOD=""
PNPM_VERSION=""
VERBOSE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --method=*)
            INSTALL_METHOD="${1#*=}"
            shift
            ;;
        --version=*)
            PNPM_VERSION="${1#*=}"
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

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Install pnpm (fast, disk space efficient package manager) via Node.js.

OPTIONS:
    --method=METHOD Install method: npm, corepack, or standalone (default: auto-detect)
    --version=VER   Specify pnpm version to install (default: $PNPM_DEFAULT_VERSION)
    --verbose       Enable verbose output
    --dry-run       Show what would be done without executing
    -h, --help      Show this help message

INSTALL METHODS:
    npm         Install via 'npm install -g pnpm' (requires npm)
    corepack    Enable via 'corepack enable' (Node.js 16.9+, recommended)
    standalone  Install via official installer script (fallback)

EXAMPLES:
    $0                              # Auto-detect best method
    $0 --method=corepack            # Use corepack (recommended)
    $0 --method=npm                 # Install via npm
    $0 --method=standalone          # Use standalone installer
    $0 --method=npm --version=8.15.1 # Install specific version via npm

NOTES:
    - Corepack method is recommended for Node.js 16.9+
    - npm method installs globally and may require sudo
    - Standalone method works without existing package managers

EOF
}

# Function to check Node.js prerequisites
check_nodejs_prerequisites() {
    print_info "Checking Node.js prerequisites..."
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed"
        print_info "Please install Node.js first using:"
        print_info "  - NVM: ./software/nvm/install.sh"
        print_info "  - Or visit: https://nodejs.org/"
        exit 1
    fi
    
    # Check Node.js version
    local node_version
    node_version=$(node --version | sed 's/v//')
    
    if ! version_compare "$node_version" "$MIN_NODE_VERSION"; then
        print_error "Node.js version $node_version is too old"
        print_error "Minimum required version: $MIN_NODE_VERSION"
        print_info "Please update Node.js and try again"
        exit 1
    fi
    
    print_success "Node.js $(node --version) is compatible"
}

# Function to compare semantic versions
version_compare() {
    local version1="$1"
    local version2="$2"
    
    # Simple version comparison (works for most cases)
    if [[ "$version1" == "$version2" ]]; then
        return 0
    fi
    
    local IFS=.
    local i ver1=($version1) ver2=($version2)
    
    # Fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 0
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 1
        fi
    done
    return 0
}

# Function to detect Node.js capabilities
detect_node_capabilities() {
    local node_version
    node_version=$(node --version | sed 's/v//')
    
    # Check if corepack is available (Node.js 16.9+)
    if version_compare "$node_version" "16.9.0" && command -v corepack &> /dev/null; then
        echo "corepack"
    elif command -v npm &> /dev/null; then
        echo "npm"
    else
        echo "standalone"
    fi
}

# Function to detect existing pnpm installation
detect_existing_pnpm() {
    if command -v pnpm &> /dev/null; then
        local pnpm_version
        pnpm_version=$(pnpm --version 2>/dev/null || echo "unknown")
        print_warning "pnpm is already installed (version: $pnpm_version)"
        
        # Detect installation method
        local install_source="unknown"
        if command -v corepack &> /dev/null && corepack pnpm --version &> /dev/null; then
            install_source="corepack"
        elif npm list -g pnpm &> /dev/null; then
            install_source="npm"
        else
            install_source="standalone"
        fi
        
        print_info "Current installation method: $install_source"
        
        if ! confirm_action "Reinstall pnpm?"; then
            print_info "Skipping pnpm installation"
            exit 0
        fi
    fi
}

# Function to determine best installation method
determine_install_method() {
    if [[ -n "$INSTALL_METHOD" ]]; then
        # Validate specified method
        case "$INSTALL_METHOD" in
            npm|corepack|standalone)
                return 0
                ;;
            *)
                print_error "Invalid installation method: $INSTALL_METHOD"
                print_info "Valid methods: npm, corepack, standalone"
                exit 1
                ;;
        esac
    fi
    
    # Auto-detect best method
    local capability
    capability=$(detect_node_capabilities)
    
    local options=()
    local descriptions=()
    
    case "$capability" in
        "corepack")
            options=("Corepack (recommended)" "npm (global install)" "Standalone installer")
            descriptions=("Use Node.js corepack (fastest, most efficient)" 
                         "Install via npm globally" 
                         "Download and install standalone")
            ;;
        "npm")
            options=("npm (global install)" "Standalone installer")
            descriptions=("Install via npm globally" 
                         "Download and install standalone")
            ;;
        *)
            options=("Standalone installer")
            descriptions=("Download and install standalone")
            ;;
    esac
    
    local selection
    selection=$(show_selection_menu "Choose pnpm installation method" "${options[@]}")
    
    case "$selection" in
        "Corepack (recommended)")
            INSTALL_METHOD="corepack"
            ;;
        "npm (global install)")
            INSTALL_METHOD="npm"
            ;;
        "Standalone installer")
            INSTALL_METHOD="standalone"
            ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac
}

# Function to install pnpm via corepack
install_pnpm_corepack() {
    print_info "Installing pnpm via corepack..."
    
    # Check if corepack is available
    if ! command -v corepack &> /dev/null; then
        print_error "corepack is not available"
        print_info "corepack is included with Node.js 16.9+. Please update Node.js or use --method=npm"
        exit 1
    fi
    
    # Enable corepack if not already enabled
    execute_command "corepack enable" "Enabling corepack"
    
    # Install specific version if requested
    if [[ "$PNPM_VERSION" != "latest" ]]; then
        execute_command "corepack prepare pnpm@$PNPM_VERSION --activate" "Preparing pnpm@$PNPM_VERSION"
    fi
    
    print_success "pnpm installed via corepack"
}

# Function to install pnpm via npm
install_pnpm_npm() {
    print_info "Installing pnpm via npm..."
    
    # Check if npm is available
    if ! command -v npm &> /dev/null; then
        print_error "npm is not available"
        print_info "Please install npm or use --method=standalone"
        exit 1
    fi
    
    local version_flag=""
    if [[ "$PNPM_VERSION" != "latest" ]]; then
        version_flag="@$PNPM_VERSION"
    fi
    
    # Check if we need sudo for global npm install
    local npm_prefix
    npm_prefix=$(npm config get prefix 2>/dev/null || echo "/usr/local")
    
    local npm_cmd="npm install -g pnpm$version_flag"
    
    # If npm prefix is not writable, suggest using sudo
    if [[ ! -w "$npm_prefix" ]] && [[ $EUID -ne 0 ]]; then
        print_warning "Global npm installation may require elevated privileges"
        if confirm_action "Use sudo for global installation?"; then
            npm_cmd="sudo $npm_cmd"
        else
            print_error "Cannot install globally without write access to $npm_prefix"
            print_info "Consider using --method=corepack or configuring npm prefix"
            exit 1
        fi
    fi
    
    execute_command "$npm_cmd" "Installing pnpm via npm"
    
    print_success "pnpm installed via npm"
}

# Function to install pnpm via standalone installer
install_pnpm_standalone() {
    print_info "Installing pnpm via standalone installer..."
    
    # Set version environment variable if specified
    local env_vars=""
    if [[ "$PNPM_VERSION" != "latest" ]]; then
        env_vars="PNPM_VERSION=$PNPM_VERSION"
    fi
    
    # Download and run the official installer
    execute_command "curl -fsSL $PNPM_INSTALL_URL | $env_vars sh -" "Downloading and installing pnpm"
    
    # Add pnpm to PATH for current session
    if [[ "$DRY_RUN" == false ]]; then
        local pnpm_home="${PNPM_HOME:-$HOME/.local/share/pnpm}"
        if [[ -d "$pnpm_home" ]] && [[ ":$PATH:" != *":$pnpm_home:"* ]]; then
            export PATH="$pnpm_home:$PATH"
            print_info "Added pnpm to PATH for current session"
        fi
    fi
    
    print_success "pnpm installed via standalone installer"
}

# Function to setup pnpm configuration
setup_pnpm_config() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure pnpm settings"
        return 0
    fi
    
    print_info "Configuring pnpm..."
    
    # Set some useful defaults
    if command -v pnpm &> /dev/null; then
        # Set shamefully-hoist to false for better dependency isolation
        pnpm config set shamefully-hoist false 2>/dev/null || true
        
        # Set auto-install-peers to true for better compatibility
        pnpm config set auto-install-peers true 2>/dev/null || true
        
        print_success "pnpm configuration completed"
    else
        print_warning "pnpm not found in PATH for configuration"
    fi
}

# Function to verify pnpm installation
verify_installation() {
    print_info "Verifying pnpm installation..."
    
    if [[ "$DRY_RUN" == false ]]; then
        # Try to run pnpm
        if command -v pnpm &> /dev/null; then
            local pnpm_version
            pnpm_version=$(pnpm --version 2>/dev/null || echo "")
            
            if [[ -n "$pnpm_version" ]]; then
                print_success "pnpm installation verified. Version: $pnpm_version"
                
                # Show installation details
                local install_location
                install_location=$(which pnpm 2>/dev/null || echo "unknown")
                print_info "pnpm location: $install_location"
                
                return 0
            fi
        fi
        
        print_error "pnpm installation verification failed"
        print_info "You may need to restart your shell or update your PATH"
        return 1
    else
        echo "[DRY-RUN] Would verify pnpm installation"
    fi
}

# Function to show post-installation instructions
show_post_install_instructions() {
    echo
    print_info "=== Post-Installation Instructions ==="
    echo
    
    case "$INSTALL_METHOD" in
        "corepack")
            cat << EOF
pnpm is now available via corepack. Usage examples:

Basic commands:
  pnpm install                # Install dependencies
  pnpm add <package>          # Add a package
  pnpm remove <package>       # Remove a package
  pnpm run <script>           # Run a script

Workspace commands:
  pnpm -r install             # Install in all workspace packages
  pnpm -r run build           # Run build in all packages

Configuration:
  pnpm config list            # Show current config
  pnpm config set <key> <val> # Set config value

Corepack benefits:
  ✓ Automatic version management
  ✓ No global installation needed
  ✓ Project-specific pnpm versions via package.json
EOF
            ;;
        "npm")
            cat << EOF
pnpm is now installed globally via npm. Usage examples:

Basic commands:
  pnpm install                # Install dependencies
  pnpm add <package>          # Add a package
  pnpm remove <package>       # Remove a package
  pnpm run <script>           # Run a script

Global commands:
  pnpm add -g <package>       # Install package globally
  pnpm list -g                # List global packages

Performance features:
  ✓ Hard links for fast installs
  ✓ Content-addressable storage
  ✓ Strict node_modules structure
EOF
            ;;
        "standalone")
            cat << EOF
pnpm is now installed as a standalone binary. Usage examples:

Basic commands:
  pnpm install                # Install dependencies
  pnpm add <package>          # Add a package
  pnpm remove <package>       # Remove a package
  pnpm run <script>           # Run a script

Shell integration:
  Add to ~/.bashrc or ~/.zshrc:
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="\$PNPM_HOME:\$PATH"

Update pnpm:
  pnpm add -g pnpm            # Self-update
EOF
            ;;
    esac
    
    echo
    print_info "Migration from npm/yarn:"
    cat << EOF
  pnpm import                 # Import from package-lock.json/yarn.lock
  pnpm install-completion     # Add shell completion

Useful aliases:
  alias pn='pnpm'
  alias pni='pnpm install'
  alias pna='pnpm add'
  alias pnr='pnpm run'
EOF
    
    echo
    print_success "pnpm installation completed successfully! 🚀"
}

# Main installation function
main() {
    show_script_header "pnpm Installation Script"
    
    # Check system compatibility
    check_ubuntu_system
    
    # Check Node.js prerequisites
    check_nodejs_prerequisites
    
    # Set default version if not specified
    if [[ -z "$PNPM_VERSION" ]]; then
        PNPM_VERSION="$PNPM_DEFAULT_VERSION"
    fi
    
    print_info "pnpm version to install: $PNPM_VERSION"
    
    # Detect existing installations
    detect_existing_pnpm
    
    # Determine installation method
    determine_install_method
    
    print_info "Installation method: $INSTALL_METHOD"
    
    # Confirm installation
    if ! confirm_action "Proceed with pnpm installation?" "Y"; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Install pnpm based on method
    case "$INSTALL_METHOD" in
        "corepack")
            install_pnpm_corepack
            ;;
        "npm")
            install_pnpm_npm
            ;;
        "standalone")
            install_pnpm_standalone
            ;;
        *)
            print_error "Invalid installation method: $INSTALL_METHOD"
            exit 1
            ;;
    esac
    
    # Setup pnpm configuration
    setup_pnpm_config
    
    # Verify installation
    verify_installation
    
    # Show post-installation instructions
    show_post_install_instructions
}

# Run main function
main "$@"
