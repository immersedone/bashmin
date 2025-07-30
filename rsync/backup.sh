#!/bin/bash
#
# Script: rsync/backup.sh
# Description: Comprehensive backup and sync script for local and remote synchronization
# Usage: ./backup.sh [OPTIONS]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly RSYNC_USER="rsync-backup"
readonly RSYNC_GROUP="rsync-backup"
readonly BASHMIN_LOG_DIR="/var/log/bashmin"
readonly RSYNC_LOG_DIR="/var/log/bashmin/rsync"
readonly RSYNC_CONFIG_DIR="/etc/bashmin/rsync"
readonly RSYNC_BACKUP_DIR="/opt/bashmin/backups"
readonly RSYNC_STATE_DIR="/var/lib/bashmin/rsync"
readonly SSH_KEY_DIR="/home/$RSYNC_USER/.ssh"
readonly RSYNC_EXCLUDES_FILE="$RSYNC_CONFIG_DIR/excludes.conf"
readonly RSYNC_TARGETS_FILE="$RSYNC_CONFIG_DIR/targets.conf"

# Configuration variables
SYNC_MODE="backup"           # backup, sync, mirror, incremental
SYNC_TYPE="local"            # local, remote, bidirectional
SOURCE_PATH=""
DESTINATION_PATH=""
REMOTE_HOST=""
REMOTE_USER="root"
REMOTE_PORT="22"
SSH_KEY_PATH=""
EXCLUDE_PATTERNS=()
INCLUDE_PATTERNS=()
DELETE_EXCLUDED=false
PRESERVE_PERMISSIONS=true
PRESERVE_OWNERSHIP=true
PRESERVE_TIMESTAMPS=true
PRESERVE_LINKS=true
COMPRESS=true
BANDWIDTH_LIMIT=""
PARTIAL_TRANSFERS=true
RESUME_TRANSFERS=true
VERIFY_CHECKSUMS=true
DRY_RUN=false
VERBOSE=false
QUIET=false
PROGRESS=true
STATS=true
BACKUP_SUFFIX=""
BACKUP_DIR=""
INCREMENTAL_BACKUP=false
SNAPSHOT_DIR=""
MAX_SNAPSHOTS=7
EMAIL_NOTIFICATIONS=false
NOTIFICATION_EMAIL=""
SLACK_WEBHOOK=""
LOG_LEVEL="INFO"
PARALLEL_TRANSFERS=1
RETRY_COUNT=3
RETRY_DELAY=30
TIMEOUT=3600
PRE_SYNC_SCRIPT=""
POST_SYNC_SCRIPT=""
CONFIG_FILE=""
DAEMON_MODE=false
SCHEDULE=""
FORCE=false

