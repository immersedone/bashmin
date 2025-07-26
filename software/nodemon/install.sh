#!/bin/bash
#
# Script: software/nodemon/install.sh
# Description: Install nodemon (Node.js file watcher) globally or locally
# Usage: ./software/nodemon/install.sh [--global|--local] [--version=VERSION] [--verbose] [--dry-run]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/_helpers/common.sh"
source "${SCRIPT_DIR}/_helpers/cli.sh"

# Script configuration
readonly NODEMON_DEFAULT_VERSION="latest"
readonly MIN_NODE_VERSION="14.0.0"

# Parse command line arguments
INSTALL_SCOPE=""
NODEMON_VERSION=""
VERBOSE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --global)
            INSTALL_SCOPE="global"
            shift
            ;;
        --local)
            INSTALL_SCOPE="local"
            shift
            ;;
        --version=*)
            NODEMON_VERSION="${1#*=}"
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

Install nodemon (Node.js file watcher) globally or locally.

OPTIONS:
    --global        Install nodemon globally (accessible system-wide)
    --local         Install nodemon locally in current directory (default)
    --version=VER   Specify nodemon version to install (default: $NODEMON_DEFAULT_VERSION)
    --verbose       Enable verbose output
    --dry-run       Show what would be done without executing
    -h, --help      Show this help message

EXAMPLES:
    $0                              # Interactive prompt for scope
    $0 --global                     # Install globally
    $0 --local                      # Install locally (requires package.json)
    $0 --global --version=3.0.1     # Install specific version globally

NOTES:
    - Global installation requires Node.js and npm to be installed
    - Local installation requires a package.json file in current directory
    - Global installation may require sudo on some systems

EOF
}

# Function to check Node.js and npm prerequisites
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
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed"
        print_info "npm should come with Node.js. Please reinstall Node.js."
        exit 1
    fi
    
    # Check Node.js version
    local node_version
    node_version=$(node --version | sed 's/v//')
    
    if ! version_compare "$node_version" "$MIN_NODE_VERSION"; then
        print_warning "Node.js version $node_version detected"
        print_warning "Minimum recommended version: $MIN_NODE_VERSION"
        if ! confirm_action "Continue with current Node.js version?"; then
            print_info "Please update Node.js and try again"
            exit 1
        fi
    fi
    
    print_success "Node.js $(node --version) and npm $(npm --version) are available"
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

# Function to detect existing nodemon installation
detect_existing_nodemon() {
    local global_installed=false
    local local_installed=false
    
    # Check global installation
    if command -v nodemon &> /dev/null; then
        global_installed=true
        local global_version
        global_version=$(nodemon --version 2>/dev/null || echo "unknown")
        print_warning "nodemon is already installed globally (version: $global_version)"
    fi
    
    # Check local installation (if package.json exists)
    if [[ -f "package.json" ]] && [[ -f "node_modules/.bin/nodemon" ]]; then
        local_installed=true
        local local_version
        local_version=$(./node_modules/.bin/nodemon --version 2>/dev/null || echo "unknown")
        print_warning "nodemon is already installed locally (version: $local_version)"
    fi
    
    # If already installed and same scope, prompt for reinstall
    if [[ "$INSTALL_SCOPE" == "global" && "$global_installed" == true ]]; then
        if ! confirm_action "Reinstall nodemon globally?"; then
            print_info "Skipping nodemon installation"
            exit 0
        fi
    elif [[ "$INSTALL_SCOPE" == "local" && "$local_installed" == true ]]; then
        if ! confirm_action "Reinstall nodemon locally?"; then
            print_info "Skipping nodemon installation"
            exit 0
        fi
    fi
}

# Function to prompt for installation scope
prompt_for_scope() {
    if [[ -n "$INSTALL_SCOPE" ]]; then
        return 0
    fi
    
    local options=("Local (project-specific)" "Global (system-wide)")
    local selection
    
    # Check if we're in a project directory
    if [[ ! -f "package.json" ]]; then
        print_warning "No package.json found in current directory"
        print_info "Local installation requires a Node.js project with package.json"
        
        if confirm_action "Create package.json first?"; then
            create_package_json
        else
            print_info "Defaulting to global installation"
            INSTALL_SCOPE="global"
            return 0
        fi
    fi
    
    selection=$(show_selection_menu "Choose nodemon installation scope" "${options[@]}")
    
    case "$selection" in
        "Local (project-specific)")
            INSTALL_SCOPE="local"
            ;;
        "Global (system-wide)")
            INSTALL_SCOPE="global"
            ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac
}

# Function to create basic package.json
create_package_json() {
    local project_name
    project_name=$(basename "$(pwd)")
    
    print_info "Creating basic package.json..."
    
    local package_json_content='{
  "name": "'$project_name'",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": [],
  "author": "",
  "license": "ISC"
}'
    
    if [[ "$DRY_RUN" == false ]]; then
        echo "$package_json_content" > package.json
        print_success "Created package.json"
    else
        echo "[DRY-RUN] Would create package.json with basic configuration"
    fi
}

