#!/bin/bash
#
# Script: development/cghooks/install.sh
# Description: Install and configure BrainMaestro/composer-git-hooks for PHP/Composer projects
# Usage: ./install.sh [OPTIONS]
# Author: Bashmin Project
# Documentation: https://github.com/BrainMaestro/composer-git-hooks
#

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly PACKAGE_NAME="brainmaestro/composer-git-hooks"
readonly PACKAGE_VERSION="^3.0"
readonly MIN_PHP_VERSION="7.4"
readonly MIN_COMPOSER_VERSION="2.0"

# Configuration variables
INSTALL_GLOBALLY=false         # Install as global composer package
INSTALL_AS_DEV=true            # Install as dev dependency
AUTO_CONFIGURE=true            # Automatically add hooks configuration
WORKING_DIRECTORY=""           # Target directory (default: current)
FORCE_INSTALL=false           # Force installation even if already present
SETUP_SAMPLE_HOOKS=true       # Add sample hook configurations
ENABLE_PRE_COMMIT=true        # Enable pre-commit hook
ENABLE_PRE_PUSH=true          # Enable pre-push hook  
ENABLE_POST_MERGE=false       # Enable post-merge hook
ENABLE_POST_CHECKOUT=false    # Enable post-checkout hook

# Hook commands (can be customized)
PRE_COMMIT_COMMANDS=()
PRE_PUSH_COMMANDS=()
POST_MERGE_COMMANDS=()
POST_CHECKOUT_COMMANDS=()

# Default fallback commands if no .dev/ scripts found
DEFAULT_PRE_COMMIT_COMMANDS=("echo 'Running pre-commit checks...'" "composer run-script phpcs" "composer run-script phpstan")
DEFAULT_PRE_PUSH_COMMANDS=("echo 'Running pre-push checks...'" "composer run-script test")
DEFAULT_POST_MERGE_COMMANDS=("composer install --no-dev")
DEFAULT_POST_CHECKOUT_COMMANDS=("composer install")

# Display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install and configure BrainMaestro/composer-git-hooks for PHP/Composer projects.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run          Show what would be done without executing
    -f, --force            Force installation even if already present
    -g, --global           Install as global composer package
    --production           Install as production dependency (not dev)
    --no-auto-config       Skip automatic hook configuration
    --no-samples           Skip adding sample hook configurations
    --working-dir=DIR      Target directory for installation (default: current)
    --disable-pre-commit   Disable pre-commit hook setup
    --disable-pre-push     Disable pre-push hook setup
    --enable-post-merge    Enable post-merge hook setup
    --enable-post-checkout Enable post-checkout hook setup

EXAMPLES:
    $0                              # Install with default settings
    $0 --global                     # Install globally
    $0 --working-dir=/path/to/proj  # Install in specific directory
    $0 --force --verbose            # Force reinstall with verbose output
    $0 --production --no-samples    # Production install without samples

HOOKS CONFIGURATION:
    The script will automatically configure common Git hooks:
    - pre-commit: Code style and static analysis checks
    - pre-push: Run test suite
    - post-merge: Install dependencies (optional)
    - post-checkout: Install dependencies (optional)

REQUIREMENTS:
    - PHP >= $MIN_PHP_VERSION
    - Composer >= $MIN_COMPOSER_VERSION
    - Git repository (for hook installation)

EOF
}