# Help function
show_help() {
    cat << 'EOF'
Rsync Backup and Synchronization Script

DESCRIPTION:
    Comprehensive backup and synchronization solution using rsync for both local 
    and remote operations. Supports multiple sync modes, incremental backups, 
    snapshots, and advanced configuration options.

USAGE:
    ./backup.sh [OPTIONS]

OPTIONS:
    Source and Destination:
    -s, --source PATH           Source directory/file path
    -d, --destination PATH      Destination directory path
    -h, --remote-host HOST      Remote host for SSH synchronization
    -u, --remote-user USER      Remote SSH username [root]
    -p, --remote-port PORT      Remote SSH port [22]
    -k, --ssh-key PATH          SSH private key path for authentication
    
    Sync Configuration:
    -m, --sync-mode MODE        Sync mode: backup, sync, mirror, incremental [backup]
    -t, --sync-type TYPE        Sync type: local, remote, bidirectional [local]
    --exclude PATTERN           Exclude pattern (can be used multiple times)
    --include PATTERN           Include pattern (can be used multiple times)
    --exclude-file FILE         File containing exclude patterns
    --delete-excluded           Delete excluded files from destination
    
    Transfer Options:
    --no-compress               Disable compression during transfer
    --bandwidth-limit RATE      Limit bandwidth (e.g., 1000k, 2m)
    --no-partial                Disable partial file transfers
    --no-resume                 Disable transfer resume
    --no-checksum               Disable checksum verification
    --parallel NUM              Number of parallel transfers [1]
    --timeout SECONDS           Transfer timeout in seconds [3600]
    --retry-count NUM           Number of retry attempts [3]
    --retry-delay SEC           Delay between retries in seconds [30]
    
    Preservation Options:
    --no-perms                  Don't preserve file permissions
    --no-owner                  Don't preserve file ownership
    --no-times                  Don't preserve modification times
    --no-links                  Don't preserve symbolic links
    
    Backup Features:
    --backup-suffix SUFFIX      Backup file suffix
    --backup-dir DIR            Directory for backup files
    --incremental               Enable incremental backup mode
    --snapshot-dir DIR          Directory for snapshots
    --max-snapshots NUM         Maximum number of snapshots to keep [7]
    
    Automation and Scheduling:
    --daemon                    Run in daemon mode
    --schedule CRON             Cron schedule for daemon mode
    --pre-sync-script SCRIPT    Script to run before sync
    --post-sync-script SCRIPT   Script to run after sync
    --config-file FILE          Configuration file path
    
    Notifications:
    --email EMAIL               Email address for notifications
    --slack-webhook URL         Slack webhook for notifications
    --no-notifications          Disable all notifications
    
    Execution Control:
    --dry-run                   Show what would be synchronized without executing
    --verbose                   Enable verbose output
    --quiet                     Suppress non-essential output
    --no-progress               Disable progress display
    --no-stats                  Disable transfer statistics
    --log-level LEVEL           Log level: DEBUG, INFO, WARN, ERROR [INFO]
    --force                     Force operation even with warnings
    --help                      Show this help message

SYNC MODES:
    backup                      One-way backup (source to destination)
                               - Preserves destination files not in source
                               - Creates incremental backups if enabled
    
    sync                        One-way synchronization
                               - Makes destination identical to source
                               - Deletes files not in source (use with caution)
    
    mirror                      Exact mirror synchronization
                               - Bidirectional sync (requires bidirectional type)
                               - Maintains exact copies on both sides
    
    incremental                 Incremental backup with snapshots
                               - Creates timestamped snapshots
                               - Hard-links unchanged files for efficiency

SYNC TYPES:
    local                       Local filesystem synchronization
    remote                      Remote synchronization via SSH
    bidirectional              Two-way synchronization (local or remote)

EXAMPLES:
    # Simple local backup
    ./backup.sh --source /home/user --destination /backup/user

    # Remote backup with SSH key
    ./backup.sh --source /var/www --destination /backup/www \\
                --remote-host server.example.com --ssh-key ~/.ssh/backup_key

    # Incremental backup with snapshots
    ./backup.sh --source /data --destination /backup/data \\
                --sync-mode incremental --snapshot-dir /backup/snapshots

    # Sync with exclusions and compression
    ./backup.sh --source /home --destination /backup/home \\
                --exclude "*.tmp" --exclude "*.log" --bandwidth-limit 1000k

    # Bidirectional sync between servers
    ./backup.sh --source /srv/data --destination /backup/data \\
                --sync-type bidirectional --remote-host backup-server.com

    # Daemon mode with email notifications
    ./backup.sh --daemon --config-file /etc/bashmin/rsync/backup.conf \\
                --email admin@company.com --schedule "0 2 * * *"

    # Dry run to preview changes
    ./backup.sh --source /data --destination /backup --dry-run --verbose

CONFIGURATION FILE:
    Configuration files use KEY=VALUE format:
    
    SOURCE_PATH="/var/www"
    DESTINATION_PATH="/backup/www"
    REMOTE_HOST="backup.example.com"
    EXCLUDE_PATTERNS=("*.tmp" "*.log" ".git")
    EMAIL_NOTIFICATIONS=true
    NOTIFICATION_EMAIL="admin@company.com"

PRE/POST SYNC SCRIPTS:
    Scripts receive environment variables:
    - SYNC_SOURCE: Source path
    - SYNC_DESTINATION: Destination path
    - SYNC_MODE: Current sync mode
    - SYNC_STATUS: "starting" (pre) or "completed"/"failed" (post)

EOF
}

# Function to validate dependencies
check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_deps=()
    
    # Check required commands
    local required_commands=("rsync" "ssh" "date" "find")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Installing missing dependencies..."
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would install: ${missing_deps[*]}"
        else
            apt-get update -qq
            apt-get install -y rsync openssh-client coreutils findutils
        fi
    fi
    
    # Check rsync version and capabilities
    local rsync_version=$(rsync --version | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
    print_info "Rsync version: $rsync_version"
    
    # Verify rsync supports required features
    if ! rsync --help | grep -q "partial"; then
        print_warning "Rsync version may not support partial transfers"
    fi
}

