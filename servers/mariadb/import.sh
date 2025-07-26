#!/bin/bash
#
# Script: servers/mariadb/import.sh
# Description: MariaDB import script with multi-format support and progress indicators
# Usage: ./import.sh [OPTIONS] FILE_PATH [DATABASE_NAME]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Script configuration
readonly SUPPORTED_FORMATS=("sql" "gz" "bz2" "xz" "csv" "json" "tsv" "xml")
readonly CSV_LOAD_BATCH_SIZE=10000

# Configuration variables
FILE_PATH=""
DATABASE_NAME=""
TABLE_NAME=""
IMPORT_FORMAT=""
MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
CREATE_DATABASE=false
DROP_EXISTING=false
VERBOSE=false
DRY_RUN=false
SHOW_PROGRESS=true
FORCE=false
CSV_DELIMITER=","
CSV_ENCLOSED_BY='"'
CSV_ESCAPED_BY='\\'
CSV_HEADERS=true
JSON_PATH=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--database)
            DATABASE_NAME="$2"
            shift 2
            ;;
        -t|--table)
            TABLE_NAME="$2"
            shift 2
            ;;
        --format)
            IMPORT_FORMAT="$2"
            shift 2
            ;;
        --create-database)
            CREATE_DATABASE=true
            shift
            ;;
        --drop-existing)
            DROP_EXISTING=true
            shift
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
        --csv-delimiter)
            CSV_DELIMITER="$2"
            shift 2
            ;;
        --csv-enclosed-by)
            CSV_ENCLOSED_BY="$2"
            shift 2
            ;;
        --csv-escaped-by)
            CSV_ESCAPED_BY="$2"
            shift 2
            ;;
        --no-csv-headers)
            CSV_HEADERS=false
            shift
            ;;
        --json-path)
            JSON_PATH="$2"
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
            # Positional arguments
            if [[ -z "$FILE_PATH" ]]; then
                FILE_PATH="$1"
            elif [[ -z "$DATABASE_NAME" ]]; then
                DATABASE_NAME="$1"
            else
                print_error "Too many positional arguments"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] FILE_PATH [DATABASE_NAME]

MariaDB import script with multi-format support and progress indicators.

ARGUMENTS:
    FILE_PATH               Path to file to import (required)
    DATABASE_NAME           Target database name (or use --database)

OPTIONS:
    -d, --database NAME     Target database name
    -t, --table NAME        Target table name (for CSV/JSON imports)
    --format FORMAT         Force specific format (auto-detected by default)
    --create-database       Create database if it doesn't exist
    --drop-existing         Drop existing table/database before import
    -u, --user USER         MySQL username (default: prompt or use .my.cnf)
    -p, --password PASS     MySQL password (default: prompt or use .my.cnf)
    -h, --host HOST         MySQL host (default: localhost)
    -P, --port PORT         MySQL port (default: 3306)
    --no-progress          Disable progress bar
    --force                Force import even if target exists
    --verbose              Enable verbose output
    --dry-run              Show what would be done without executing
    --help                 Show this help message

CSV OPTIONS:
    --csv-delimiter CHAR    Field delimiter (default: ,)
    --csv-enclosed-by CHAR  Field enclosure character (default: ")
    --csv-escaped-by CHAR   Escape character (default: \\)
    --no-csv-headers       CSV file has no header row

JSON OPTIONS:
    --json-path PATH        JSONPath for nested data extraction

SUPPORTED FORMATS:
    sql                    SQL dump files
    gz, bz2, xz           Compressed SQL files
    csv, tsv              Comma/Tab separated values
    json                  JSON data files
    xml                   XML data files

EXAMPLES:
    $0 backup.sql mydb                           # Import SQL file
    $0 backup.sql.gz mydb                        # Import compressed SQL
    $0 data.csv mydb --table users               # Import CSV to table
    $0 data.json mydb --table products           # Import JSON to table
    $0 --create-database backup.sql newdb       # Create database and import
    $0 --drop-existing data.csv mydb --table users # Drop table and reimport
    $0 --csv-delimiter ';' data.csv mydb         # Custom CSV delimiter
    $0 --json-path '$.users[*]' data.json mydb  # Extract nested JSON data

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
    
    # Check if pv is available for progress bars
    if [[ "$SHOW_PROGRESS" == true ]] && ! command -v pv &> /dev/null; then
        print_warning "pv (pipe viewer) not found - progress bars disabled"
        print_info "Install with: sudo apt install pv"
        SHOW_PROGRESS=false
    fi
    
    print_success "Prerequisites check completed"
}