# Function to install nodemon globally
install_nodemon_global() {
    local version_flag=""
    
    if [[ "$NODEMON_VERSION" != "latest" ]]; then
        version_flag="@$NODEMON_VERSION"
    fi
    
    print_info "Installing nodemon$version_flag globally..."
    
    # Check if we need sudo for global npm install
    local npm_prefix
    npm_prefix=$(npm config get prefix 2>/dev/null || echo "/usr/local")
    
    local npm_cmd="npm install -g nodemon$version_flag"
    
    # If npm prefix is not writable, suggest using sudo
    if [[ ! -w "$npm_prefix" ]] && [[ $EUID -ne 0 ]]; then
        print_warning "Global npm installation may require elevated privileges"
        if confirm_action "Use sudo for global installation?"; then
            npm_cmd="sudo $npm_cmd"
        else
            print_error "Cannot install globally without write access to $npm_prefix"
            print_info "Consider using --local or configuring npm prefix for your user"
            exit 1
        fi
    fi
    
    execute_command "$npm_cmd" "Installing nodemon globally"
    
    print_success "nodemon installed globally"
}

# Function to install nodemon locally
install_nodemon_local() {
    if [[ ! -f "package.json" ]]; then
        print_error "package.json not found in current directory"
        print_info "Local installation requires a Node.js project"
        exit 1
    fi
    
    local version_flag=""
    local save_flag="--save-dev"
    
    if [[ "$NODEMON_VERSION" != "latest" ]]; then
        version_flag="@$NODEMON_VERSION"
    fi
    
    print_info "Installing nodemon$version_flag locally as dev dependency..."
    
    execute_command "npm install $save_flag nodemon$version_flag" "Installing nodemon locally"
    
    # Add nodemon script to package.json if it doesn't exist
    add_nodemon_scripts
    
    print_success "nodemon installed locally"
}

# Function to add helpful scripts to package.json
add_nodemon_scripts() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would add nodemon scripts to package.json"
        return 0
    fi
    
    print_info "Adding nodemon scripts to package.json..."
    
    # Check if dev script already exists
    if ! grep -q '"dev":' package.json; then
        # Use jq if available, otherwise use sed
        if command -v jq &> /dev/null; then
            local temp_file
            temp_file=$(mktemp)
            jq '.scripts.dev = "nodemon index.js"' package.json > "$temp_file" && mv "$temp_file" package.json
            print_success "Added 'dev' script using nodemon"
        else
            print_info "Consider adding this script to package.json:"
            print_info '  "dev": "nodemon index.js"'
        fi
    else
        print_info "Dev script already exists in package.json"
    fi
}

# Function to verify nodemon installation
verify_installation() {
    print_info "Verifying nodemon installation..."
    
    if [[ "$DRY_RUN" == false ]]; then
        local nodemon_cmd
        local version_output
        
        if [[ "$INSTALL_SCOPE" == "global" ]]; then
            nodemon_cmd="nodemon"
        else
            nodemon_cmd="./node_modules/.bin/nodemon"
        fi
        
        if command -v "$nodemon_cmd" &> /dev/null || [[ -x "$nodemon_cmd" ]]; then
            version_output=$($nodemon_cmd --version 2>/dev/null || echo "")
            
            if [[ -n "$version_output" ]]; then
                print_success "nodemon installation verified. Version: $version_output"
            else
                print_warning "nodemon installed but version check failed"
            fi
        else
            print_error "nodemon installation verification failed"
            return 1
        fi
    else
        echo "[DRY-RUN] Would verify nodemon installation"
    fi
}

# Function to show post-installation instructions
show_post_install_instructions() {
    echo
    print_info "=== Post-Installation Instructions ==="
    echo
    
    if [[ "$INSTALL_SCOPE" == "global" ]]; then
        cat << EOF
nodemon is now available globally. Usage examples:

  nodemon app.js              # Watch and restart on file changes
  nodemon --exec "npm start"  # Execute custom command
  nodemon -e js,json,yaml     # Watch specific file extensions
  nodemon --ignore lib/       # Ignore specific directories

Create a nodemon.json config file for advanced settings:
  {
    "watch": ["src"],
    "ext": "js,json",
    "ignore": ["node_modules", "dist"],
    "exec": "node app.js"
  }
EOF
    else
        cat << EOF
nodemon is installed locally in this project. Usage examples:

  npx nodemon app.js          # Run with npx
  npm run dev                 # If dev script was added
  ./node_modules/.bin/nodemon app.js  # Direct path

Local installation benefits:
  - Version locked to your project
  - Included in package.json dependencies
  - Works consistently across team members

Add to package.json scripts:
  "scripts": {
    "dev": "nodemon app.js",
    "start:dev": "nodemon --exec npm start"
  }
EOF
    fi
    
    echo
    print_success "nodemon installation completed successfully! 🚀"
}

# Main installation function
main() {
    show_script_header "Nodemon Installation Script"
    
    # Check system compatibility
    check_ubuntu_system
    
    # Check Node.js prerequisites
    check_nodejs_prerequisites
    
    # Set default version if not specified
    if [[ -z "$NODEMON_VERSION" ]]; then
        NODEMON_VERSION="$NODEMON_DEFAULT_VERSION"
    fi
    
    print_info "nodemon version to install: $NODEMON_VERSION"
    
    # Prompt for installation scope if not specified
    prompt_for_scope
    
    print_info "Installation scope: $INSTALL_SCOPE"
    
    # Detect existing installations
    detect_existing_nodemon
    
    # Confirm installation
    if ! confirm_action "Proceed with nodemon installation?" "Y"; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Install nodemon based on scope
    case "$INSTALL_SCOPE" in
        "global")
            install_nodemon_global
            ;;
        "local")
            install_nodemon_local
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