# Function to create system structure
create_system_structure() {
    print_info "Creating system structure..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create rsync system structure"
        return 0
    fi
    
    # Create rsync user if it doesn't exist
    if ! id "$RSYNC_USER" >/dev/null 2>&1; then
        print_info "Creating rsync system user..."
        useradd --system --home-dir "/home/$RSYNC_USER" --shell /bin/bash --user-group "$RSYNC_USER"
        mkdir -p "/home/$RSYNC_USER"
        chown "$RSYNC_USER:$RSYNC_GROUP" "/home/$RSYNC_USER"
    fi
    
    # Create directories
    local dirs=(
        "$RSYNC_LOG_DIR"
        "$RSYNC_CONFIG_DIR"
        "$RSYNC_BACKUP_DIR"
        "$RSYNC_STATE_DIR"
        "$SSH_KEY_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        if [[ "$dir" == "$SSH_KEY_DIR" ]]; then
            chown "$RSYNC_USER:$RSYNC_GROUP" "$dir"
            chmod 700 "$dir"
        elif [[ "$dir" =~ ^/var/lib/ || "$dir" =~ ^/opt/ ]]; then
            chown "$RSYNC_USER:$RSYNC_GROUP" "$dir"
        fi
    done
    
    print_success "System structure created"
}

# Function to validate paths
validate_paths() {
    if [[ -z "$SOURCE_PATH" ]]; then
        print_error "Source path is required"
        return 1
    fi
    
    if [[ -z "$DESTINATION_PATH" ]]; then
        print_error "Destination path is required"
        return 1
    fi
    
    # Validate source exists for non-dry-run
    if [[ "$DRY_RUN" != true ]] && [[ "$SYNC_TYPE" == "local" || "$SYNC_TYPE" == "bidirectional" ]]; then
        if [[ ! -e "$SOURCE_PATH" ]]; then
            print_error "Source path does not exist: $SOURCE_PATH"
            return 1
        fi
    fi
    
    # Validate remote host for remote operations
    if [[ "$SYNC_TYPE" == "remote" || "$SYNC_TYPE" == "bidirectional" ]]; then
        if [[ -z "$REMOTE_HOST" ]]; then
            print_error "Remote host is required for remote sync"
            return 1
        fi
    fi
}

# Function to generate SSH key if needed
setup_ssh_key() {
    if [[ "$SYNC_TYPE" != "remote" && "$SYNC_TYPE" != "bidirectional" ]]; then
        return 0
    fi
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        if [[ ! -f "$SSH_KEY_PATH" ]]; then
            print_error "SSH key not found: $SSH_KEY_PATH"
            return 1
        fi
        return 0
    fi
    
    local default_key="$SSH_KEY_DIR/id_rsa"
    
    if [[ ! -f "$default_key" ]]; then
        print_info "Generating SSH key for rsync operations..."
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would generate SSH key: $default_key"
            return 0
        fi
        
        sudo -u "$RSYNC_USER" ssh-keygen -t rsa -b 4096 -f "$default_key" -N "" -C "rsync-backup@$(hostname)"
        print_success "SSH key generated: $default_key"
        print_info "Add the public key to the remote server:"
        print_info "$(cat "$default_key.pub")"
    fi
    
    SSH_KEY_PATH="$default_key"
}

# Function to test SSH connectivity
test_ssh_connection() {
    if [[ "$SYNC_TYPE" != "remote" && "$SYNC_TYPE" != "bidirectional" ]]; then
        return 0
    fi
    
    print_info "Testing SSH connection to $REMOTE_HOST..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test SSH connection"
        return 0
    fi
    
    local ssh_cmd="ssh"
    local ssh_args=("-o" "ConnectTimeout=10" "-o" "BatchMode=yes")
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        ssh_args+=("-i" "$SSH_KEY_PATH")
    fi
    
    if [[ "$REMOTE_PORT" != "22" ]]; then
        ssh_args+=("-p" "$REMOTE_PORT")
    fi
    
    if sudo -u "$RSYNC_USER" $ssh_cmd "${ssh_args[@]}" "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        print_success "SSH connection established"
    else
        print_error "SSH connection failed"
        print_info "Ensure SSH key is added to remote server and user has proper access"
        return 1
    fi
}

# Function to build rsync command
build_rsync_command() {
    local rsync_cmd="rsync"
    local rsync_args=()
    
    # Basic options
    rsync_args+=("-a")  # Archive mode (preserves permissions, timestamps, etc.)
    
    # Verbose output
    if [[ "$VERBOSE" == true ]]; then
        rsync_args+=("-v")
    fi
    
    # Progress display
    if [[ "$PROGRESS" == true && "$QUIET" != true ]]; then
        rsync_args+=("--progress")
    fi
    
    # Statistics
    if [[ "$STATS" == true ]]; then
        rsync_args+=("--stats")
    fi
    
    # Compression
    if [[ "$COMPRESS" == true ]]; then
        rsync_args+=("-z")
    fi
    
    # Preservation options
    if [[ "$PRESERVE_PERMISSIONS" != true ]]; then
        rsync_args+=("--no-perms")
    fi
    
    if [[ "$PRESERVE_OWNERSHIP" != true ]]; then
        rsync_args+=("--no-owner" "--no-group")
    fi
    
    if [[ "$PRESERVE_TIMESTAMPS" != true ]]; then
        rsync_args+=("--no-times")
    fi
    
    if [[ "$PRESERVE_LINKS" != true ]]; then
        rsync_args+=("--no-links")
    fi
    
    # Transfer options
    if [[ "$PARTIAL_TRANSFERS" == true ]]; then
        rsync_args+=("--partial")
    fi
    
    if [[ "$VERIFY_CHECKSUMS" == true ]]; then
        rsync_args+=("-c")
    fi
    
    # Bandwidth limitation
    if [[ -n "$BANDWIDTH_LIMIT" ]]; then
        rsync_args+=("--bwlimit=$BANDWIDTH_LIMIT")
    fi
    
    # Timeout
    if [[ -n "$TIMEOUT" ]]; then
        rsync_args+=("--timeout=$TIMEOUT")
    fi
    
    # Sync mode specific options
    case "$SYNC_MODE" in
        "sync"|"mirror")
            rsync_args+=("--delete")
            if [[ "$DELETE_EXCLUDED" == true ]]; then
                rsync_args+=("--delete-excluded")
            fi
            ;;
        "incremental")
            if [[ -n "$BACKUP_DIR" ]]; then
                rsync_args+=("--backup" "--backup-dir=$BACKUP_DIR")
            fi
            if [[ -n "$BACKUP_SUFFIX" ]]; then
                rsync_args+=("--suffix=$BACKUP_SUFFIX")
            fi
            ;;
    esac
    
    # Exclude patterns
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        rsync_args+=("--exclude=$pattern")
    done
    
    # Include patterns
    for pattern in "${INCLUDE_PATTERNS[@]}"; do
        rsync_args+=("--include=$pattern")
    done
    
    # Exclude from file
    if [[ -f "$RSYNC_EXCLUDES_FILE" ]]; then
        rsync_args+=("--exclude-from=$RSYNC_EXCLUDES_FILE")
    fi
    
    # SSH options for remote sync
    if [[ "$SYNC_TYPE" == "remote" || "$SYNC_TYPE" == "bidirectional" ]]; then
        local ssh_opts="ssh"
        if [[ -n "$SSH_KEY_PATH" ]]; then
            ssh_opts="$ssh_opts -i $SSH_KEY_PATH"
        fi
        if [[ "$REMOTE_PORT" != "22" ]]; then
            ssh_opts="$ssh_opts -p $REMOTE_PORT"
        fi
        rsync_args+=("-e" "$ssh_opts")
    fi
    
    # Dry run
    if [[ "$DRY_RUN" == true ]]; then
        rsync_args+=("--dry-run")
    fi
    
    echo "$rsync_cmd ${rsync_args[*]}"
}