# Function to validate file exists
validate_file() {
    if [[ -z "$FILE_PATH" ]]; then
        print_error "No file path specified"
        show_help
        exit 1
    fi
    
    if [[ ! -f "$FILE_PATH" ]]; then
        print_error "File not found: $FILE_PATH"
        exit 1
    fi
    
    if [[ ! -r "$FILE_PATH" ]]; then
        print_error "File not readable: $FILE_PATH"
        exit 1
    fi
    
    print_success "File validation passed: $FILE_PATH"
}

# Function to detect file format
detect_file_format() {
    if [[ -n "$IMPORT_FORMAT" ]]; then
        # Validate manually specified format
        if [[ ! " ${SUPPORTED_FORMATS[*]} " =~ " $IMPORT_FORMAT " ]]; then
            print_error "Unsupported format: $IMPORT_FORMAT"
            print_info "Supported formats: ${SUPPORTED_FORMATS[*]}"
            exit 1
        fi
        return 0
    fi
    
    # Auto-detect format from file extension
    local filename
    filename=$(basename "$FILE_PATH")
    
    case "$filename" in
        *.sql)
            IMPORT_FORMAT="sql"
            ;;
        *.sql.gz|*.gz)
            IMPORT_FORMAT="gz"
            ;;
        *.sql.bz2|*.bz2)
            IMPORT_FORMAT="bz2"
            ;;
        *.sql.xz|*.xz)
            IMPORT_FORMAT="xz"
            ;;
        *.csv)
            IMPORT_FORMAT="csv"
            ;;
        *.tsv)
            IMPORT_FORMAT="tsv"
            CSV_DELIMITER=$'\t'
            ;;
        *.json)
            IMPORT_FORMAT="json"
            ;;
        *.xml)
            IMPORT_FORMAT="xml"
            ;;
        *)
            print_error "Cannot auto-detect format for: $filename"
            print_info "Please specify format with --format option"
            print_info "Supported formats: ${SUPPORTED_FORMATS[*]}"
            exit 1
            ;;
    esac
    
    print_info "Detected format: $IMPORT_FORMAT"
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

