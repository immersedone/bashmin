#!/bin/bash
#
# Script: hosts/update-hosts.sh
# Description: Manage hosts file entries with IP and hostname mapping
# Usage: ./update-hosts.sh [OPTIONS] HOSTNAME [IP]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly HOSTS_FILE="/etc/hosts"
readonly HOSTS_BACKUP_DIR="/var/backups/hosts"
readonly DEFAULT_IP="127.0.0.1"

# Configuration variables
HOSTNAME=""
IP_ADDRESS=""
ACTION="add"
FORCE_UPDATE=false
CREATE_BACKUP=true
VERBOSE=false
DRY_RUN=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ip)
            IP_ADDRESS="$2"
            shift 2
            ;;
        -a|--action)
            ACTION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_UPDATE=true
            shift
            ;;
        --no-backup)
            CREATE_BACKUP=false
            shift
            ;;
        -q|--quiet)
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
        -*)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            # Positional arguments
            if [[ -z "$HOSTNAME" ]]; then
                HOSTNAME="$1"
            elif [[ -z "$IP_ADDRESS" ]]; then
                IP_ADDRESS="$1"
            else
                print_error "Too many arguments: $1"
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
Usage: $0 [OPTIONS] HOSTNAME [IP]

Manage hosts file entries with IP and hostname mapping.

ARGUMENTS:
    HOSTNAME                Hostname to add/update/remove
    IP                      IP address (default: $DEFAULT_IP)

OPTIONS:
    -i, --ip IP             Set IP address explicitly
    -a, --action ACTION     Action to perform: add, update, remove, check (default: $ACTION)
    -f, --force             Force update even if entry exists
    --no-backup             Skip creating backup of hosts file
    -q, --quiet             Suppress output (useful for scripts)
    --verbose               Enable verbose output
    --dry-run               Show what would be done without executing
    -h, --help              Show this help message

ACTIONS:
    add                     Add new hostname entry (fails if exists unless --force)
    update                  Update existing hostname entry (creates if not exists)
    remove                  Remove hostname entry
    check                   Check if hostname exists (exit code 0=exists, 1=not found)
    list                    List all custom entries (non-system)

EXAMPLES:
    $0 example.com                          # Add example.com → 127.0.0.1
    $0 api.local 192.168.1.100             # Add api.local → 192.168.1.100
    $0 --ip 10.0.0.1 myapp.test            # Add myapp.test → 10.0.0.1
    $0 --action update site.local 127.0.0.1 # Update existing entry
    $0 --action remove old-site.com        # Remove entry
    $0 --action check api.local             # Check if entry exists
    $0 --action list                        # List all custom entries
    $0 --dry-run --verbose site.com        # Test without changes

SCRIPT INTEGRATION:
    # From other scripts (quiet mode)
    if $0 --quiet --action check "mysite.local"; then
        echo "Host exists"
    else
        $0 --quiet --action add "mysite.local" "127.0.0.1"
    fi

EXIT CODES:
    0    Success
    1    General error
    2    Host not found (for check action)
    3    Host already exists (for add action without --force)
    4    Permission denied
    5    Invalid arguments

NOTES:
    - Requires sudo privileges to modify $HOSTS_FILE
    - Creates automatic backup before changes
    - Handles IPv4 and IPv6 addresses
    - Preserves original hosts file formatting
    - Comments are preserved and respected

EOF
}

# Function to validate IP address
validate_ip() {
    local ip="$1"
    local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    local ipv6_regex='^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'
    
    if [[ "$ip" =~ $ip_regex ]]; then
        # Validate IPv4 octets
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    elif [[ "$ip" =~ $ipv6_regex ]]; then
        # Basic IPv6 validation
        return 0
    else
        return 1
    fi
}

