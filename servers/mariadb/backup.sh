#!/bin/bash
#
# Script: servers/mariadb/backup.sh
# Description: MariaDB backup script with CLI support and progress indicators
# Usage: ./backup.sh [OPTIONS] [DATABASE_NAME]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Script configuration
readonly DEFAULT_BACKUP_DIR="/var/backups/mariadb"
readonly DEFAULT_RETENTION_DAYS=30
readonly TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly COMPRESSION_LEVEL=6

# Configuration variables
BACKUP_DIR=""
DATABASE_NAME=""
BACKUP_TYPE="full"
COMPRESSION="gzip"
RETENTION_DAYS=""
MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
VERBOSE=false
DRY_RUN=false
SHOW_PROGRESS=true
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--database)
            DATABASE_NAME="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --type)
            BACKUP_TYPE="$2"
            shift 2
            ;;
        --compression)
            COMPRESSION="$2"
            shift 2
            ;;
        --retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        -u|--user)
            MYSQL_USER="$2"
            shift 2
            ;;
        -p|--password)
            MYSQL_PASSWORD="$2"
            shift 2
            ;;
        -h|--host)
            MYSQL_HOST="$2"
            shift 2
            ;;
        -P|--port)
            MYSQL_PORT="$2"
            shift 2
            ;;
        --no-progress)
            SHOW_PROGRESS=false
            shift
            ;;
        --force)
            FORCE=true
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
        --help)
            show_help
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            # Positional argument (database name)
            if [[ -z "$DATABASE_NAME" ]]; then
                DATABASE_NAME="$1"
            else
                print_error "Multiple database names specified: $DATABASE_NAME, $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [DATABASE_NAME]

MariaDB backup script with CLI support and progress indicators.

ARGUMENTS:
    DATABASE_NAME           Name of database to backup (or use --database)

OPTIONS:
    -d, --database NAME     Database name to backup
    --backup-dir DIR        Backup directory (default: $DEFAULT_BACKUP_DIR)
    --type TYPE             Backup type: full, schema, data (default: full)
    --compression TYPE      Compression: gzip, bzip2, xz, none (default: gzip)
    --retention DAYS        Retention period in days (default: $DEFAULT_RETENTION_DAYS)
    -u, --user USER         MySQL username (default: prompt or use .my.cnf)
    -p, --password PASS     MySQL password (default: prompt or use .my.cnf)
    -h, --host HOST         MySQL host (default: localhost)
    -P, --port PORT         MySQL port (default: 3306)
    --no-progress          Disable progress bar
    --force                Force backup even if target exists
    --verbose              Enable verbose output
    --dry-run              Show what would be done without executing
    --help                 Show this help message

BACKUP TYPES:
    full                   Complete database backup (structure + data)
    schema                 Structure only (no data)
    data                   Data only (no structure)

EXAMPLES:
    $0 wordpress                    # Backup wordpress database
    $0 --database myapp             # Same as above
    $0 --type schema --database myapp # Schema only backup
    $0 --compression xz wordpress   # Use XZ compression
    $0 --retention 7 wordpress      # Keep backups for 7 days
    $0 --backup-dir /tmp wordpress  # Custom backup directory
    $0 --dry-run wordpress          # Show what would happen

ENVIRONMENT:
    MYSQL_USER             Default MySQL username
    MYSQL_PASSWORD         Default MySQL password
    MYSQL_HOST             Default MySQL host
    MYSQL_PORT             Default MySQL port

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if MariaDB/MySQL client is installed
    if ! command -v mysql &> /dev/null && ! command -v mariadb &> /dev/null; then
        print_error "MySQL/MariaDB client not found"
        print_info "Install with: sudo apt install mariadb-client"
        exit 1
    fi
    
    # Check if mysqldump is available
    if ! command -v mysqldump &> /dev/null; then
        print_error "mysqldump not found"
        print_info "Install with: sudo apt install mariadb-client"
        exit 1
    fi
    
    # Check if pv is available for progress bars
    if [[ "$SHOW_PROGRESS" == true ]] && ! command -v pv &> /dev/null; then
        print_warning "pv (pipe viewer) not found - progress bars disabled"
        print_info "Install with: sudo apt install pv"
        SHOW_PROGRESS=false
    fi
    
    # Check compression tools
    case "$COMPRESSION" in
        gzip)
            if ! command -v gzip &> /dev/null; then
                print_error "gzip not found"
                exit 1
            fi
            ;;
        bzip2)
            if ! command -v bzip2 &> /dev/null; then
                print_error "bzip2 not found"
                print_info "Install with: sudo apt install bzip2"
                exit 1
            fi
            ;;
        xz)
            if ! command -v xz &> /dev/null; then
                print_error "xz not found"
                print_info "Install with: sudo apt install xz-utils"
                exit 1
            fi
            ;;
        none)
            # No compression tool needed
            ;;
        *)
            print_error "Unknown compression type: $COMPRESSION"
            print_info "Supported types: gzip, bzip2, xz, none"
            exit 1
            ;;
    esac
    
    print_success "Prerequisites check completed"
}

