#!/bin/bash
#
# Script: software/nvm/global-packages.sh
# Description: Install essential global Node.js packages
# Usage: ./software/nvm/global-packages.sh [OPTIONS]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/_helpers/common.sh"
source "${SCRIPT_DIR}/_helpers/cli.sh"

# Script configuration
# PNPM is always installed first with npm, then used for the rest
readonly DEFAULT_PACKAGES=(
    "puppeteer"
    "@anthropic-ai/claude-code"
)

# Additional useful packages that can be installed
readonly OPTIONAL_PACKAGES=(
    "npm-check-updates"
    "yarn"
    "typescript"
    "ts-node"
    "nodemon"
    "pm2"
    "vercel"
    "netlify-cli"
    "firebase-tools"
    "eslint"
    "prettier"
)

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Install essential global Node.js packages using npm or pnpm.

OPTIONS:
    --packages=LIST  Comma-separated list of packages to install
    --all            Install all packages (default + optional)
    --list           List available packages without installing
    --use-pnpm       Use pnpm instead of npm (default behavior)
    --use-npm        Use npm only, skip pnpm installation
    --verbose        Enable verbose output
    --dry-run        Show what would be installed without executing
    -h, --help       Show this help message

DEFAULT PACKAGES:
    - pnpm (always installed first with npm)
$(for pkg in "${DEFAULT_PACKAGES[@]}"; do echo "    - $pkg"; done)

OPTIONAL PACKAGES:
$(for pkg in "${OPTIONAL_PACKAGES[@]}"; do echo "    - $pkg"; done)

EXAMPLES:
    $0                                    # Install pnpm + default packages
    $0 --all                              # Install pnpm + all packages
    $0 --packages="typescript,eslint"    # Install pnpm + specific packages
    $0 --use-npm                          # Use npm only (skip pnpm)

NOTES:
    - Requires Node.js and npm to be installed (via NVM)
    - pnpm is installed first with npm, then used for other packages
    - Global packages are installed for the current Node.js version
    - Use 'nvm use <version>' to switch Node.js versions before running

EOF
}

# Parse command line arguments
PACKAGES_TO_INSTALL=()
USE_PNPM=true  # Default to using pnpm
INSTALL_ALL=false
LIST_ONLY=false
VERBOSE=false
DRY_RUN=false
CUSTOM_PACKAGES=""
SKIP_PNPM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --packages=*)
            CUSTOM_PACKAGES="${1#*=}"
            shift
            ;;
        --all)
            INSTALL_ALL=true
            shift
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        --use-pnpm)
            USE_PNPM=true
            shift
            ;;
        --use-npm)
            USE_PNPM=false
            SKIP_PNPM=true
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

# Function to check if NVM and Node.js are available
check_node_environment() {
    print_info "Checking Node.js environment..."
    
    # Check if NVM is loaded
    if ! type nvm &>/dev/null; then
        print_warning "NVM is not loaded. Attempting to load it..."
        
        # Try to load NVM
        export NVM_DIR="${HOME}/.nvm"
        if [[ -s "$NVM_DIR/nvm.sh" ]]; then
            # Disable strict mode for NVM
            set +u
            source "$NVM_DIR/nvm.sh"
            set -u
            
            if type nvm &>/dev/null; then
                print_success "NVM loaded successfully"
            else
                print_error "Failed to load NVM. Please install NVM first using: ./software/nvm/install.sh"
                exit 1
            fi
        else
            print_error "NVM not found. Please install NVM first using: ./software/nvm/install.sh"
            exit 1
        fi
    fi
    
    # Check if Node.js is installed
    if ! command -v node &>/dev/null; then
        print_error "Node.js is not installed. Please install it using: nvm install node"
        exit 1
    fi
    
    local node_version=$(node --version)
    local npm_version=$(npm --version)
    
    print_success "Node.js environment ready"
    print_info "  Node.js version: $node_version"
    print_info "  NPM version: $npm_version"
    
    # Show current NVM version
    set +u
    local current_nvm=$(nvm current 2>/dev/null || echo "unknown")
    set -u
    print_info "  Current NVM version: $current_nvm"
}

# Function to list available packages
list_packages() {
    echo
    print_info "=== Available Global Packages ==="
    echo
    echo "Always installed first:"
    echo "  • pnpm (installed with npm, then used for other packages)"
    echo
    echo "Default packages (installed with pnpm):"
    for pkg in "${DEFAULT_PACKAGES[@]}"; do
        echo "  • $pkg"
    done
    echo
    echo "Optional packages (use --all to include):"
    for pkg in "${OPTIONAL_PACKAGES[@]}"; do
        echo "  • $pkg"
    done
    echo
}

# Function to determine which packages to install
determine_packages() {
    if [[ -n "$CUSTOM_PACKAGES" ]]; then
        # Parse custom packages list
        IFS=',' read -ra PACKAGES_TO_INSTALL <<< "$CUSTOM_PACKAGES"
        print_info "Installing custom package list"
    elif [[ "$INSTALL_ALL" == true ]]; then
        # Install all packages
        PACKAGES_TO_INSTALL=("${DEFAULT_PACKAGES[@]}" "${OPTIONAL_PACKAGES[@]}")
        print_info "Installing all packages (default + optional)"
    else
        # Install default packages only
        PACKAGES_TO_INSTALL=("${DEFAULT_PACKAGES[@]}")
        print_info "Installing default packages"
    fi
}

