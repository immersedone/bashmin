#!/bin/bash
#
# Script: aliases/install.sh
# Description: Install bash aliases for improved productivity
# Usage: ./install.sh [OPTIONS]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly ALIASES_SOURCE="$SCRIPT_DIR/.bash_aliases"
readonly USER_BASHRC="$HOME/.bashrc"
readonly USER_ALIASES="$HOME/.bash_aliases"
readonly GLOBAL_BASHRC="/etc/bash.bashrc"
readonly GLOBAL_ALIASES="/etc/bash_aliases"
readonly BACKUP_DIR="$HOME/.config/bashmin/backups"

# Configuration variables
INSTALL_SCOPE="user"
FORCE_INSTALL=false
CREATE_BACKUP=true
MERGE_EXISTING=true
ADD_SOURCING=true
VERBOSE=false
DRY_RUN=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --scope)
            INSTALL_SCOPE="$2"
            shift 2
            ;;
        --force)
            FORCE_INSTALL=true
            shift
            ;;
        --no-backup)
            CREATE_BACKUP=false
            shift
            ;;
        --no-merge)
            MERGE_EXISTING=false
            shift
            ;;
        --no-sourcing)
            ADD_SOURCING=false
            shift
            ;;
        --quiet)
            QUIET=true
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

Install bash aliases for improved productivity and system management.

OPTIONS:
    --scope SCOPE           Installation scope: user, system (default: $INSTALL_SCOPE)
    --force                 Overwrite existing aliases file
    --no-backup             Skip creating backup of existing aliases
    --no-merge              Don't merge with existing aliases (replace completely)
    --no-sourcing           Don't add sourcing line to bashrc
    --quiet                 Suppress non-essential output
    --verbose               Enable verbose output
    --dry-run               Show what would be done without executing
    -h, --help              Show this help message

SCOPES:
    user                    Install for current user only (~/.bash_aliases)
    system                  Install system-wide (/etc/bash_aliases) - requires sudo

ALIASES INCLUDED:
    Directory Navigation:
      WWW, LOG_DIR, LOG_NGINX, LOG_APACHE     # Common directories
      DR_NG, DR_AP, DR_PHP                    # Configuration directories
      .., ..., ...., .....                   # Parent directory shortcuts

    Development Tools:
      art, cmp, mig, migF                     # Laravel/PHP shortcuts
      gitst, gitbr, gitc, gitcm               # Git shortcuts
      pmi, pmu, pmaud                         # PNPM/NPM shortcuts

    System Management:
      sysupd, modh, bsrl                      # System maintenance
      apcf, ngcf, aprs, ngrs                  # Web server management
      stackrs, stackrl                       # Multi-service operations

    Productivity:
      ll, dfh, OP_LOG                         # Common command shortcuts

EXAMPLES:
    $0                                        # Install for current user
    $0 --scope system                        # Install system-wide
    $0 --force --no-merge                    # Replace existing aliases
    $0 --dry-run --verbose                   # Preview installation
    $0 --quiet --scope user                  # Silent user installation

POST-INSTALLATION:
    source ~/.bashrc                         # Reload aliases for current session
    # Or start a new terminal session

NOTES:
    - System scope requires sudo privileges
    - Existing aliases are backed up automatically
    - Aliases are merged with existing ones by default
    - Self-update functionality available via self-update.sh

EOF
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$QUIET" == false ]]; then
        print_info "Checking prerequisites..."
    fi
    
    # Check if aliases source file exists
    if [[ ! -f "$ALIASES_SOURCE" ]]; then
        print_error "Aliases source file not found: $ALIASES_SOURCE"
        exit 1
    fi
    
    # Check sudo privileges for system scope
    if [[ "$INSTALL_SCOPE" == "system" ]]; then
        if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
            print_error "System scope installation requires sudo privileges"
            exit 1
        fi
    fi
    
    # Create backup directory if needed
    if [[ "$CREATE_BACKUP" == true && "$DRY_RUN" == false ]]; then
        if [[ ! -d "$BACKUP_DIR" ]]; then
            mkdir -p "$BACKUP_DIR" 2>/dev/null || {
                print_warning "Cannot create backup directory: $BACKUP_DIR"
                CREATE_BACKUP=false
            }
        fi
    fi
    
    if [[ "$QUIET" == false ]]; then
        print_success "Prerequisites check completed"
    fi
}