# Function to setup defaults
setup_defaults() {
    # Set default backup directory
    if [[ -z "$BACKUP_DIR" ]]; then
        BACKUP_DIR="$DEFAULT_BACKUP_DIR"
    fi
    
    # Set default retention
    if [[ -z "$RETENTION_DAYS" ]]; then
        RETENTION_DAYS="$DEFAULT_RETENTION_DAYS"
    fi
    
    # Use environment variables if not specified
    if [[ -z "$MYSQL_USER" && -n "${MYSQL_USER:-}" ]]; then
        MYSQL_USER="$MYSQL_USER"
    fi
    
    if [[ -z "$MYSQL_PASSWORD" && -n "${MYSQL_PASSWORD:-}" ]]; then
        MYSQL_PASSWORD="$MYSQL_PASSWORD"
    fi
    
    if [[ -z "$MYSQL_HOST" && -n "${MYSQL_HOST:-}" ]]; then
        MYSQL_HOST="$MYSQL_HOST"
    fi
    
    if [[ -z "$MYSQL_PORT" && -n "${MYSQL_PORT:-}" ]]; then
        MYSQL_PORT="$MYSQL_PORT"
    fi
}

# Function to validate backup type
validate_backup_type() {
    case "$BACKUP_TYPE" in
        full|schema|data)
            return 0
            ;;
        *)
            print_error "Invalid backup type: $BACKUP_TYPE"
            print_info "Valid types: full, schema, data"
            exit 1
            ;;
    esac
}

# Function to prompt for database if not specified
prompt_for_database() {
    if [[ -n "$DATABASE_NAME" ]]; then
        return 0
    fi
    
    print_info "No database specified. Available databases:"
    
    local databases
    if ! databases=$(get_database_list); then
        print_error "Failed to retrieve database list"
        exit 1
    fi
    
    if [[ -z "$databases" ]]; then
        print_error "No databases found"
        exit 1
    fi
    
    # Convert to array for selection menu
    local db_array=()
    while IFS= read -r db; do
        # Skip system databases
        if [[ "$db" != "information_schema" && "$db" != "performance_schema" && "$db" != "mysql" && "$db" != "sys" ]]; then
            db_array+=("$db")
        fi
    done <<< "$databases"
    
    if [[ ${#db_array[@]} -eq 0 ]]; then
        print_error "No user databases found"
        exit 1
    fi
    
    # Add "All databases" option
    db_array=("All databases" "${db_array[@]}")
    
    local selection
    selection=$(show_selection_menu "Choose database to backup" "${db_array[@]}")
    
    if [[ "$selection" == "All databases" ]]; then
        DATABASE_NAME="--all-databases"
    else
        DATABASE_NAME="$selection"
    fi
}

# Function to get database list
get_database_list() {
    local mysql_cmd
    mysql_cmd=$(build_mysql_command "mysql")
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would list databases using: $mysql_cmd"
        echo -e "wordpress\nmyapp\ntestdb"
        return 0
    fi
    
    $mysql_cmd -e "SHOW DATABASES;" --batch --skip-column-names 2>/dev/null
}

# Function to build MySQL command with credentials
build_mysql_command() {
    local command="$1"
    local cmd_parts=("$command")
    
    # Add host and port
    cmd_parts+=("-h" "$MYSQL_HOST")
    cmd_parts+=("-P" "$MYSQL_PORT")
    
    # Add user if specified
    if [[ -n "$MYSQL_USER" ]]; then
        cmd_parts+=("-u" "$MYSQL_USER")
    fi
    
    # Add password if specified
    if [[ -n "$MYSQL_PASSWORD" ]]; then
        cmd_parts+=("-p$MYSQL_PASSWORD")
    fi
    
    echo "${cmd_parts[*]}"
}

# Function to prompt for MySQL credentials
prompt_for_credentials() {
    # Check if we can connect without explicit credentials (.my.cnf)
    local test_cmd
    test_cmd=$(build_mysql_command "mysql")
    
    if [[ "$DRY_RUN" == false ]] && $test_cmd -e "SELECT 1;" &>/dev/null; then
        print_success "Using existing MySQL credentials"
        return 0
    fi
    
    # Prompt for credentials if needed
    if [[ -z "$MYSQL_USER" ]]; then
        read -p "MySQL username: " MYSQL_USER
    fi
    
    if [[ -z "$MYSQL_PASSWORD" ]]; then
        read -s -p "MySQL password: " MYSQL_PASSWORD
        echo
    fi
    
    # Test credentials
    if [[ "$DRY_RUN" == false ]]; then
        local test_cmd
        test_cmd=$(build_mysql_command "mysql")
        
        if ! $test_cmd -e "SELECT 1;" &>/dev/null; then
            print_error "Failed to connect to MySQL with provided credentials"
            exit 1
        fi
        
        print_success "MySQL connection verified"
    fi
}

# Function to create backup directory
create_backup_directory() {
    local full_backup_dir="$BACKUP_DIR/$DATABASE_NAME"
    
    if [[ "$DATABASE_NAME" == "--all-databases" ]]; then
        full_backup_dir="$BACKUP_DIR/all-databases"
    fi
    
    print_info "Creating backup directory: $full_backup_dir"
    
    execute_command "sudo mkdir -p '$full_backup_dir'" "Creating backup directory"
    execute_command "sudo chown $(whoami):$(whoami) '$full_backup_dir'" "Setting directory permissions"
}

# Function to get file extension for compression
get_file_extension() {
    case "$COMPRESSION" in
        gzip)
            echo ".sql.gz"
            ;;
        bzip2)
            echo ".sql.bz2"
            ;;
        xz)
            echo ".sql.xz"
            ;;
        none)
            echo ".sql"
            ;;
    esac
}