# Function to install pnpm first (always done unless --use-npm specified)
install_pnpm_first() {
    if [[ "$SKIP_PNPM" == true ]]; then
        print_info "Skipping pnpm installation (using npm only)"
        return 0
    fi
    
    print_info "=== Installing pnpm (Step 1/2) ==="
    print_info "Installing pnpm with npm first, then using pnpm for other packages..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install: pnpm (using npm install -g pnpm)"
        return 0
    fi
    
    if npm install -g pnpm; then
        print_success "✓ pnpm installed successfully"
        
        # Verify pnpm is available
        if command -v pnpm &>/dev/null; then
            local pnpm_version=$(pnpm --version)
            print_success "pnpm version $pnpm_version is now available"
        else
            print_warning "pnpm installed but not found in PATH"
        fi
    else
        print_error "Failed to install pnpm"
        print_info "Falling back to npm for package installation"
        USE_PNPM=false
    fi
}

# Function to install a single package
install_package() {
    local package="$1"
    local installer="${2:-npm}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install: $package (using $installer)"
        return 0
    fi
    
    print_info "Installing $package..."
    
    local install_cmd
    if [[ "$installer" == "pnpm" ]]; then
        install_cmd="pnpm add -g"
    else
        install_cmd="npm install -g"
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        $install_cmd "$package"
    else
        $install_cmd "$package" &>/dev/null
    fi
    
    if [[ $? -eq 0 ]]; then
        print_success "✓ $package installed"
        return 0
    else
        print_warning "✗ Failed to install $package"
        return 1
    fi
}

# Function to install all packages
install_packages() {
    if [[ ${#PACKAGES_TO_INSTALL[@]} -eq 0 ]]; then
        print_info "No additional packages to install"
        return 0
    fi
    
    local installer="npm"
    
    if [[ "$USE_PNPM" == true ]] && [[ "$SKIP_PNPM" == false ]] && command -v pnpm &>/dev/null; then
        installer="pnpm"
        print_info "=== Installing Packages with pnpm (Step 2/2) ==="
    else
        print_info "=== Installing Packages with npm ==="
    fi
    
    print_info "Using $installer for package installation"
    echo
    
    local success_count=0
    local fail_count=0
    
    for package in "${PACKAGES_TO_INSTALL[@]}"; do
        if install_package "$package" "$installer"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    echo
    print_info "=== Installation Summary ==="
    if [[ "$SKIP_PNPM" == false ]]; then
        print_success "pnpm: installed with npm"
    fi
    print_success "Other packages: $success_count installed successfully"
    if [[ $fail_count -gt 0 ]]; then
        print_warning "Failed packages: $fail_count"
    fi
}

# Function to show installed global packages
show_installed_packages() {
    if [[ "$DRY_RUN" == false ]]; then
        echo
        print_info "=== Currently Installed Global Packages ==="
        
        if [[ "$USE_PNPM" == true ]] && command -v pnpm &>/dev/null; then
            pnpm list -g --depth=0 2>/dev/null | tail -n +2 || true
        else
            npm list -g --depth=0 2>/dev/null | tail -n +2 || true
        fi
    fi
}

# Function to verify specific package installation
verify_package_installation() {
    local package="$1"
    local binary="${2:-}"
    
    # If no binary name provided, try to guess it from package name
    if [[ -z "$binary" ]]; then
        # Handle scoped packages
        if [[ "$package" == @*/* ]]; then
            binary=$(echo "$package" | sed 's/@.*\///')
        else
            binary="$package"
        fi
    fi
    
    if command -v "$binary" &>/dev/null; then
        local version=$("$binary" --version 2>/dev/null || echo "unknown")
        print_success "✓ $package is available (version: $version)"
        return 0
    else
        print_warning "⚠ $package installed but binary '$binary' not found in PATH"
        return 1
    fi
}

# Function to verify installations
verify_installations() {
    if [[ "$DRY_RUN" == false ]]; then
        echo
        print_info "=== Verifying Package Installations ==="
        
        # Check specific important packages
        if [[ " ${PACKAGES_TO_INSTALL[@]} " =~ " pnpm " ]]; then
            verify_package_installation "pnpm" "pnpm"
        fi
        
        if [[ " ${PACKAGES_TO_INSTALL[@]} " =~ " @anthropic-ai/claude-code " ]]; then
            verify_package_installation "@anthropic-ai/claude-code" "claude"
        fi
        
        if [[ " ${PACKAGES_TO_INSTALL[@]} " =~ " puppeteer " ]]; then
            # Puppeteer doesn't have a CLI binary, just check if it's in the list
            if npm list -g puppeteer --depth=0 &>/dev/null; then
                print_success "✓ puppeteer is installed (library package)"
            fi
        fi
    fi
}

# Main function
main() {
    show_script_header "Global Node.js Packages Installer"
    
    # Check if just listing packages
    if [[ "$LIST_ONLY" == true ]]; then
        list_packages
        exit 0
    fi
    
    # Check Node.js environment
    check_node_environment
    
    # Determine which packages to install
    determine_packages
    
    if [[ ${#PACKAGES_TO_INSTALL[@]} -eq 0 ]]; then
        print_warning "No packages to install"
        exit 0
    fi
    
    echo
    print_info "Packages to install:"
    for pkg in "${PACKAGES_TO_INSTALL[@]}"; do
        echo "  • $pkg"
    done
    echo
    
    # Confirm installation
    if [[ "$DRY_RUN" == false ]]; then
        if ! confirm_action "Proceed with installation?" "Y"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Install pnpm first if requested
    install_pnpm_first
    
    # Install packages
    install_packages
    
    # Show installed packages
    show_installed_packages
    
    # Verify installations
    verify_installations
    
    echo
    print_success "Global packages installation completed! 🚀"
    echo
    print_info "To update these packages in the future, run:"
    if [[ "$USE_PNPM" == true ]]; then
        echo "  pnpm update -g"
    else
        echo "  npm update -g"
    fi
}

# Run main function
main "$@"