# Function to perform incremental backup with snapshots
perform_incremental_backup() {
    if [[ -z "$SNAPSHOT_DIR" ]]; then
        SNAPSHOT_DIR="$DESTINATION_PATH/snapshots"
    fi
    
    print_info "Performing incremental backup with snapshots..."
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local current_snapshot="$SNAPSHOT_DIR/snapshot_$timestamp"
    local latest_link="$SNAPSHOT_DIR/latest"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create snapshot: $current_snapshot"
        return 0
    fi
    
    # Create snapshot directory
    mkdir -p "$SNAPSHOT_DIR"
    
    # Build rsync command for incremental backup
    local rsync_cmd=$(build_rsync_command)
    
    # Add link-dest for hard-linking unchanged files
    if [[ -d "$latest_link" ]]; then
        rsync_cmd="$rsync_cmd --link-dest=$latest_link"
    fi
    
    # Perform the sync
    local source_path="$SOURCE_PATH"
    local dest_path="$current_snapshot"
    
    # Handle remote paths
    if [[ "$SYNC_TYPE" == "remote" ]]; then
        source_path="$REMOTE_USER@$REMOTE_HOST:$SOURCE_PATH"
    elif [[ "$SYNC_TYPE" == "bidirectional" ]]; then
        print_error "Bidirectional sync not supported with incremental mode"
        return 1
    fi
    
    print_info "Creating snapshot: $current_snapshot"
    
    if eval "$rsync_cmd \"$source_path\" \"$dest_path\""; then
        # Update latest link
        rm -f "$latest_link"
        ln -s "$(basename "$current_snapshot")" "$latest_link"
        print_success "Incremental backup completed: $current_snapshot"
        
        # Cleanup old snapshots
        cleanup_old_snapshots
    else
        print_error "Incremental backup failed"
        return 1
    fi
}

