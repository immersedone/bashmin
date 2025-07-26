#!/bin/bash

# BashMin phpMyAdmin Server Management
# Adds a new database server configuration to phpMyAdmin
# Author: BashMin Team
# Version: 1.0

set -euo pipefail

# Load helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/system.sh"

# Configuration constants
CONFIG_FILE="/etc/phpmyadmin/config.inc.php"
BACKUP_DIR="/var/backups/phpmyadmin"

# Default values
DEFAULT_PORT=3306
DEFAULT_AUTH_TYPE="cookie"
DEFAULT_CONNECT_TYPE="tcp"

# Function to print script header
print_header() {
    echo
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}       PHPMyAdmin Server Configuration${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
}

# Function to validate IP address
validate_ip() {
    local ip="$1"
    
    # Allow localhost and common local addresses
    if [[ "$ip" =~ ^(localhost|127\.0\.0\.1)$ ]]; then
        return 0
    fi
    
    # Validate IPv4 format
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Split IP into octets and validate range
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet < 0 || octet > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    
    # Basic hostname validation (allows FQDN)
    if [[ "$ip" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi
    
    return 1
}

# Function to validate port number
validate_port() {
    local port="$1"
    
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
        return 0
    fi
    return 1
}

# Function to prompt for user input with validation
prompt_with_validation() {
    local prompt="$1"
    local validation_func="$2"
    local default_value="${3:-}"
    local value=""
    
    while true; do
        if [[ -n "$default_value" ]]; then
            read -p "$prompt [$default_value]: " value
            value="${value:-$default_value}"
        else
            read -p "$prompt: " value
        fi
        
        if [[ -n "$value" ]] && $validation_func "$value"; then
            echo "$value"
            return 0
        else
            print_error "Invalid input. Please try again."
        fi
    done
}

# Function to check if configuration file exists
check_config_file() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "PHPMyAdmin configuration file not found: $CONFIG_FILE"
        print_info "Please run the PHPMyAdmin installer first:"
        print_info "bash $PROJECT_ROOT/software/phpmyadmin/install.sh"
        exit 1
    fi
}

# Function to backup configuration file
backup_config() {
    print_info "Creating backup of configuration file..."
    
    # Create backup directory if it doesn't exist
    sudo mkdir -p "$BACKUP_DIR"
    
    # Create timestamped backup
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$BACKUP_DIR/config.inc.php.backup.$timestamp"
    
    sudo cp "$CONFIG_FILE" "$backup_file"
    print_success "Backup created: $backup_file"
}

# Function to get next server index
get_next_server_index() {
    local max_index=0
    
    # Find the highest existing server index
    while IFS= read -r line; do
        if [[ "$line" =~ \$cfg\[\'Servers\'\]\[([0-9]+)\] ]]; then
            local index="${BASH_REMATCH[1]}"
            if (( index > max_index )); then
                max_index=$index
            fi
        fi
    done < "$CONFIG_FILE"
    
    echo $((max_index + 1))
}

# Function to check if server already exists
check_server_exists() {
    local host="$1"
    local port="$2"
    
    if grep -q "\['host'\] = '$host'" "$CONFIG_FILE" && grep -q "\['port'\] = '$port'" "$CONFIG_FILE"; then
        return 0
    fi
    return 1
}

# Function to add server configuration
add_server_config() {
    local server_index="$1"
    local host="$2"
    local port="$3"
    local verbose_name="$4"
    
    print_info "Adding server configuration..."
    
    # Prepare the server configuration block
    local server_config=""
    server_config+="\n// Server $server_index - $verbose_name"
    server_config+="\n\$cfg['Servers'][$server_index]['verbose'] = '$verbose_name';"
    server_config+="\n\$cfg['Servers'][$server_index]['host'] = '$host';"
    server_config+="\n\$cfg['Servers'][$server_index]['port'] = '$port';"
    server_config+="\n\$cfg['Servers'][$server_index]['socket'] = '';"
    server_config+="\n\$cfg['Servers'][$server_index]['connect_type'] = '$DEFAULT_CONNECT_TYPE';"
    server_config+="\n\$cfg['Servers'][$server_index]['auth_type'] = '$DEFAULT_AUTH_TYPE';"
    server_config+="\n\$cfg['Servers'][$server_index]['user'] = '';"
    server_config+="\n\$cfg['Servers'][$server_index]['password'] = '';"
    server_config+="\n\$cfg['Servers'][$server_index]['compress'] = false;"
    server_config+="\n\$cfg['Servers'][$server_index]['AllowNoPassword'] = false;"
    server_config+="\n"
    
    # Find the insertion point (before the closing PHP tag or at the end)
    if grep -q "^?>" "$CONFIG_FILE"; then
        # Insert before closing PHP tag
        sudo sed -i "/^?>/ i\\$server_config" "$CONFIG_FILE"
    else
        # Append to end of file
        echo -e "$server_config" | sudo tee -a "$CONFIG_FILE" > /dev/null
    fi
    
    print_success "Server configuration added successfully!"
}

# Function to display server summary
display_summary() {
    local host="$1"
    local port="$2"
    local verbose_name="$3"
    local server_index="$4"
    
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}     Server Added Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo "Server Details:"
    echo "  • Name: $verbose_name"
    echo "  • Host: $host"
    echo "  • Port: $port"
    echo "  • Index: $server_index"
    echo "  • Auth Type: $DEFAULT_AUTH_TYPE"
    echo "  • Connection Type: $DEFAULT_CONNECT_TYPE"
    echo
    echo "The server is now available in PHPMyAdmin."
    echo "Users will be prompted for their database credentials when connecting."
    echo
}

# Function to validate non-empty string
validate_non_empty() {
    [[ -n "$1" ]]
}

# Main execution function
main() {
    print_header
    
    # Check prerequisites
    check_config_file
    
    print_info "This script will add a new database server to your PHPMyAdmin configuration."
    echo
    
    # Gather server information
    echo -e "${YELLOW}Server Configuration:${NC}"
    
    # Get host/IP
    host=$(prompt_with_validation "Enter server IP address or hostname" validate_ip "localhost")
    
    # Get port
    port=$(prompt_with_validation "Enter server port" validate_port "$DEFAULT_PORT")
    
    # Get verbose name (display name)
    verbose_name=$(prompt_with_validation "Enter display name for this server" validate_non_empty "Database Server ($host:$port)")
    
    echo
    
    # Check if server already exists
    if check_server_exists "$host" "$port"; then
        print_warning "A server with host '$host' and port '$port' already exists in the configuration."
        if ! confirm_action "Do you want to continue and add it anyway?"; then
            print_info "Operation cancelled."
            exit 0
        fi
    fi
    
    # Show summary and confirm
    echo -e "${YELLOW}Configuration Summary:${NC}"
    echo "  • Display Name: $verbose_name"
    echo "  • Host: $host"
    echo "  • Port: $port"
    echo "  • Auth Type: $DEFAULT_AUTH_TYPE"
    echo "  • Connection Type: $DEFAULT_CONNECT_TYPE"
    echo
    
    if ! confirm_action "Add this server to PHPMyAdmin configuration?"; then
        print_info "Operation cancelled."
        exit 0
    fi
    
    # Create backup
    backup_config
    
    # Get next server index
    server_index=$(get_next_server_index)
    
    # Add server configuration
    add_server_config "$server_index" "$host" "$port" "$verbose_name"
    
    # Display success summary
    display_summary "$host" "$port" "$verbose_name" "$server_index"
    
    # Suggest restart if needed
    if systemctl is-active --quiet apache2 || systemctl is-active --quiet nginx; then
        echo -e "${YELLOW}Note:${NC} You may need to restart your web server to apply changes:"
        echo "  • Apache: sudo systemctl reload apache2"
        echo "  • Nginx: sudo systemctl reload nginx"
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