# Function to prompt for database if not specified
prompt_for_database() {
    if [[ -n "$DATABASE_NAME" ]]; then
        return 0
    fi
    
    # For non-SQL formats, database is required
    if [[ "$IMPORT_FORMAT" != "sql" && "$IMPORT_FORMAT" != "gz" && "$IMPORT_FORMAT" != "bz2" && "$IMPORT_FORMAT" != "xz" ]]; then
        print_error "Database name is required for $IMPORT_FORMAT imports"
        read -p "Enter database name: " DATABASE_NAME
        
        if [[ -z "$DATABASE_NAME" ]]; then
            print_error "Database name cannot be empty"
            exit 1
        fi
    fi
    
    # For SQL dumps, try to extract database name or prompt
    if [[ -z "$DATABASE_NAME" ]]; then
        print_info "No database specified. Available databases:"
        
        local databases
        if ! databases=$(get_database_list); then
            print_error "Failed to retrieve database list"
            exit 1
        fi
        
        if [[ -z "$databases" ]]; then
            print_warning "No databases found"
            if confirm_action "Create new database?"; then
                read -p "Enter new database name: " DATABASE_NAME
                CREATE_DATABASE=true
            else
                exit 1
            fi
        else
            # Convert to array for selection menu
            local db_array=()
            while IFS= read -r db; do
                # Skip system databases
                if [[ "$db" != "information_schema" && "$db" != "performance_schema" && "$db" != "mysql" && "$db" != "sys" ]]; then
                    db_array+=("$db")
                fi
            done <<< "$databases"
            
            # Add "Create new database" option
            db_array+=("Create new database")
            
            local selection
            selection=$(show_selection_menu "Choose target database" "${db_array[@]}")
            
            if [[ "$selection" == "Create new database" ]]; then
                read -p "Enter new database name: " DATABASE_NAME
                CREATE_DATABASE=true
            else
                DATABASE_NAME="$selection"
            fi
        fi
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

# Function to check if database exists
database_exists() {
    local db_name="$1"
    local mysql_cmd
    mysql_cmd=$(build_mysql_command "mysql")
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would check if database exists: $db_name"
        return 0
    fi
    
    $mysql_cmd -e "USE $db_name;" &>/dev/null
}

# Function to create database if needed
create_database_if_needed() {
    if [[ "$CREATE_DATABASE" == true ]]; then
        print_info "Creating database: $DATABASE_NAME"
        
        local mysql_cmd
        mysql_cmd=$(build_mysql_command "mysql")
        
        local create_cmd="CREATE DATABASE IF NOT EXISTS \`$DATABASE_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would create database: $create_cmd"
            return 0
        fi
        
        if $mysql_cmd -e "$create_cmd"; then
            print_success "Database created: $DATABASE_NAME"
        else
            print_error "Failed to create database: $DATABASE_NAME"
            exit 1
        fi
    elif [[ -n "$DATABASE_NAME" ]]; then
        # Check if database exists
        if ! database_exists "$DATABASE_NAME"; then
            print_error "Database does not exist: $DATABASE_NAME"
            if confirm_action "Create database '$DATABASE_NAME'?"; then
                CREATE_DATABASE=true
                create_database_if_needed
            else
                exit 1
            fi
        fi
    fi
}

# Function to get file size for progress calculation
get_file_size() {
    local file="$1"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "1048576"  # 1MB for dry run
        return 0
    fi
    
    stat --format="%s" "$file" 2>/dev/null || echo "0"
}

# Function to build decompression command
build_decompression_command() {
    local format="$1"
    
    case "$format" in
        gz)
            echo "gunzip -c"
            ;;
        bz2)
            echo "bunzip2 -c"
            ;;
        xz)
            echo "unxz -c"
            ;;
        sql)
            echo "cat"
            ;;
        *)
            echo "cat"
            ;;
    esac
}

# Function to import SQL file
import_sql() {
    print_info "Importing SQL file: $FILE_PATH"
    
    local mysql_cmd
    mysql_cmd=$(build_mysql_command "mysql")
    
    # Add database to command if specified
    if [[ -n "$DATABASE_NAME" ]]; then
        mysql_cmd="$mysql_cmd $DATABASE_NAME"
    fi
    
    # Build decompression command
    local decomp_cmd
    decomp_cmd=$(build_decompression_command "$IMPORT_FORMAT")
    
    # Build complete command
    local full_command
    if [[ "$SHOW_PROGRESS" == true ]]; then
        local file_size
        file_size=$(get_file_size "$FILE_PATH")
        full_command="$decomp_cmd '$FILE_PATH' | pv -p -t -e -r -b -s $file_size | $mysql_cmd"
    else
        full_command="$decomp_cmd '$FILE_PATH' | $mysql_cmd"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would execute: $full_command"
        return 0
    fi
    
    print_info "Executing import command..."
    if [[ "$VERBOSE" == true ]]; then
        print_info "Command: $full_command"
    fi
    
    if eval "$full_command"; then
        print_success "SQL import completed successfully!"
    else
        print_error "SQL import failed!"
        exit 1
    fi
}