# Function to cleanup old snapshots
cleanup_old_snapshots() {
    if [[ -z "$SNAPSHOT_DIR" || ! -d "$SNAPSHOT_DIR" ]]; then
        return 0
    fi
    
    print_info "Cleaning up old snapshots (keeping $MAX_SNAPSHOTS)..."
    
    local snapshots=($(find "$SNAPSHOT_DIR" -maxdepth 1 -name "snapshot_*" -type d | sort -r))
    local snapshot_count=${#snapshots[@]}
    
    if [[ $snapshot_count -gt $MAX_SNAPSHOTS ]]; then
        local to_remove=$((snapshot_count - MAX_SNAPSHOTS))
        print_info "Removing $to_remove old snapshots..."
        
        for ((i=MAX_SNAPSHOTS; i<snapshot_count; i++)); do
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY-RUN] Would remove: ${snapshots[$i]}"
            else
                print_info "Removing old snapshot: $(basename "${snapshots[$i]}")"
                rm -rf "${snapshots[$i]}"
            fi
        done
    fi
}

# Function to perform standard sync
perform_sync() {
    print_info "Performing $SYNC_MODE synchronization..."
    
    local rsync_cmd=$(build_rsync_command)
    local source_path="$SOURCE_PATH"
    local dest_path="$DESTINATION_PATH"
    
    # Handle remote paths
    if [[ "$SYNC_TYPE" == "remote" ]]; then
        source_path="$REMOTE_USER@$REMOTE_HOST:$SOURCE_PATH"
    fi
    
    # Ensure source path ends with / for directory contents
    if [[ -d "$SOURCE_PATH" && "$SOURCE_PATH" != */ ]]; then
        source_path="$source_path/"
    fi
    
    print_info "Syncing: $source_path -> $dest_path"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Command: $rsync_cmd \"$source_path\" \"$dest_path\""
    fi
    
    if eval "$rsync_cmd \"$source_path\" \"$dest_path\""; then
        print_success "Synchronization completed successfully"
        return 0
    else
        print_error "Synchronization failed"
        return 1
    fi
}

# Function to perform bidirectional sync
perform_bidirectional_sync() {
    print_info "Performing bidirectional synchronization..."
    
    if [[ "$SYNC_TYPE" != "bidirectional" ]]; then
        print_error "Bidirectional sync requires --sync-type bidirectional"
        return 1
    fi
    
    # First sync: local to remote
    print_info "Step 1: Syncing local to remote..."
    local forward_result=0
    SYNC_TYPE="remote"
    perform_sync || forward_result=1
    
    # Second sync: remote to local
    print_info "Step 2: Syncing remote to local..."
    local reverse_result=0
    local temp_source="$SOURCE_PATH"
    local temp_dest="$DESTINATION_PATH"
    
    SOURCE_PATH="$temp_dest"
    DESTINATION_PATH="$temp_source"
    SYNC_TYPE="remote"
    
    local rsync_cmd=$(build_rsync_command)
    local source_path="$REMOTE_USER@$REMOTE_HOST:$SOURCE_PATH"
    local dest_path="$DESTINATION_PATH"
    
    if [[ -d "$SOURCE_PATH" && "$SOURCE_PATH" != */ ]]; then
        source_path="$source_path/"
    fi
    
    print_info "Reverse sync: $source_path -> $dest_path"
    
    if eval "$rsync_cmd \"$source_path\" \"$dest_path\""; then
        print_success "Reverse synchronization completed"
    else
        print_error "Reverse synchronization failed"
        reverse_result=1
    fi
    
    # Restore original values
    SOURCE_PATH="$temp_source"
    DESTINATION_PATH="$temp_dest"
    SYNC_TYPE="bidirectional"
    
    if [[ $forward_result -eq 0 && $reverse_result -eq 0 ]]; then
        print_success "Bidirectional synchronization completed successfully"
        return 0
    else
        print_error "Bidirectional synchronization completed with errors"
        return 1
    fi
}

