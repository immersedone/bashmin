#!/bin/bash
#
# File: cli.sh
# Description: Command-line interface helper functions
# Usage: source "${SCRIPT_DIR}/_helpers/cli.sh"
#

# Function to parse boolean flags
parse_flag() {
    local flag="$1"
    local args=("$@")
    
    for arg in "${args[@]}"; do
        if [[ "$arg" == "$flag" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to parse value arguments
parse_value_arg() {
    local flag="$1"
    local args=("$@")
    
    for i in "${!args[@]}"; do
        if [[ "${args[$i]}" == "$flag" ]]; then
            if [[ $((i+1)) -lt ${#args[@]} ]]; then
                echo "${args[$((i+1))]}"
                return 0
            else
                return 1
            fi
        fi
    done
    return 1
}

# Function to show script header
show_script_header() {
    local title="$1"
    local width="${2:-50}"
    
    local border=$(printf '=%.0s' $(seq 1 $width))
    
    echo "$border"
    printf "%*s\n" $(((${#title}+$width)/2)) "$title"
    echo "$border"
    echo
}

# Function to display selection menu
show_selection_menu() {
    local prompt="$1"
    local options=("${@:2}")
    local default_option="${options[0]}"
    
    echo >&2
    print_info "$prompt:" >&2
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}" >&2
    done
    
    while true; do
        read -p "Select option (1-${#options[@]}) [default: $default_option]: " choice >&2
        
        # Handle empty input (use default)
        if [[ -z "$choice" ]]; then
            echo "${options[0]}"
            return 0
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "${options[$((choice-1))]}"
            return 0
        else
            print_error "Invalid selection. Please choose 1-${#options[@]} or press Enter for default" >&2
        fi
    done
}