# Function to build mysqldump command
build_mysqldump_command() {
    local mysqldump_cmd
    mysqldump_cmd=$(build_mysql_command "mysqldump")
    
    # Add common options
    local dump_parts=($mysqldump_cmd)
    dump_parts+=("--single-transaction")
    dump_parts+=("--routines")
    dump_parts+=("--triggers")
    dump_parts+=("--events")
    
    # Add backup type specific options
    case "$BACKUP_TYPE" in
        schema)
            dump_parts+=("--no-data")
            ;;
        data)
            dump_parts+=("--no-create-info")
            ;;
        full)
            # Default - includes both structure and data
            ;;
    esac
    
    # Add database name or --all-databases
    if [[ "$DATABASE_NAME" == "--all-databases" ]]; then
        dump_parts+=("--all-databases")
    else
        dump_parts+=("$DATABASE_NAME")
    fi
    
    echo "${dump_parts[*]}"
}

# Function to build compression command
build_compression_command() {
    case "$COMPRESSION" in
        gzip)
            echo "gzip -$COMPRESSION_LEVEL"
            ;;
        bzip2)
            echo "bzip2 -$COMPRESSION_LEVEL"
            ;;
        xz)
            echo "xz -$COMPRESSION_LEVEL"
            ;;
        none)
            echo "cat"
            ;;
    esac
}

# Function to estimate backup size
estimate_backup_size() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would estimate backup size"
        return 0
    fi
    
    print_info "Estimating backup size..."
    
    local mysql_cmd
    mysql_cmd=$(build_mysql_command "mysql")
    
    local size_query="SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'DB Size in MB' FROM information_schema.tables"
    
    if [[ "$DATABASE_NAME" != "--all-databases" ]]; then
        size_query="$size_query WHERE table_schema='$DATABASE_NAME'"
    fi
    
    local estimated_size
    estimated_size=$($mysql_cmd -e "$size_query" --batch --skip-column-names 2>/dev/null || echo "unknown")
    
    if [[ "$estimated_size" != "unknown" && "$estimated_size" != "NULL" ]]; then
        print_info "Estimated size: ${estimated_size} MB"
    else
        print_warning "Could not estimate backup size"
    fi
}