# Function to create backup
create_backup() {
    local target_file="$1"
    
    if [[ "$CREATE_BACKUP" == false || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    if [[ ! -f "$target_file" ]]; then
        return 0
    fi
    
    local backup_file="$BACKUP_DIR/$(basename "$target_file").$(date +%Y%m%d_%H%M%S)"
    
    if cp "$target_file" "$backup_file" 2>/dev/null; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Backup created: $backup_file"
        fi
    else
        print_warning "Failed to create backup of $target_file"
    fi
}

# Function to check if aliases are already sourced
aliases_sourced() {
    local bashrc_file="$1"
    local aliases_file="$2"
    
    if [[ ! -f "$bashrc_file" ]]; then
        return 1
    fi
    
    # Check for various sourcing patterns
    grep -q "source.*$(basename "$aliases_file")" "$bashrc_file" 2>/dev/null || \
    grep -q "\. .*$(basename "$aliases_file")" "$bashrc_file" 2>/dev/null || \
    grep -q "source.*$aliases_file" "$bashrc_file" 2>/dev/null || \
    grep -q "\. .*$aliases_file" "$bashrc_file" 2>/dev/null
}

# Function to add sourcing to bashrc
add_sourcing_to_bashrc() {
    local bashrc_file="$1"
    local aliases_file="$2"
    
    if [[ "$ADD_SOURCING" == false ]]; then
        return 0
    fi
    
    if aliases_sourced "$bashrc_file" "$aliases_file"; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Aliases already sourced in $bashrc_file"
        fi
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would add sourcing line to $bashrc_file"
        return 0
    fi
    
    local sourcing_block="
# Source bash aliases (added by bashmin aliases installer)
if [ -f \"$aliases_file\" ]; then
    . \"$aliases_file\"
fi
"
    
    # Add sourcing to bashrc
    if [[ "$INSTALL_SCOPE" == "system" ]]; then
        echo "$sourcing_block" | sudo tee -a "$bashrc_file" > /dev/null
    else
        echo "$sourcing_block" >> "$bashrc_file"
    fi
    
    if [[ "$QUIET" == false ]]; then
        print_success "Added sourcing line to $bashrc_file"
    fi
}

# Function to merge aliases
merge_aliases() {
    local existing_file="$1"
    local new_file="$2"
    local output_file="$3"
    
    local temp_file=$(mktemp)
    
    # Start with header
    cat > "$temp_file" << 'EOF'
# Bash Aliases Configuration
# Managed by bashmin aliases installer
# Last updated: DATE_PLACEHOLDER

EOF
    
    # Replace date placeholder
    sed -i "s/DATE_PLACEHOLDER/$(date)/" "$temp_file"
    
    if [[ -f "$existing_file" && "$MERGE_EXISTING" == true ]]; then
        # Add existing aliases (excluding our managed section)
        echo "# === EXISTING ALIASES ===" >> "$temp_file"
        grep -v "^# Managed by bashmin" "$existing_file" | \
        grep -v "^# Last updated:" | \
        grep -v "^# Bash Aliases Configuration" | \
        grep -v "^# === BASHMIN ALIASES ===" | \
        grep -v "^# === EXISTING ALIASES ===" >> "$temp_file" 2>/dev/null || true
        echo "" >> "$temp_file"
    fi
    
    # Add new aliases
    echo "# === BASHMIN ALIASES ===" >> "$temp_file"
    cat "$new_file" >> "$temp_file"
    
    mv "$temp_file" "$output_file"
}

# Function to install aliases for user scope
install_user_aliases() {
    if [[ "$QUIET" == false ]]; then
        print_info "Installing aliases for user: $(whoami)"
    fi
    
    local target_aliases="$USER_ALIASES"
    local target_bashrc="$USER_BASHRC"
    
    # Create backup
    create_backup "$target_aliases"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install aliases to: $target_aliases"
        echo "[DRY-RUN] Would update bashrc: $target_bashrc"
        return 0
    fi
    
    # Install aliases
    if [[ "$MERGE_EXISTING" == true && -f "$target_aliases" ]]; then
        local temp_merged=$(mktemp)
        merge_aliases "$target_aliases" "$ALIASES_SOURCE" "$temp_merged"
        mv "$temp_merged" "$target_aliases"
    else
        cp "$ALIASES_SOURCE" "$target_aliases"
    fi
    
    # Set permissions
    chmod 644 "$target_aliases"
    
    # Add sourcing to bashrc
    add_sourcing_to_bashrc "$target_bashrc" "$target_aliases"
    
    if [[ "$QUIET" == false ]]; then
        print_success "User aliases installed successfully"
    fi
}

# Function to install aliases for system scope
install_system_aliases() {
    if [[ "$QUIET" == false ]]; then
        print_info "Installing aliases system-wide"
    fi
    
    local target_aliases="$GLOBAL_ALIASES"
    local target_bashrc="$GLOBAL_BASHRC"
    
    # Create backup
    if [[ -f "$target_aliases" ]]; then
        create_backup "$target_aliases"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install aliases to: $target_aliases"
        echo "[DRY-RUN] Would update bashrc: $target_bashrc"
        return 0
    fi
    
    # Install aliases
    if [[ "$MERGE_EXISTING" == true && -f "$target_aliases" ]]; then
        local temp_merged=$(mktemp)
        merge_aliases "$target_aliases" "$ALIASES_SOURCE" "$temp_merged"
        sudo mv "$temp_merged" "$target_aliases"
    else
        sudo cp "$ALIASES_SOURCE" "$target_aliases"
    fi
    
    # Set permissions
    sudo chmod 644 "$target_aliases"
    sudo chown root:root "$target_aliases"
    
    # Add sourcing to system bashrc
    add_sourcing_to_bashrc "$target_bashrc" "$target_aliases"
    
    if [[ "$QUIET" == false ]]; then
        print_success "System aliases installed successfully"
    fi
}

# Function to show aliases preview
show_aliases_preview() {
    if [[ "$QUIET" == true ]]; then
        return 0
    fi
    
    print_info "Aliases to be installed:"
    echo "========================"
    
    # Count aliases by category
    local nav_count=$(grep -c "^alias.*cd " "$ALIASES_SOURCE" || echo "0")
    local dev_count=$(grep -c "^alias.*\(art\|cmp\|git\|pnpm\|npm\)" "$ALIASES_SOURCE" || echo "0")
    local sys_count=$(grep -c "^alias.*\(sudo\|service\|systemctl\)" "$ALIASES_SOURCE" || echo "0")
    local util_count=$(grep -c "^alias ll\|^alias \.\.\|^alias dfh" "$ALIASES_SOURCE" || echo "0")
    local total_count=$(grep -c "^alias " "$ALIASES_SOURCE" || echo "0")
    
    echo "  Directory Navigation: $nav_count aliases"
    echo "  Development Tools:    $dev_count aliases"
    echo "  System Management:    $sys_count aliases"
    echo "  Utilities:           $util_count aliases"
    echo "  ────────────────────────────────"
    echo "  Total:               $total_count aliases"
    echo
    
    if [[ "$VERBOSE" == true ]]; then
        echo "Sample aliases:"
        echo "  WWW          → cd /var/www/vhosts"
        echo "  art          → /usr/bin/php8.3 artisan"
        echo "  gitst        → git status"
        echo "  sysupd       → sudo apt update -y && sudo apt upgrade -y"
        echo "  stackrs      → restart apache2, nginx, and php-fpm"
        echo
    fi
}

# Function to show post-installation instructions
show_post_install_instructions() {
    if [[ "$QUIET" == true ]]; then
        return 0
    fi
    
    echo
    print_info "=== Bash Aliases Installation Complete! ==="
    echo
    
    local target_aliases
    local target_bashrc
    
    if [[ "$INSTALL_SCOPE" == "system" ]]; then
        target_aliases="$GLOBAL_ALIASES"
        target_bashrc="$GLOBAL_BASHRC"
    else
        target_aliases="$USER_ALIASES"
        target_bashrc="$USER_BASHRC"
    fi
    
    cat << EOF
Installation Details:
  Scope:           $INSTALL_SCOPE
  Aliases File:    $target_aliases
  Bashrc File:     $target_bashrc
  Backup Created:  $(if [[ "$CREATE_BACKUP" == true ]]; then echo "Yes"; else echo "No"; fi)
  Merged Existing: $(if [[ "$MERGE_EXISTING" == true ]]; then echo "Yes"; else echo "No"; fi)

Activation:
  # Reload aliases in current session
  source ~/.bashrc
  
  # Or start a new terminal session
  # Aliases will be automatically available

Popular Aliases Installed:
  Directory Navigation:
    WWW              → cd /var/www/vhosts
    LOG_NGINX        → cd /var/log/nginx
    DR_NG_STA        → cd /etc/nginx/sites-available
    
  Development:
    art              → php artisan (Laravel)
    gitst            → git status
    gitc             → git checkout
    pmi              → pnpm install
    
  System Management:
    sysupd           → system update
    stackrs          → restart web stack
    apcf/ngcf        → test Apache/Nginx config
    modh             → edit hosts file

Management:
  Update aliases:   $SCRIPT_DIR/self-update.sh
  View all:        alias | grep -E "(WWW|art|git|sys)"
  
Self-Update:
  The self-update script can automatically update your aliases
  when new versions are available in the bashmin repository.

Usage Examples:
  WWW                     # Navigate to web root
  art migrate             # Run Laravel migration
  gitst                   # Check git status
  sysupd                  # Update system packages
  stackrs                 # Restart web services

EOF
    
    print_success "Bash aliases installation completed successfully! 🚀"
    print_info "Run 'source ~/.bashrc' or start a new terminal to use aliases"
}

# Main installation function
main() {
    if [[ "$QUIET" == false ]]; then
        show_script_header "Bash Aliases Installation Script"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show preview
    show_aliases_preview
    
    # Confirm installation
    if [[ "$VERBOSE" == true && "$QUIET" == false && "$DRY_RUN" == false ]]; then
        print_info "Installation summary:"
        print_info "  Scope: $INSTALL_SCOPE"
        print_info "  Force install: $FORCE_INSTALL"
        print_info "  Merge existing: $MERGE_EXISTING"
        print_info "  Create backup: $CREATE_BACKUP"
        
        if ! confirm_action "Proceed with aliases installation?" "Y"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Install based on scope
    case "$INSTALL_SCOPE" in
        user)
            install_user_aliases
            ;;
        system)
            install_system_aliases
            ;;
        *)
            print_error "Invalid installation scope: $INSTALL_SCOPE"
            exit 1
            ;;
    esac
    
    # Show post-installation instructions
    show_post_install_instructions
}

# Run main function
main "$@"