# Function to validate hostname
validate_hostname() {
    local hostname="$1"
    local hostname_regex='^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'
    
    if [[ ${#hostname} -gt 253 ]]; then
        return 1
    fi
    
    if [[ "$hostname" =~ $hostname_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Checking prerequisites..."
    fi
    
    # Check if hosts file exists
    if [[ ! -f "$HOSTS_FILE" ]]; then
        print_error "Hosts file not found: $HOSTS_FILE"
        exit 1
    fi
    
    # Check if we need sudo privileges (only for write operations)
    if [[ "$ACTION" != "check" && "$ACTION" != "list" && "$DRY_RUN" == false ]]; then
        if [[ $EUID -ne 0 && ! -w "$HOSTS_FILE" ]]; then
            if ! sudo -n true 2>/dev/null; then
                print_error "This operation requires sudo privileges to modify $HOSTS_FILE"
                exit 4
            fi
        fi
    fi
    
    # Create backup directory if needed
    if [[ "$CREATE_BACKUP" == true && "$ACTION" != "check" && "$ACTION" != "list" && "$DRY_RUN" == false ]]; then
        if [[ ! -d "$HOSTS_BACKUP_DIR" ]]; then
            sudo mkdir -p "$HOSTS_BACKUP_DIR" 2>/dev/null || {
                print_warning "Cannot create backup directory: $HOSTS_BACKUP_DIR"
                CREATE_BACKUP=false
            }
        fi
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Prerequisites check completed"
    fi
}

# Function to setup defaults
setup_defaults() {
    # Set default IP if not provided
    if [[ -z "$IP_ADDRESS" ]]; then
        IP_ADDRESS="$DEFAULT_IP"
    fi
    
    # Validate hostname
    if [[ -n "$HOSTNAME" ]]; then
        if ! validate_hostname "$HOSTNAME"; then
            print_error "Invalid hostname format: $HOSTNAME"
            exit 5
        fi
    fi
    
    # Validate IP address
    if [[ -n "$IP_ADDRESS" ]]; then
        if ! validate_ip "$IP_ADDRESS"; then
            print_error "Invalid IP address format: $IP_ADDRESS"
            exit 5
        fi
    fi
    
    # Validate action
    case "$ACTION" in
        add|update|remove|check|list)
            ;;
        *)
            print_error "Invalid action: $ACTION"
            print_info "Valid actions: add, update, remove, check, list"
            exit 5
            ;;
    esac
    
    # Check required arguments
    if [[ "$ACTION" != "list" && -z "$HOSTNAME" ]]; then
        print_error "Hostname is required for action: $ACTION"
        show_help
        exit 5
    fi
}

# Function to create backup
create_backup() {
    if [[ "$CREATE_BACKUP" == false || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    local backup_file="$HOSTS_BACKUP_DIR/hosts.$(date +%Y%m%d_%H%M%S)"
    
    if sudo cp "$HOSTS_FILE" "$backup_file" 2>/dev/null; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Backup created: $backup_file"
        fi
    else
        print_warning "Failed to create backup"
    fi
}

# Function to check if hostname exists
hostname_exists() {
    local hostname="$1"
    
    # Check for exact hostname match (not in comments)
    if grep -E "^[^#]*[[:space:]]$hostname([[:space:]]|$)" "$HOSTS_FILE" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to get current IP for hostname
get_hostname_ip() {
    local hostname="$1"
    
    # Extract IP address for the hostname
    grep -E "^[^#]*[[:space:]]$hostname([[:space:]]|$)" "$HOSTS_FILE" 2>/dev/null | \
        head -n1 | \
        awk '{print $1}' || echo ""
}

# Function to add hostname entry
add_hostname() {
    local hostname="$1"
    local ip="$2"
    
    if [[ "$QUIET" == false ]]; then
        print_info "Adding hostname: $hostname → $ip"
    fi
    
    # Check if hostname already exists
    if hostname_exists "$hostname"; then
        if [[ "$FORCE_UPDATE" == false ]]; then
            local current_ip
            current_ip=$(get_hostname_ip "$hostname")
            print_error "Hostname '$hostname' already exists with IP: $current_ip"
            print_info "Use --force to update or --action update"
            exit 3
        else
            # Force update
            update_hostname "$hostname" "$ip"
            return $?
        fi
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would add: $ip $hostname"
        return 0
    fi
    
    # Create backup
    create_backup
    
    # Add entry to hosts file
    local entry="$ip $hostname"
    local temp_file=$(mktemp)
    
    # Copy existing content and add new entry
    {
        cat "$HOSTS_FILE"
        echo ""
        echo "# Added by update-hosts.sh on $(date)"
        echo "$entry"
    } > "$temp_file"
    
    # Install new hosts file
    if sudo mv "$temp_file" "$HOSTS_FILE"; then
        if [[ "$QUIET" == false ]]; then
            print_success "Hostname added successfully: $hostname → $ip"
        fi
        return 0
    else
        print_error "Failed to update hosts file"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to update hostname entry
update_hostname() {
    local hostname="$1"
    local ip="$2"
    
    if [[ "$QUIET" == false ]]; then
        print_info "Updating hostname: $hostname → $ip"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        if hostname_exists "$hostname"; then
            local current_ip
            current_ip=$(get_hostname_ip "$hostname")
            echo "[DRY-RUN] Would update: $hostname ($current_ip → $ip)"
        else
            echo "[DRY-RUN] Would add: $ip $hostname"
        fi
        return 0
    fi
    
    # Create backup
    create_backup
    
    local temp_file=$(mktemp)
    local entry_updated=false
    
    # Process hosts file line by line
    while IFS= read -r line; do
        # Check if this line contains our hostname
        if echo "$line" | grep -E "^[^#]*[[:space:]]$hostname([[:space:]]|$)" > /dev/null; then
            # Update the IP address for this hostname
            echo "$ip $hostname"
            entry_updated=true
        else
            echo "$line"
        fi
    done < "$HOSTS_FILE" > "$temp_file"
    
    # If hostname wasn't found, add it
    if [[ "$entry_updated" == false ]]; then
        {
            echo ""
            echo "# Added by update-hosts.sh on $(date)"
            echo "$ip $hostname"
        } >> "$temp_file"
    fi
    
    # Install new hosts file
    if sudo mv "$temp_file" "$HOSTS_FILE"; then
        if [[ "$QUIET" == false ]]; then
            if [[ "$entry_updated" == true ]]; then
                print_success "Hostname updated successfully: $hostname → $ip"
            else
                print_success "Hostname added successfully: $hostname → $ip"
            fi
        fi
        return 0
    else
        print_error "Failed to update hosts file"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to remove hostname entry
remove_hostname() {
    local hostname="$1"
    
    if [[ "$QUIET" == false ]]; then
        print_info "Removing hostname: $hostname"
    fi
    
    # Check if hostname exists
    if ! hostname_exists "$hostname"; then
        if [[ "$QUIET" == false ]]; then
            print_warning "Hostname '$hostname' not found in hosts file"
        fi
        return 2
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        local current_ip
        current_ip=$(get_hostname_ip "$hostname")
        echo "[DRY-RUN] Would remove: $hostname ($current_ip)"
        return 0
    fi
    
    # Create backup
    create_backup
    
    local temp_file=$(mktemp)
    
    # Remove lines containing the hostname
    grep -v -E "^[^#]*[[:space:]]$hostname([[:space:]]|$)" "$HOSTS_FILE" > "$temp_file"
    
    # Install new hosts file
    if sudo mv "$temp_file" "$HOSTS_FILE"; then
        if [[ "$QUIET" == false ]]; then
            print_success "Hostname removed successfully: $hostname"
        fi
        return 0
    else
        print_error "Failed to update hosts file"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to check hostname
check_hostname() {
    local hostname="$1"
    
    if hostname_exists "$hostname"; then
        local current_ip
        current_ip=$(get_hostname_ip "$hostname")
        if [[ "$QUIET" == false ]]; then
            print_success "Hostname found: $hostname → $current_ip"
        fi
        return 0
    else
        if [[ "$QUIET" == false ]]; then
            print_info "Hostname not found: $hostname"
        fi
        return 2
    fi
}

# Function to list custom entries
list_hostnames() {
    if [[ "$QUIET" == false ]]; then
        print_info "Custom hostname entries:"
        echo "========================"
    fi
    
    # List non-system entries (skip localhost, broadcast, etc.)
    grep -E "^[0-9]" "$HOSTS_FILE" | \
        grep -v -E "(localhost|broadcasthost|ip6-|::1)" | \
        while read -r line; do
            local ip=$(echo "$line" | awk '{print $1}')
            local hostname=$(echo "$line" | awk '{print $2}')
            
            if [[ -n "$ip" && -n "$hostname" ]]; then
                if [[ "$QUIET" == true ]]; then
                    echo "$hostname $ip"
                else
                    printf "%-30s → %s\n" "$hostname" "$ip"
                fi
            fi
        done
    
    if [[ "$QUIET" == false ]]; then
        echo "========================"
        local count
        count=$(grep -E "^[0-9]" "$HOSTS_FILE" | grep -v -E "(localhost|broadcasthost|ip6-|::1)" | wc -l)
        print_info "Total custom entries: $count"
    fi
}

# Function to perform the requested action
perform_action() {
    case "$ACTION" in
        add)
            add_hostname "$HOSTNAME" "$IP_ADDRESS"
            ;;
        update)
            update_hostname "$HOSTNAME" "$IP_ADDRESS"
            ;;
        remove)
            remove_hostname "$HOSTNAME"
            ;;
        check)
            check_hostname "$HOSTNAME"
            ;;
        list)
            list_hostnames
            ;;
        *)
            print_error "Unknown action: $ACTION"
            exit 1
            ;;
    esac
}

# Main function
main() {
    # Show header only if not quiet
    if [[ "$QUIET" == false ]]; then
        show_script_header "Hosts File Management Script"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Setup defaults and validate input
    setup_defaults
    
    # Show summary if verbose and not quiet
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Operation summary:"
        print_info "  Action: $ACTION"
        if [[ -n "$HOSTNAME" ]]; then
            print_info "  Hostname: $HOSTNAME"
        fi
        if [[ -n "$IP_ADDRESS" && "$ACTION" != "remove" && "$ACTION" != "check" ]]; then
            print_info "  IP Address: $IP_ADDRESS"
        fi
        print_info "  Hosts File: $HOSTS_FILE"
        print_info "  Backup: $(if [[ "$CREATE_BACKUP" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
        
        if [[ "$ACTION" != "check" && "$ACTION" != "list" ]]; then
            if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with hosts file modification?"; then
                print_info "Operation cancelled"
                exit 0
            fi
        fi
    fi
    
    # Perform the requested action
    perform_action
}

# Run main function only if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi