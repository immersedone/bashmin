#!/bin/bash
#
# Script: aliases/self-update.sh
# Description: Self-update bash aliases from bashmin repository
# Usage: ./self-update.sh [OPTIONS]
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
readonly USER_ALIASES="$HOME/.bash_aliases"
readonly GLOBAL_ALIASES="/etc/bash_aliases"
readonly BACKUP_DIR="$HOME/.config/bashmin/backups"
readonly UPDATE_MARKER="$HOME/.config/bashmin/aliases_version"

# Configuration variables
UPDATE_SCOPE="auto"
FORCE_UPDATE=false
CREATE_BACKUP=true
CHECK_ONLY=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --scope)
            UPDATE_SCOPE="$2"
            shift 2
            ;;
        --force)
            FORCE_UPDATE=true
            shift
            ;;
        --no-backup)
            CREATE_BACKUP=false
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
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

Self-update bash aliases from the bashmin repository.

OPTIONS:
    --scope SCOPE           Update scope: auto, user, system (default: $UPDATE_SCOPE)
    --force                 Force update even if no changes detected
    --no-backup             Skip creating backup before update
    --check-only            Only check for updates without applying
    --quiet                 Suppress non-essential output
    --verbose               Enable verbose output
    --dry-run               Show what would be updated without executing
    -h, --help              Show this help message

SCOPES:
    auto                    Detect and update the same scope as currently installed
    user                    Update user aliases (~/.bash_aliases)
    system                  Update system aliases (/etc/bash_aliases) - requires sudo

EXAMPLES:
    $0                                      # Auto-detect and update
    $0 --check-only                        # Check for updates only
    $0 --scope user --verbose              # Update user aliases with details
    $0 --scope system --force              # Force system update
    $0 --dry-run                           # Preview updates

AUTOMATIC UPDATES:
    This script can be run automatically via cron:
    # Daily alias updates
    0 2 * * * /path/to/bashmin/aliases/self-update.sh --quiet

NOTES:
    - Detects installation scope automatically by default
    - Creates backups before applying updates
    - Preserves custom aliases when merging
    - Requires sudo for system scope updates

EOF
}

# Function to detect current installation scope
detect_installation_scope() {
    if [[ -f "$USER_ALIASES" && -f "$GLOBAL_ALIASES" ]]; then
        # Both exist, check which is sourced or more recent
        if [[ "$USER_ALIASES" -nt "$GLOBAL_ALIASES" ]]; then
            echo "user"
        else
            echo "system"
        fi
    elif [[ -f "$USER_ALIASES" ]]; then
        echo "user"
    elif [[ -f "$GLOBAL_ALIASES" ]]; then
        echo "system"
    else
        echo "none"
    fi
}

# Function to get version info from aliases file
get_aliases_version() {
    local aliases_file="$1"
    
    if [[ ! -f "$aliases_file" ]]; then
        echo "0"
        return
    fi
    
    # Try to extract date from header comment
    local version_date
    version_date=$(grep "# Last updated:" "$aliases_file" 2>/dev/null | sed 's/# Last updated: //' || echo "")
    
    if [[ -n "$version_date" ]]; then
        # Convert date to timestamp
        date -d "$version_date" +%s 2>/dev/null || echo "0"
    else
        # Fall back to file modification time
        stat -c %Y "$aliases_file" 2>/dev/null || echo "0"
    fi
}

# Function to get source version
get_source_version() {
    if [[ ! -f "$ALIASES_SOURCE" ]]; then
        echo "0"
        return
    fi
    
    # Get file modification time as version
    stat -c %Y "$ALIASES_SOURCE" 2>/dev/null || echo "0"
}

# Function to check if update is available
check_update_available() {
    local current_file="$1"
    
    local current_version
    local source_version
    
    current_version=$(get_aliases_version "$current_file")
    source_version=$(get_source_version)
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Version comparison:"
        print_info "  Current: $current_version"
        print_info "  Source:  $source_version"
    fi
    
    # Check if source is newer or if files differ
    if [[ "$source_version" -gt "$current_version" ]] || [[ "$FORCE_UPDATE" == true ]]; then
        return 0
    else
        # Also check for content differences
        if ! diff -q "$current_file" "$ALIASES_SOURCE" > /dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
}