# Setup hook commands based on .dev/ scripts or defaults
setup_hook_commands() {
    print_info "Setting up hook commands..."
    
    local dev_scripts_dir="$SCRIPT_DIR/.dev"
    local target_dev_dir=".dev"
    
    # Check if we have .dev/ scripts to copy
    if [[ -d "$dev_scripts_dir" ]]; then
        print_info "Found .dev/ scripts in installer directory"
        
        # Create .dev/ directory in target if it doesn't exist
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$target_dev_dir"
        fi
        
        # Copy .dev/ scripts and set up commands
        for hook_script in "$dev_scripts_dir"/*; do
            if [[ -f "$hook_script" ]]; then
                local hook_name=$(basename "$hook_script")
                local target_script="$target_dev_dir/$hook_name"
                
                if [[ "$DRY_RUN" == false ]]; then
                    cp "$hook_script" "$target_script"
                    chmod +x "$target_script"
                    print_success "Copied $hook_name script"
                else
                    echo "[DRY-RUN] Would copy $hook_script to $target_script"
                fi
                
                # Set up hook command to use the .dev/ script
                case "$hook_name" in
                    "pre-commit")
                        if [[ "$ENABLE_PRE_COMMIT" == true ]]; then
                            PRE_COMMIT_COMMANDS=("./.dev/pre-commit")
                        fi
                        ;;
                    "pre-push")
                        if [[ "$ENABLE_PRE_PUSH" == true ]]; then
                            PRE_PUSH_COMMANDS=("./.dev/pre-push")
                        fi
                        ;;
                    "post-merge")
                        if [[ "$ENABLE_POST_MERGE" == true ]]; then
                            POST_MERGE_COMMANDS=("./.dev/post-merge")
                        fi
                        ;;
                    "post-checkout")
                        if [[ "$ENABLE_POST_CHECKOUT" == true ]]; then
                            POST_CHECKOUT_COMMANDS=("./.dev/post-checkout")
                        fi
                        ;;
                esac
            fi
        done
    else
        print_info "No .dev/ scripts found, using default commands"
        
        # Use default commands
        if [[ "$ENABLE_PRE_COMMIT" == true ]]; then
            PRE_COMMIT_COMMANDS=("${DEFAULT_PRE_COMMIT_COMMANDS[@]}")
        fi
        if [[ "$ENABLE_PRE_PUSH" == true ]]; then
            PRE_PUSH_COMMANDS=("${DEFAULT_PRE_PUSH_COMMANDS[@]}")
        fi
        if [[ "$ENABLE_POST_MERGE" == true ]]; then
            POST_MERGE_COMMANDS=("${DEFAULT_POST_MERGE_COMMANDS[@]}")
        fi
        if [[ "$ENABLE_POST_CHECKOUT" == true ]]; then
            POST_CHECKOUT_COMMANDS=("${DEFAULT_POST_CHECKOUT_COMMANDS[@]}")
        fi
    fi
    
    print_success "Hook commands configured"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_INSTALL=true
                shift
                ;;
            -g|--global)
                INSTALL_GLOBALLY=true
                shift
                ;;
            --production)
                INSTALL_AS_DEV=false
                shift
                ;;
            --no-auto-config)
                AUTO_CONFIGURE=false
                shift
                ;;
            --no-samples)
                SETUP_SAMPLE_HOOKS=false
                shift
                ;;
            --working-dir=*)
                WORKING_DIRECTORY="${1#*=}"
                shift
                ;;
            --disable-pre-commit)
                ENABLE_PRE_COMMIT=false
                shift
                ;;
            --disable-pre-push)
                ENABLE_PRE_PUSH=false
                shift
                ;;
            --enable-post-merge)
                ENABLE_POST_MERGE=true
                shift
                ;;
            --enable-post-checkout)
                ENABLE_POST_CHECKOUT=true
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

# Check system requirements
check_requirements() {
    print_info "Checking system requirements..."
    
    # Check if PHP is installed
    if ! command -v php &> /dev/null; then
        print_error "PHP is not installed. Please install PHP >= $MIN_PHP_VERSION"
        exit 1
    fi
    
    # Check PHP version
    local php_version
    php_version=$(php -r "echo PHP_VERSION;" 2>/dev/null || echo "0.0.0")
    if ! printf '%s\n%s\n' "$MIN_PHP_VERSION" "$php_version" | sort -V | head -1 | grep -q "^$MIN_PHP_VERSION"; then
        print_error "PHP version $php_version is too old. Minimum required: $MIN_PHP_VERSION"
        exit 1
    fi
    print_success "PHP version $php_version is compatible"
    
    # Check if Composer is installed
    if ! command -v composer &> /dev/null; then
        print_error "Composer is not installed. Please install Composer >= $MIN_COMPOSER_VERSION"
        exit 1
    fi
    
    # Check Composer version
    local composer_version
    composer_version=$(composer --version --no-ansi 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if ! printf '%s\n%s\n' "$MIN_COMPOSER_VERSION" "$composer_version" | sort -V | head -1 | grep -q "^$MIN_COMPOSER_VERSION"; then
        print_error "Composer version $composer_version is too old. Minimum required: $MIN_COMPOSER_VERSION"
        exit 1
    fi
    print_success "Composer version $composer_version is compatible"
    
    # Check if Git is installed
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed. Git is required for Git hooks functionality"
        exit 1
    fi
    print_success "Git is available"
}

# Determine working directory
setup_working_directory() {
    if [[ -n "$WORKING_DIRECTORY" ]]; then
        if [[ ! -d "$WORKING_DIRECTORY" ]]; then
            print_error "Specified working directory does not exist: $WORKING_DIRECTORY"
            exit 1
        fi
        cd "$WORKING_DIRECTORY"
        print_info "Using working directory: $WORKING_DIRECTORY"
    else
        WORKING_DIRECTORY="$(pwd)"
        print_info "Using current directory: $WORKING_DIRECTORY"
    fi
    
    # For non-global installations, check if we're in a PHP project
    if [[ "$INSTALL_GLOBALLY" == false ]]; then
        if [[ ! -f "composer.json" ]]; then
            print_error "No composer.json found in $WORKING_DIRECTORY"
            print_error "This doesn't appear to be a PHP/Composer project"
            print_info "Use --global flag to install globally, or navigate to a PHP project directory"
            exit 1
        fi
        print_success "Found composer.json in current directory"
        
        # Check if it's a Git repository
        if [[ ! -d ".git" ]]; then
            print_warning "No .git directory found. Git hooks won't work without a Git repository"
            if ! confirm_action "Continue anyway?"; then
                exit 1
            fi
        fi
    fi
}

# Check if package is already installed
check_existing_installation() {
    print_info "Checking for existing installation..."
    
    local is_installed=false
    
    if [[ "$INSTALL_GLOBALLY" == true ]]; then
        if composer global show "$PACKAGE_NAME" &>/dev/null; then
            is_installed=true
            print_warning "Package $PACKAGE_NAME is already installed globally"
        fi
    else
        if [[ -f "composer.json" ]] && composer show "$PACKAGE_NAME" &>/dev/null; then
            is_installed=true
            print_warning "Package $PACKAGE_NAME is already installed in this project"
        fi
    fi
    
    if [[ "$is_installed" == true ]]; then
        if [[ "$FORCE_INSTALL" == true ]]; then
            print_info "Force installation enabled, proceeding anyway"
        else
            print_info "Use --force flag to reinstall"
            exit 0
        fi
    fi
}

# Install the composer-git-hooks package
install_package() {
    print_info "Installing $PACKAGE_NAME..."
    
    local install_cmd="composer"
    local install_args=()
    
    if [[ "$INSTALL_GLOBALLY" == true ]]; then
        install_args+=("global")
    fi
    
    install_args+=("require")
    
    if [[ "$INSTALL_AS_DEV" == true ]] && [[ "$INSTALL_GLOBALLY" == false ]]; then
        install_args+=("--dev")
    fi
    
    install_args+=("$PACKAGE_NAME:$PACKAGE_VERSION")
    
    local full_command="$install_cmd ${install_args[*]}"
    
    if execute_command "$full_command" "Installing composer-git-hooks package"; then
        print_success "Package installed successfully"
    else
        print_error "Failed to install package"
        exit 1
    fi
}

# Create or update composer.json hooks configuration (merge with existing)
configure_composer_hooks() {
    if [[ "$AUTO_CONFIGURE" == false ]] || [[ "$INSTALL_GLOBALLY" == true ]]; then
        return 0
    fi
    
    print_info "Configuring Git hooks in composer.json..."
    
    local composer_file="composer.json"
    local backup_file="composer.json.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup
    if [[ "$DRY_RUN" == false ]]; then
        cp "$composer_file" "$backup_file"
        print_info "Created backup: $backup_file"
    fi
    
    # Use Python to intelligently merge hooks configuration
    if [[ "$DRY_RUN" == false ]]; then
        local temp_script
        temp_script=$(mktemp)
        
        cat << 'EOF' > "$temp_script"
import json
import sys

def merge_hooks_config():
    try:
        # Read existing composer.json
        with open('composer.json', 'r') as f:
            data = json.load(f)
        
        # Ensure 'extra' section exists
        if 'extra' not in data:
            data['extra'] = {}
        
        # Ensure 'hooks' section exists
        if 'hooks' not in data['extra']:
            data['extra']['hooks'] = {}
        
        existing_hooks = data['extra']['hooks']
        
        # New hooks to add/merge
        new_hooks = {}
EOF

        # Add enabled hooks to the Python script
        if [[ "$ENABLE_PRE_COMMIT" == true ]] && [[ ${#PRE_COMMIT_COMMANDS[@]} -gt 0 ]]; then
            echo "        new_hooks['pre-commit'] = [$(printf '"%s",' "${PRE_COMMIT_COMMANDS[@]}" | sed 's/,$//')]" >> "$temp_script"
        fi
        if [[ "$ENABLE_PRE_PUSH" == true ]] && [[ ${#PRE_PUSH_COMMANDS[@]} -gt 0 ]]; then
            echo "        new_hooks['pre-push'] = [$(printf '"%s",' "${PRE_PUSH_COMMANDS[@]}" | sed 's/,$//')]" >> "$temp_script"
        fi
        if [[ "$ENABLE_POST_MERGE" == true ]] && [[ ${#POST_MERGE_COMMANDS[@]} -gt 0 ]]; then
            echo "        new_hooks['post-merge'] = [$(printf '"%s",' "${POST_MERGE_COMMANDS[@]}" | sed 's/,$//')]" >> "$temp_script"
        fi
        if [[ "$ENABLE_POST_CHECKOUT" == true ]] && [[ ${#POST_CHECKOUT_COMMANDS[@]} -gt 0 ]]; then
            echo "        new_hooks['post-checkout'] = [$(printf '"%s",' "${POST_CHECKOUT_COMMANDS[@]}" | sed 's/,$//')]" >> "$temp_script"
        fi
        
        cat << 'EOF' >> "$temp_script"
        
        # Merge hooks intelligently
        for hook_name, hook_commands in new_hooks.items():
            if hook_name in existing_hooks:
                # Check if existing commands are different
                if existing_hooks[hook_name] != hook_commands:
                    print(f"Hook '{hook_name}' already exists with different commands:")
                    print(f"  Existing: {existing_hooks[hook_name]}")
                    print(f"  New: {hook_commands}")
                    
                    # For now, we'll merge by appending new commands that don't already exist
                    existing_commands = existing_hooks[hook_name] if isinstance(existing_hooks[hook_name], list) else [existing_hooks[hook_name]]
                    
                    for cmd in hook_commands:
                        if cmd not in existing_commands:
                            existing_commands.append(cmd)
                    
                    data['extra']['hooks'][hook_name] = existing_commands
                    print(f"  Merged: {existing_commands}")
                else:
                    print(f"Hook '{hook_name}' already configured with same commands")
            else:
                # Add new hook
                data['extra']['hooks'][hook_name] = hook_commands
                print(f"Added new hook '{hook_name}': {hook_commands}")
        
        # Write updated composer.json
        with open('composer.json', 'w') as f:
            json.dump(data, f, indent=4)
            f.write('\n')  # Add final newline
        
        print("Hooks configuration updated successfully")
        return True
        
    except Exception as e:
        print(f"Error updating composer.json: {e}", file=sys.stderr)
        return False

if __name__ == "__main__":
    success = merge_hooks_config()
    sys.exit(0 if success else 1)
EOF

        if python3 "$temp_script"; then
            print_success "Updated composer.json with hooks configuration"
        else
            print_error "Failed to update composer.json"
            print_info "Restoring backup..."
            cp "$backup_file" "$composer_file"
            exit 1
        fi
        
        rm -f "$temp_script"
    else
        echo "[DRY-RUN] Would intelligently merge hooks configuration into composer.json"
    fi
}

# Install Git hooks
install_git_hooks() {
    if [[ "$INSTALL_GLOBALLY" == true ]] || [[ ! -d ".git" ]]; then
        return 0
    fi
    
    print_info "Installing Git hooks..."
    
    local install_hooks_cmd="composer run-script cghooks:add"
    
    if execute_command "$install_hooks_cmd" "Installing Git hooks via composer-git-hooks"; then
        print_success "Git hooks installed successfully"
    else
        print_warning "Failed to install Git hooks automatically"
        print_info "You can install them manually by running: composer run-script cghooks:add"
    fi
}

# Add sample scripts section to composer.json (merge with existing)
add_sample_scripts() {
    if [[ "$SETUP_SAMPLE_HOOKS" == false ]] || [[ "$INSTALL_GLOBALLY" == true ]] || [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    print_info "Checking for sample script commands to add to composer.json..."
    
    local scripts_to_add=()
    local scripts_info=()
    
    # Check for common PHP development scripts and suggest them if missing
    if ! grep -q '"phpcs"' composer.json; then
        scripts_to_add+=("phpcs")
        scripts_info+=("phpcs:vendor/bin/phpcs --standard=PSR12 src/")
    fi
    
    if ! grep -q '"phpstan"' composer.json; then
        scripts_to_add+=("phpstan")
        scripts_info+=("phpstan:vendor/bin/phpstan analyse src/")
    fi
    
    if ! grep -q '"test"' composer.json; then
        scripts_to_add+=("test")
        scripts_info+=("test:vendor/bin/phpunit")
    fi
    
    if ! grep -q '"pint"' composer.json; then
        scripts_to_add+=("pint")
        scripts_info+=("pint:vendor/bin/pint")
    fi
    
    if ! grep -q '"pest"' composer.json; then
        scripts_to_add+=("pest")
        scripts_info+=("pest:vendor/bin/pest")
    fi
    
    if [[ ${#scripts_to_add[@]} -gt 0 ]]; then
        print_info "Suggested scripts to add to your composer.json:"
        printf "\n"
        print_warning "Add these to your composer.json 'scripts' section:"
        printf "\n"
        
        for script_info in "${scripts_info[@]}"; do
            local script_name="${script_info%:*}"
            local script_command="${script_info#*:}"
            printf "    \"%s\": \"%s\",\n" "$script_name" "$script_command"
        done
        
        printf "\n"
        print_info "These scripts are referenced by the default Git hooks"
        
        # Optionally auto-add them
        if confirm_action "Would you like me to add these scripts automatically?"; then
            add_scripts_to_composer "${scripts_info[@]}"
        fi
    else
        print_success "All expected scripts are already present in composer.json"
    fi
}

# Add scripts to composer.json
add_scripts_to_composer() {
    local scripts_info=("$@")
    
    print_info "Adding scripts to composer.json..."
    
    if [[ "$DRY_RUN" == false ]]; then
        local temp_script
        temp_script=$(mktemp)
        
        cat << 'EOF' > "$temp_script"
import json
import sys

def add_scripts():
    try:
        # Read existing composer.json
        with open('composer.json', 'r') as f:
            data = json.load(f)
        
        # Ensure 'scripts' section exists
        if 'scripts' not in data:
            data['scripts'] = {}
        
        # Scripts to add
        scripts_to_add = {
EOF

        # Add each script to the Python script
        for script_info in "${scripts_info[@]}"; do
            local script_name="${script_info%:*}"
            local script_command="${script_info#*:}"
            echo "            \"$script_name\": \"$script_command\"," >> "$temp_script"
        done
        
        cat << 'EOF' >> "$temp_script"
        }
        
        # Add new scripts (don't overwrite existing)
        for script_name, script_command in scripts_to_add.items():
            if script_name not in data['scripts']:
                data['scripts'][script_name] = script_command
                print(f"Added script: {script_name}")
            else:
                print(f"Script '{script_name}' already exists, skipping")
        
        # Write updated composer.json
        with open('composer.json', 'w') as f:
            json.dump(data, f, indent=4)
            f.write('\n')  # Add final newline
        
        print("Scripts added successfully")
        return True
        
    except Exception as e:
        print(f"Error updating composer.json: {e}", file=sys.stderr)
        return False

if __name__ == "__main__":
    success = add_scripts()
    sys.exit(0 if success else 1)
EOF

        if python3 "$temp_script"; then
            print_success "Added sample scripts to composer.json"
        else
            print_error "Failed to add scripts to composer.json"
        fi
        
        rm -f "$temp_script"
    else
        echo "[DRY-RUN] Would add sample scripts to composer.json"
    fi
}

# Display post-installation information
show_post_install_info() {
    print_success "Composer Git Hooks installation completed!"
    echo
    print_info "Next steps:"
    echo
    
    if [[ "$INSTALL_GLOBALLY" == true ]]; then
        echo "  1. Navigate to a PHP/Composer project directory"
        echo "  2. Run: composer run-script cghooks:add"
        echo "  3. Configure hooks in composer.json under 'extra.hooks'"
    else
        echo "  1. Git hooks have been configured in composer.json"
        if [[ -d ".git" ]]; then
            echo "  2. Git hooks have been installed in .git/hooks/"
        else
            echo "  2. Initialize Git repository: git init"
            echo "  3. Install hooks: composer run-script cghooks:add"
        fi
        
        if [[ -d ".dev" ]]; then
            echo "  3. Custom .dev/ hook scripts have been installed"
            echo "     - Edit .dev/ scripts to customize hook behavior"
        fi
        
        echo "  4. Test hooks: git add . && git commit -m 'test'"
    fi
    
    echo
    print_info "Available commands:"
    echo "  composer run-script cghooks:add     # Install hooks"
    echo "  composer run-script cghooks:update  # Update existing hooks"
    echo "  composer run-script cghooks:remove  # Remove hooks"
    echo "  composer run-script cghooks:list    # List configured hooks"
    echo
    
    if [[ -d ".dev" ]]; then
        print_info "Custom hook scripts (edit these to customize behavior):"
        for script in .dev/*; do
            if [[ -f "$script" ]]; then
                echo "  $script"
            fi
        done
        echo
    fi
    
    print_info "Documentation: https://github.com/BrainMaestro/composer-git-hooks"
}

# Main execution function
main() {
    print_info "Starting Composer Git Hooks installation..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check system requirements
    check_requirements
    
    # Setup working directory
    setup_working_directory
    
    # Setup hook commands (must be done after working directory is set)
    setup_hook_commands
    
    # Check for existing installation
    check_existing_installation
    
    # Install the package
    install_package
    
    # Configure hooks in composer.json
    configure_composer_hooks
    
    # Install Git hooks
    install_git_hooks
    
    # Add sample scripts
    add_sample_scripts
    
    # Show post-installation information
    show_post_install_info
    
    print_success "Installation completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