# Function to get CSV column count and sample data
analyze_csv() {
    local file="$1"
    local decomp_cmd
    decomp_cmd=$(build_decompression_command "$IMPORT_FORMAT")
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would analyze CSV file: $file"
        return 0
    fi
    
    # Get first few lines to analyze structure
    local sample_data
    sample_data=$($decomp_cmd "$file" | head -5)
    
    print_info "CSV file analysis:"
    echo "$sample_data" | head -3
    
    # Count columns from first line
    local column_count
    column_count=$(echo "$sample_data" | head -1 | tr "$CSV_DELIMITER" '\n' | wc -l)
    print_info "Detected $column_count columns"
    
    return 0
}

# Function to generate table schema from CSV
generate_csv_table_schema() {
    local table_name="$1"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would generate table schema for: $table_name"
        return 0
    fi
    
    print_info "Generating table schema for CSV import..."
    
    # Get header row if present
    local decomp_cmd
    decomp_cmd=$(build_decompression_command "$IMPORT_FORMAT")
    
    local headers
    if [[ "$CSV_HEADERS" == true ]]; then
        headers=$($decomp_cmd "$FILE_PATH" | head -1)
    else
        # Generate generic column names
        local column_count
        column_count=$($decomp_cmd "$FILE_PATH" | head -1 | tr "$CSV_DELIMITER" '\n' | wc -l)
        headers=""
        for ((i=1; i<=column_count; i++)); do
            if [[ $i -gt 1 ]]; then
                headers="${headers}${CSV_DELIMITER}"
            fi
            headers="${headers}column_$i"
        done
    fi
    
    # Build CREATE TABLE statement
    local create_sql="CREATE TABLE IF NOT EXISTS \`$table_name\` ("
    local first_col=true
    
    IFS="$CSV_DELIMITER" read -ra COLS <<< "$headers"
    for col in "${COLS[@]}"; do
        # Clean column name
        col=$(echo "$col" | tr -d '"' | tr ' ' '_' | tr -cd '[:alnum:]_')
        
        if [[ "$first_col" == false ]]; then
            create_sql="$create_sql,"
        fi
        create_sql="$create_sql \`$col\` TEXT"
        first_col=false
    done
    
    create_sql="$create_sql ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;"
    
    # Execute CREATE TABLE
    local mysql_cmd
    mysql_cmd=$(build_mysql_command "mysql")
    mysql_cmd="$mysql_cmd $DATABASE_NAME"
    
    if [[ "$VERBOSE" == true ]]; then
        print_info "CREATE TABLE SQL: $create_sql"
    fi
    
    if $mysql_cmd -e "$create_sql"; then
        print_success "Table created: $table_name"
    else
        print_error "Failed to create table: $table_name"
        exit 1
    fi
}