# Function to create backup
create_backup() {
    local source_file="$1"
    
    if [[ "$CREATE_BACKUP" == false || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    if [[ ! -f "$source_file" ]]; then
        return 0
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR" 2>/dev/null || {
        print_warning "Cannot create backup directory: $BACKUP_DIR"
        return 1
    }
    
    local backup_file="$BACKUP_DIR/$(basename "$source_file").$(date +%Y%m%d_%H%M%S)"
    
    if cp "$source_file" "$backup_file" 2>/dev/null; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Backup created: $backup_file"
        fi
        return 0
    else
        print_warning "Failed to create backup of $source_file"
        return 1
    fi
}

# Function to merge aliases intelligently
merge_aliases_intelligent() {
    local current_file="$1"
    local source_file="$2"
    local output_file="$3"
    
    local temp_file=$(mktemp)
    
    # Start with updated header
    cat > "$temp_file" << EOF
# Bash Aliases Configuration
# Managed by bashmin aliases installer
# Last updated: $(date)

EOF
    
    # Extract custom aliases from current file (not in source)
    if [[ -f "$current_file" ]]; then
        local custom_aliases=()
        
        # Read current aliases
        while IFS= read -r line; do
            if [[ "$line" =~ ^alias\ ([^=]+)= ]]; then
                local alias_name="${BASH_REMATCH[1]}"
                
                # Check if this alias exists in source
                if ! grep -q "^alias $alias_name=" "$source_file" 2>/dev/null; then
                    custom_aliases+=("$line")
                fi
            fi
        done < "$current_file"
        
        # Add custom aliases if any found
        if [[ ${#custom_aliases[@]} -gt 0 ]]; then
            echo "# === CUSTOM ALIASES ===" >> "$temp_file"
            printf '%s\n' "${custom_aliases[@]}" >> "$temp_file"
            echo "" >> "$temp_file"
        fi
    fi
    
    # Add source aliases
    echo "# === BASHMIN ALIASES ===" >> "$temp_file"
    cat "$source_file" >> "$temp_file"
    
    mv "$temp_file" "$output_file"
}

# Function to update user aliases
update_user_aliases() {
    if [[ "$QUIET" == false ]]; then
        print_info "Updating user aliases: $USER_ALIASES"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would update user aliases"
        return 0
    fi
    
    # Create backup
    create_backup "$USER_ALIASES"
    
    # Update aliases with intelligent merging
    local temp_merged=$(mktemp)
    merge_aliases_intelligent "$USER_ALIASES" "$ALIASES_SOURCE" "$temp_merged"
    mv "$temp_merged" "$USER_ALIASES"
    
    # Set proper permissions
    chmod 644 "$USER_ALIASES"
    
    # Update version marker
    mkdir -p "$(dirname "$UPDATE_MARKER")" 2>/dev/null || true
    date +%s > "$UPDATE_MARKER" 2>/dev/null || true
    
    if [[ "$QUIET" == false ]]; then
        print_success "User aliases updated successfully"
    fi
}

# Function to update system aliases
update_system_aliases() {
    if [[ "$QUIET" == false ]]; then
        print_info "Updating system aliases: $GLOBAL_ALIASES"
    fi
    
    # Check sudo privileges
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_error "System scope update requires sudo privileges"
        exit 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would update system aliases"
        return 0
    fi
    
    # Create backup
    create_backup "$GLOBAL_ALIASES"
    
    # Update aliases with intelligent merging
    local temp_merged=$(mktemp)
    merge_aliases_intelligent "$GLOBAL_ALIASES" "$ALIASES_SOURCE" "$temp_merged"
    sudo mv "$temp_merged" "$GLOBAL_ALIASES"
    
    # Set proper permissions
    sudo chmod 644 "$GLOBAL_ALIASES"
    sudo chown root:root "$GLOBAL_ALIASES"
    
    # Update version marker
    mkdir -p "$(dirname "$UPDATE_MARKER")" 2>/dev/null || true
    date +%s > "$UPDATE_MARKER" 2>/dev/null || true
    
    if [[ "$QUIET" == false ]]; then
        print_success "System aliases updated successfully"
    fi
}

# Function to show update summary
show_update_summary() {
    if [[ "$QUIET" == true ]]; then
        return 0
    fi
    
    echo
    print_info "=== Aliases Update Summary ==="
    echo
    
    # Count aliases in source
    local total_aliases
    total_aliases=$(grep -c "^alias " "$ALIASES_SOURCE" 2>/dev/null || echo "0")
    
    cat << EOF
Update Details:
  Source File:     $ALIASES_SOURCE
  Total Aliases:   $total_aliases
  Scope:          $UPDATE_SCOPE
  Backup Created: $(if [[ "$CREATE_BACKUP" == true ]]; then echo "Yes"; else echo "No"; fi)

Changes Applied:
  ✓ Updated bashmin aliases from repository
  ✓ Preserved any custom aliases
  ✓ Updated version timestamp
  ✓ Maintained proper file permissions

Activation:
  # Reload aliases in current session
  source ~/.bashrc
  
  # Or start a new terminal session

Management:
  Check updates:   $0 --check-only
  Force update:    $0 --force
  View changes:    diff ~/.bash_aliases.backup ~/.bash_aliases

Automation:
  Add to crontab for automatic updates:
  0 2 * * * $SCRIPT_DIR/self-update.sh --quiet

EOF
    
    print_success "Aliases self-update completed successfully! 🚀"
}

# Function to perform update check
perform_update_check() {
    local scope="$1"
    local target_file
    
    case "$scope" in
        user)
            target_file="$USER_ALIASES"
            ;;
        system)
            target_file="$GLOBAL_ALIASES"
            ;;
        *)
            print_error "Invalid scope for update check: $scope"
            return 1
            ;;
    esac
    
    if [[ ! -f "$target_file" ]]; then
        if [[ "$QUIET" == false ]]; then
            print_warning "No existing aliases found at: $target_file"
            print_info "Run install.sh to install aliases first"
        fi
        return 1
    fi
    
    if check_update_available "$target_file"; then
        if [[ "$QUIET" == false ]]; then
            print_success "Updates available for $scope aliases"
        fi
        return 0
    else
        if [[ "$QUIET" == false ]]; then
            print_info "No updates available for $scope aliases"
        fi
        return 1
    fi
}

# Function to perform update
perform_update() {
    local scope="$1"
    
    case "$scope" in
        user)
            if perform_update_check "user"; then
                update_user_aliases
                return 0
            else
                if [[ "$FORCE_UPDATE" == true ]]; then
                    update_user_aliases
                    return 0
                else
                    if [[ "$QUIET" == false ]]; then
                        print_info "No updates needed for user aliases"
                    fi
                    return 1
                fi
            fi
            ;;
        system)
            if perform_update_check "system"; then
                update_system_aliases
                return 0
            else
                if [[ "$FORCE_UPDATE" == true ]]; then
                    update_system_aliases
                    return 0
                else
                    if [[ "$QUIET" == false ]]; then
                        print_info "No updates needed for system aliases"
                    fi
                    return 1
                fi
            fi
            ;;
        *)
            print_error "Invalid update scope: $scope"
            return 1
            ;;
    esac
}