# Function to run pre-sync script
run_pre_sync_script() {
    if [[ -z "$PRE_SYNC_SCRIPT" || ! -f "$PRE_SYNC_SCRIPT" ]]; then
        return 0
    fi
    
    print_info "Running pre-sync script: $PRE_SYNC_SCRIPT"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would run pre-sync script"
        return 0
    fi
    
    # Set environment variables for the script
    export SYNC_SOURCE="$SOURCE_PATH"
    export SYNC_DESTINATION="$DESTINATION_PATH"
    export SYNC_MODE="$SYNC_MODE"
    export SYNC_STATUS="starting"
    
    if bash "$PRE_SYNC_SCRIPT"; then
        print_success "Pre-sync script completed successfully"
    else
        print_error "Pre-sync script failed"
        return 1
    fi
}

# Function to run post-sync script
run_post_sync_script() {
    if [[ -z "$POST_SYNC_SCRIPT" || ! -f "$POST_SYNC_SCRIPT" ]]; then
        return 0
    fi
    
    local sync_status="${1:-completed}"
    
    print_info "Running post-sync script: $POST_SYNC_SCRIPT"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would run post-sync script with status: $sync_status"
        return 0
    fi
    
    # Set environment variables for the script
    export SYNC_SOURCE="$SOURCE_PATH"
    export SYNC_DESTINATION="$DESTINATION_PATH"
    export SYNC_MODE="$SYNC_MODE"
    export SYNC_STATUS="$sync_status"
    
    if bash "$POST_SYNC_SCRIPT"; then
        print_success "Post-sync script completed successfully"
    else
        print_warning "Post-sync script failed (continuing anyway)"
    fi
}

# Function to send notifications
send_notification() {
    local status="$1"
    local message="$2"
    local details="${3:-}"
    
    if [[ "$EMAIL_NOTIFICATIONS" != true && -z "$SLACK_WEBHOOK" ]]; then
        return 0
    fi
    
    local hostname=$(hostname)
    local timestamp=$(date)
    
    local subject="Rsync $status - $hostname"
    local body="Rsync Operation $status
    
Server: $hostname
Time: $timestamp
Source: $SOURCE_PATH
Destination: $DESTINATION_PATH
Mode: $SYNC_MODE
Type: $SYNC_TYPE

$message

$details"
    
    # Email notification
    if [[ "$EMAIL_NOTIFICATIONS" == true && -n "$NOTIFICATION_EMAIL" ]]; then
        if command -v mail >/dev/null 2>&1; then
            echo "$body" | mail -s "$subject" "$NOTIFICATION_EMAIL"
        fi
    fi
    
    # Slack notification
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        local slack_color="good"
        if [[ "$status" == "Failed" ]]; then
            slack_color="danger"
        elif [[ "$status" == "Warning" ]]; then
            slack_color="warning"
        fi
        
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$subject\",\"color\":\"$slack_color\",\"fields\":[{\"title\":\"Details\",\"value\":\"$message\",\"short\":false}]}" \
            "$SLACK_WEBHOOK" >/dev/null 2>&1 || true
    fi
}

# Function to load configuration file
load_config_file() {
    if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
        return 0
    fi
    
    print_info "Loading configuration from: $CONFIG_FILE"
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    print_success "Configuration loaded"
}