# Function to import CSV file
import_csv() {
    # Require table name for CSV imports
    if [[ -z "$TABLE_NAME" ]]; then
        local default_table
        default_table=$(basename "$FILE_PATH" | sed 's/\.[^.]*$//')
        read -p "Enter table name [$default_table]: " TABLE_NAME
        if [[ -z "$TABLE_NAME" ]]; then
            TABLE_NAME="$default_table"
        fi
    fi
    
    print_info "Importing CSV file: $FILE_PATH to table: $TABLE_NAME"
    
    # Analyze CSV structure
    analyze_csv "$FILE_PATH"
    
    # Drop existing table if requested
    if [[ "$DROP_EXISTING" == true ]]; then
        print_info "Dropping existing table: $TABLE_NAME"
        local mysql_cmd
        mysql_cmd=$(build_mysql_command "mysql")
        mysql_cmd="$mysql_cmd $DATABASE_NAME"
        
        if [[ "$DRY_RUN" == false ]]; then
            $mysql_cmd -e "DROP TABLE IF EXISTS \`$TABLE_NAME\`;"
        fi
    fi
    
    # Generate table schema
    generate_csv_table_schema "$TABLE_NAME"
    
    # Build LOAD DATA command
    local mysql_cmd
    mysql_cmd=$(build_mysql_command "mysql")
    mysql_cmd="$mysql_cmd $DATABASE_NAME"
    
    # Create temporary named pipe for progress monitoring
    local temp_pipe
    temp_pipe=$(mktemp -u)
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would import CSV using LOAD DATA LOCAL INFILE"
        echo "[DRY-RUN] Table: $TABLE_NAME"
        echo "[DRY-RUN] Delimiter: '$CSV_DELIMITER'"
        echo "[DRY-RUN] Headers: $CSV_HEADERS"
        return 0
    fi
    
    # Prepare LOAD DATA statement
    local load_sql="LOAD DATA LOCAL INFILE '/dev/stdin'
        INTO TABLE \`$TABLE_NAME\`
        CHARACTER SET utf8mb4
        FIELDS TERMINATED BY '$CSV_DELIMITER'
        ENCLOSED BY '$CSV_ENCLOSED_BY'
        ESCAPED BY '$CSV_ESCAPED_BY'
        LINES TERMINATED BY '\\n'"
    
    if [[ "$CSV_HEADERS" == true ]]; then
        load_sql="$load_sql IGNORE 1 ROWS"
    fi
    
    # Build complete command with progress
    local decomp_cmd
    decomp_cmd=$(build_decompression_command "$IMPORT_FORMAT")
    
    local full_command
    if [[ "$SHOW_PROGRESS" == true ]]; then
        local file_size
        file_size=$(get_file_size "$FILE_PATH")
        full_command="$decomp_cmd '$FILE_PATH' | pv -p -t -e -r -b -s $file_size | $mysql_cmd --local-infile=1 -e \"$load_sql\""
    else
        full_command="$decomp_cmd '$FILE_PATH' | $mysql_cmd --local-infile=1 -e \"$load_sql\""
    fi
    
    print_info "Executing CSV import command..."
    if [[ "$VERBOSE" == true ]]; then
        print_info "Command: $full_command"
    fi
    
    if eval "$full_command"; then
        # Get row count
        local row_count
        row_count=$($mysql_cmd -e "SELECT COUNT(*) FROM \`$TABLE_NAME\`;" --batch --skip-column-names)
        print_success "CSV import completed successfully!"
        print_success "Rows imported: $row_count"
    else
        print_error "CSV import failed!"
        exit 1
    fi
}

# Function to import JSON file
import_json() {
    # Require table name for JSON imports
    if [[ -z "$TABLE_NAME" ]]; then
        local default_table
        default_table=$(basename "$FILE_PATH" | sed 's/\.[^.]*$//')
        read -p "Enter table name [$default_table]: " TABLE_NAME
        if [[ -z "$TABLE_NAME" ]]; then
            TABLE_NAME="$default_table"
        fi
    fi
    
    print_info "Importing JSON file: $FILE_PATH to table: $TABLE_NAME"
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        print_error "jq (JSON processor) not found"
        print_info "Install with: sudo apt install jq"
        exit 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would import JSON file to table: $TABLE_NAME"
        echo "[DRY-RUN] JSON path: ${JSON_PATH:-'root'}"
        return 0
    fi
    
    # Drop existing table if requested
    if [[ "$DROP_EXISTING" == true ]]; then
        print_info "Dropping existing table: $TABLE_NAME"
        local mysql_cmd
        mysql_cmd=$(build_mysql_command "mysql")
        mysql_cmd="$mysql_cmd $DATABASE_NAME"
        $mysql_cmd -e "DROP TABLE IF EXISTS \`$TABLE_NAME\`;"
    fi
    
    # Create table with JSON column
    local mysql_cmd
    mysql_cmd=$(build_mysql_command "mysql")
    mysql_cmd="$mysql_cmd $DATABASE_NAME"
    
    local create_sql="CREATE TABLE IF NOT EXISTS \`$TABLE_NAME\` (
        id INT AUTO_INCREMENT PRIMARY KEY,
        data JSON,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;"
    
    $mysql_cmd -e "$create_sql"
    print_success "Table created: $TABLE_NAME"
    
    # Process JSON file
    local decomp_cmd
    decomp_cmd=$(build_decompression_command "$IMPORT_FORMAT")
    
    local json_processor="jq -c '.'"
    if [[ -n "$JSON_PATH" ]]; then
        json_processor="jq -c '$JSON_PATH'"
    fi
    
    # Import JSON data
    local full_command
    if [[ "$SHOW_PROGRESS" == true ]]; then
        local file_size
        file_size=$(get_file_size "$FILE_PATH")
        full_command="$decomp_cmd '$FILE_PATH' | pv -p -t -e -r -b -s $file_size | $json_processor | while IFS= read -r line; do $mysql_cmd -e \"INSERT INTO \\\`$TABLE_NAME\\\` (data) VALUES ('\$line');\"; done"
    else
        full_command="$decomp_cmd '$FILE_PATH' | $json_processor | while IFS= read -r line; do $mysql_cmd -e \"INSERT INTO \\\`$TABLE_NAME\\\` (data) VALUES ('\$line');\"; done"
    fi
    
    print_info "Executing JSON import command..."
    if [[ "$VERBOSE" == true ]]; then
        print_info "Command: $full_command"
    fi
    
    if eval "$full_command"; then
        # Get row count
        local row_count
        row_count=$($mysql_cmd -e "SELECT COUNT(*) FROM \`$TABLE_NAME\`;" --batch --skip-column-names)
        print_success "JSON import completed successfully!"
        print_success "Rows imported: $row_count"
    else
        print_error "JSON import failed!"
        exit 1
    fi
}

# Function to show import summary
show_import_summary() {
    echo
    print_info "=== Import Summary ==="
    print_info "File: $FILE_PATH"
    print_info "Format: $IMPORT_FORMAT"
    print_info "Database: ${DATABASE_NAME:-'(embedded in SQL)'}"
    
    if [[ -n "$TABLE_NAME" ]]; then
        print_info "Table: $TABLE_NAME"
    fi
    
    local file_size
    file_size=$(du -h "$FILE_PATH" | cut -f1)
    print_info "File size: $file_size"
    
    echo
    print_success "Import process completed! 🚀"
}

# Main function
main() {
    show_script_header "MariaDB Import Script"
    
    # Check prerequisites
    check_prerequisites
    
    # Validate file
    validate_file
    
    # Detect file format
    detect_file_format
    
    # Prompt for credentials
    prompt_for_credentials
    
    # Prompt for database
    prompt_for_database
    
    # Create database if needed
    create_database_if_needed
    
    # Show import info and confirm
    echo
    print_info "=== Import Configuration ==="
    print_info "File: $FILE_PATH"
    print_info "Format: $IMPORT_FORMAT"
    print_info "Database: $DATABASE_NAME"
    if [[ -n "$TABLE_NAME" ]]; then
        print_info "Table: $TABLE_NAME"
    fi
    
    if ! confirm_action "Proceed with import?" "Y"; then
        print_info "Import cancelled"
        exit 0
    fi
    
    # Perform import based on format
    case "$IMPORT_FORMAT" in
        sql|gz|bz2|xz)
            import_sql
            ;;
        csv|tsv)
            import_csv
            ;;
        json)
            import_json
            ;;
        xml)
            print_error "XML format not yet implemented"
            exit 1
            ;;
        *)
            print_error "Unsupported format: $IMPORT_FORMAT"
            exit 1
            ;;
    esac
    
    # Show summary
    show_import_summary
}

# Run main function
main "$@"