# Main function
main() {
    if [[ "$QUIET" == false ]]; then
        show_script_header "Bash Aliases Self-Update Script"
    fi
    
    # Check if source file exists
    if [[ ! -f "$ALIASES_SOURCE" ]]; then
        print_error "Source aliases file not found: $ALIASES_SOURCE"
        print_info "Make sure you're running this from the bashmin repository"
        exit 1
    fi
    
    # Determine update scope
    local actual_scope="$UPDATE_SCOPE"
    if [[ "$UPDATE_SCOPE" == "auto" ]]; then
        actual_scope=$(detect_installation_scope)
        
        if [[ "$actual_scope" == "none" ]]; then
            print_error "No existing aliases installation found"
            print_info "Run install.sh to install aliases first"
            exit 1
        fi
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Auto-detected scope: $actual_scope"
        fi
    fi
    
    # Handle check-only mode
    if [[ "$CHECK_ONLY" == true ]]; then
        if perform_update_check "$actual_scope"; then
            if [[ "$QUIET" == false ]]; then
                print_success "Updates are available"
            fi
            exit 0
        else
            if [[ "$QUIET" == false ]]; then
                print_info "No updates available"
            fi
            exit 1
        fi
    fi
    
    # Show update plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Update plan:"
        print_info "  Scope: $actual_scope"
        print_info "  Force: $FORCE_UPDATE"
        print_info "  Backup: $CREATE_BACKUP"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with aliases update?" "Y"; then
            print_info "Update cancelled"
            exit 0
        fi
    fi
    
    # Perform update
    if perform_update "$actual_scope"; then
        show_update_summary
    else
        if [[ "$QUIET" == false ]]; then
            print_info "No updates were applied"
        fi
    fi
}

# Run main function
main "$@"