# Function to create default exclude patterns
create_default_excludes() {
    if [[ ! -f "$RSYNC_EXCLUDES_FILE" ]]; then
        print_info "Creating default exclude patterns..."
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would create exclude patterns file"
            return 0
        fi
        
        cat > "$RSYNC_EXCLUDES_FILE" << 'EOF'
# Default rsync exclude patterns
# Temporary files
*.tmp
*.temp
*~
.#*

# System files
.DS_Store
Thumbs.db
desktop.ini

# Version control
.git/
.svn/
.hg/
.bzr/

# Logs
*.log
logs/

# Cache directories
cache/
.cache/
tmp/
temp/

# Build artifacts
build/
dist/
target/
node_modules/

# Database files
*.sqlite
*.db-journal

# OS-specific
lost+found/
.Trash*/
EOF
        
        print_success "Default exclude patterns created"
    fi
}

# Function to perform the main sync operation
perform_main_sync() {
    local sync_result=0
    
    case "$SYNC_MODE" in
        "incremental")
            perform_incremental_backup || sync_result=1
            ;;
        "bidirectional")
            perform_bidirectional_sync || sync_result=1
            ;;
        *)
            perform_sync || sync_result=1
            ;;
    esac
    
    return $sync_result
}

# Function to retry sync operation
retry_sync_operation() {
    local attempt=1
    local max_attempts=$((RETRY_COUNT + 1))
    
    while [[ $attempt -le $max_attempts ]]; do
        print_info "Sync attempt $attempt of $max_attempts"
        
        if perform_main_sync; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            print_warning "Sync failed, retrying in $RETRY_DELAY seconds..."
            sleep "$RETRY_DELAY"
        fi
        
        ((attempt++))
    done
    
    print_error "Sync failed after $max_attempts attempts"
    return 1
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--source)
                if [[ -n "${2:-}" ]]; then
                    SOURCE_PATH="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            -d|--destination)
                if [[ -n "${2:-}" ]]; then
                    DESTINATION_PATH="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            -h|--remote-host)
                if [[ -n "${2:-}" ]]; then
                    REMOTE_HOST="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            -u|--remote-user)
                if [[ -n "${2:-}" ]]; then
                    REMOTE_USER="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            -p|--remote-port)
                if [[ -n "${2:-}" ]]; then
                    REMOTE_PORT="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            -k|--ssh-key)
                if [[ -n "${2:-}" ]]; then
                    SSH_KEY_PATH="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            -m|--sync-mode)
                if [[ -n "${2:-}" ]]; then
                    SYNC_MODE="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            -t|--sync-type)
                if [[ -n "${2:-}" ]]; then
                    SYNC_TYPE="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --exclude)
                if [[ -n "${2:-}" ]]; then
                    EXCLUDE_PATTERNS+=("$2")
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --include)
                if [[ -n "${2:-}" ]]; then
                    INCLUDE_PATTERNS+=("$2")
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --exclude-file)
                if [[ -n "${2:-}" ]]; then
                    RSYNC_EXCLUDES_FILE="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --delete-excluded)
                DELETE_EXCLUDED=true
                shift
                ;;
            --no-compress)
                COMPRESS=false
                shift
                ;;
            --bandwidth-limit)
                if [[ -n "${2:-}" ]]; then
                    BANDWIDTH_LIMIT="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --no-partial)
                PARTIAL_TRANSFERS=false
                shift
                ;;
            --no-resume)
                RESUME_TRANSFERS=false
                shift
                ;;
            --no-checksum)
                VERIFY_CHECKSUMS=false
                shift
                ;;
            --parallel)
                if [[ -n "${2:-}" ]]; then
                    PARALLEL_TRANSFERS="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --timeout)
                if [[ -n "${2:-}" ]]; then
                    TIMEOUT="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --retry-count)
                if [[ -n "${2:-}" ]]; then
                    RETRY_COUNT="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --retry-delay)
                if [[ -n "${2:-}" ]]; then
                    RETRY_DELAY="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --no-perms)
                PRESERVE_PERMISSIONS=false
                shift
                ;;
            --no-owner)
                PRESERVE_OWNERSHIP=false
                shift
                ;;
            --no-times)
                PRESERVE_TIMESTAMPS=false
                shift
                ;;
            --no-links)
                PRESERVE_LINKS=false
                shift
                ;;
            --backup-suffix)
                if [[ -n "${2:-}" ]]; then
                    BACKUP_SUFFIX="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --backup-dir)
                if [[ -n "${2:-}" ]]; then
                    BACKUP_DIR="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --incremental)
                INCREMENTAL_BACKUP=true
                SYNC_MODE="incremental"
                shift
                ;;
            --snapshot-dir)
                if [[ -n "${2:-}" ]]; then
                    SNAPSHOT_DIR="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --max-snapshots)
                if [[ -n "${2:-}" ]]; then
                    MAX_SNAPSHOTS="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --daemon)
                DAEMON_MODE=true
                shift
                ;;
            --schedule)
                if [[ -n "${2:-}" ]]; then
                    SCHEDULE="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --pre-sync-script)
                if [[ -n "${2:-}" ]]; then
                    PRE_SYNC_SCRIPT="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --post-sync-script)
                if [[ -n "${2:-}" ]]; then
                    POST_SYNC_SCRIPT="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --config-file)
                if [[ -n "${2:-}" ]]; then
                    CONFIG_FILE="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --email)
                if [[ -n "${2:-}" ]]; then
                    EMAIL_NOTIFICATIONS=true
                    NOTIFICATION_EMAIL="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --slack-webhook)
                if [[ -n "${2:-}" ]]; then
                    SLACK_WEBHOOK="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --no-notifications)
                EMAIL_NOTIFICATIONS=false
                SLACK_WEBHOOK=""
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --no-progress)
                PROGRESS=false
                shift
                ;;
            --no-stats)
                STATS=false
                shift
                ;;
            --log-level)
                if [[ -n "${2:-}" ]]; then
                    LOG_LEVEL="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Function to validate configuration