# Function to perform backup
perform_backup() {
    local backup_name="${DATABASE_NAME}_${BACKUP_TYPE}_${TIMESTAMP}"
    local file_ext
    file_ext=$(get_file_extension)
    local backup_file="$BACKUP_DIR"
    
    if [[ "$DATABASE_NAME" == "--all-databases" ]]; then
        backup_file="$backup_file/all-databases/all-databases_${BACKUP_TYPE}_${TIMESTAMP}${file_ext}"
    else
        backup_file="$backup_file/$DATABASE_NAME/${backup_name}${file_ext}"
    fi
    
    # Check if backup file already exists
    if [[ -f "$backup_file" && "$FORCE" == false ]]; then
        print_error "Backup file already exists: $backup_file"
        print_info "Use --force to overwrite"
        exit 1
    fi
    
    print_info "Starting backup..."
    print_info "Database: $DATABASE_NAME"
    print_info "Type: $BACKUP_TYPE"
    print_info "Compression: $COMPRESSION"
    print_info "Output: $backup_file"
    
    # Build the complete backup command
    local mysqldump_cmd
    mysqldump_cmd=$(build_mysqldump_command)
    
    local compression_cmd
    compression_cmd=$(build_compression_command)
    
    local full_command
    if [[ "$SHOW_PROGRESS" == true ]]; then
        full_command="$mysqldump_cmd | pv -p -t -e -r -b | $compression_cmd > '$backup_file'"
    else
        full_command="$mysqldump_cmd | $compression_cmd > '$backup_file'"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would execute: $full_command"
        return 0
    fi
    
    # Execute the backup
    print_info "Executing backup command..."
    if [[ "$VERBOSE" == true ]]; then
        print_info "Command: $full_command"
    fi
    
    if eval "$full_command"; then
        local file_size
        file_size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup completed successfully!"
        print_success "File: $backup_file"
        print_success "Size: $file_size"
    else
        print_error "Backup failed!"
        # Clean up failed backup file
        if [[ -f "$backup_file" ]]; then
            rm -f "$backup_file"
        fi
        exit 1
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    if [[ "$RETENTION_DAYS" -eq 0 ]]; then
        print_info "Retention set to 0 - skipping cleanup"
        return 0
    fi
    
    print_info "Cleaning up backups older than $RETENTION_DAYS days..."
    
    local backup_base_dir="$BACKUP_DIR"
    if [[ "$DATABASE_NAME" == "--all-databases" ]]; then
        backup_base_dir="$backup_base_dir/all-databases"
    else
        backup_base_dir="$backup_base_dir/$DATABASE_NAME"
    fi
    
    if [[ ! -d "$backup_base_dir" ]]; then
        print_info "No backup directory found for cleanup"
        return 0
    fi
    
    local cleanup_cmd="find '$backup_base_dir' -name '*.sql*' -type f -mtime +$RETENTION_DAYS"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would find old backups with: $cleanup_cmd"
        echo "[DRY-RUN] Would delete files older than $RETENTION_DAYS days"
        return 0
    fi
    
    local old_files
    old_files=$($cleanup_cmd 2>/dev/null || true)
    
    if [[ -n "$old_files" ]]; then
        local file_count
        file_count=$(echo "$old_files" | wc -l)
        print_info "Found $file_count old backup files to remove"
        
        if [[ "$VERBOSE" == true ]]; then
            echo "$old_files"
        fi
        
        if confirm_action "Delete $file_count old backup files?"; then
            echo "$old_files" | xargs rm -f
            print_success "Cleanup completed"
        else
            print_info "Cleanup skipped"
        fi
    else
        print_info "No old backup files found"
    fi
}

# Function to show backup summary
show_backup_summary() {
    echo
    print_info "=== Backup Summary ==="
    print_info "Database: $DATABASE_NAME"
    print_info "Backup type: $BACKUP_TYPE"
    print_info "Compression: $COMPRESSION"
    print_info "Backup directory: $BACKUP_DIR"
    print_info "Retention: $RETENTION_DAYS days"
    
    if [[ "$DRY_RUN" == false ]]; then
        local backup_count
        local backup_base_dir="$BACKUP_DIR"
        
        if [[ "$DATABASE_NAME" == "--all-databases" ]]; then
            backup_base_dir="$backup_base_dir/all-databases"
        else
            backup_base_dir="$backup_base_dir/$DATABASE_NAME"
        fi
        
        if [[ -d "$backup_base_dir" ]]; then
            backup_count=$(find "$backup_base_dir" -name "*.sql*" -type f | wc -l)
            print_info "Total backups: $backup_count"
        fi
    fi
    
    echo
    print_success "Backup process completed! 🚀"
}

# Main function
main() {
    show_script_header "MariaDB Backup Script"
    
    # Setup defaults
    setup_defaults
    
    # Validate backup type
    validate_backup_type
    
    # Check prerequisites
    check_prerequisites
    
    # Prompt for database if not specified
    prompt_for_database
    
    # Prompt for credentials if needed
    prompt_for_credentials
    
    # Create backup directory
    create_backup_directory
    
    # Estimate backup size
    estimate_backup_size
    
    # Confirm backup
    if ! confirm_action "Proceed with backup of '$DATABASE_NAME'?" "Y"; then
        print_info "Backup cancelled"
        exit 0
    fi
    
    # Perform the backup
    perform_backup
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Show summary
    show_backup_summary
}

# Run main function
main "$@"