validate_configuration() {
    # Validate sync mode
    case "$SYNC_MODE" in
        "backup"|"sync"|"mirror"|"incremental") ;;
        *)
            print_error "Invalid sync mode: $SYNC_MODE"
            echo "Valid modes: backup, sync, mirror, incremental"
            exit 1
            ;;
    esac
    
    # Validate sync type
    case "$SYNC_TYPE" in
        "local"|"remote"|"bidirectional") ;;
        *)
            print_error "Invalid sync type: $SYNC_TYPE"
            echo "Valid types: local, remote, bidirectional"
            exit 1
            ;;
    esac
    
    # Validate numeric values
    if ! [[ "$PARALLEL_TRANSFERS" =~ ^[0-9]+$ ]] || [[ "$PARALLEL_TRANSFERS" -lt 1 ]]; then
        print_error "Invalid parallel transfers value: $PARALLEL_TRANSFERS"
        exit 1
    fi
    
    if ! [[ "$MAX_SNAPSHOTS" =~ ^[0-9]+$ ]] || [[ "$MAX_SNAPSHOTS" -lt 1 ]]; then
        print_error "Invalid max snapshots value: $MAX_SNAPSHOTS"
        exit 1
    fi
    
    # Validate paths
    validate_paths
}

# Main execution function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Load configuration file if specified
    load_config_file
    
    # Validate configuration
    validate_configuration
    
    # Show header
    if [[ "$QUIET" != true ]]; then
        show_script_header "Rsync Backup and Sync Script" 60
        print_info "Mode: $SYNC_MODE, Type: $SYNC_TYPE"
        print_info "Source: $SOURCE_PATH"
        print_info "Destination: $DESTINATION_PATH"
        if [[ -n "$REMOTE_HOST" ]]; then
            print_info "Remote Host: $REMOTE_HOST"
        fi
        echo
    fi
    
    # Start logging
    mkdir -p "$RSYNC_LOG_DIR"
    local log_file="$RSYNC_LOG_DIR/sync-$(date +%Y%m%d_%H%M%S).log"
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
    
    echo "Rsync operation started at $(date)"
    echo "Mode: $SYNC_MODE, Type: $SYNC_TYPE"
    echo "Source: $SOURCE_PATH -> Destination: $DESTINATION_PATH"
    
    # Check dependencies and setup
    check_dependencies
    create_system_structure
    create_default_excludes
    setup_ssh_key
    test_ssh_connection
    
    # Run pre-sync script
    run_pre_sync_script
    
    # Perform the sync operation with retries
    local sync_result=0
    local start_time=$(date +%s)
    
    if retry_sync_operation; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        print_success "Synchronization completed successfully in ${duration}s"
        send_notification "Completed" "Synchronization completed successfully in ${duration}s"
        run_post_sync_script "completed"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        print_error "Synchronization failed after ${duration}s"
        send_notification "Failed" "Synchronization failed after ${duration}s"
        run_post_sync_script "failed"
        sync_result=1
    fi
    
    echo "Rsync operation completed at $(date)"
    
    return $sync_result
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
