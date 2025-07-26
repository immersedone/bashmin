#!/bin/bash

# BashMin User Creation Script
# Creates system users for DevOps and security operations
# Author: BashMin Team
# Version: 1.0

set -euo pipefail

# Load helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/system.sh"

# Import colors from common.sh
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# User configuration
declare -A USERS=(
    ["devops"]="DevOps Operations User"
    ["shadower"]="Security Monitoring User"
)

# User groups and permissions
DEVOPS_GROUPS="sudo,docker,www-data"
SHADOWER_GROUPS="adm,systemd-journal"

# Home directory permissions
HOME_PERMS="750"

# Function to print header
print_header() {
    echo
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}            $1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

# Function to check if user exists
user_exists() {
    local username="$1"
    id "$username" &>/dev/null
}

# Function to create user with proper setup
create_user() {
    local username="$1"
    local description="$2"
    local groups="$3"
    
    print_info "Creating user: $username ($description)"
    
    if user_exists "$username"; then
        print_warning "User $username already exists"
        return 0
    fi
    
    # Create user with home directory
    if sudo useradd -m -s /bin/bash -c "$description" "$username"; then
        print_success "Created user: $username"
    else
        print_error "Failed to create user: $username"
        return 1
    fi
    
    # Add user to groups
    if [[ -n "$groups" ]]; then
        if sudo usermod -a -G "$groups" "$username"; then
            print_success "Added $username to groups: $groups"
        else
            print_warning "Failed to add $username to some groups: $groups"
        fi
    fi
    
    # Set home directory permissions
    local home_dir="/home/$username"
    if [[ -d "$home_dir" ]]; then
        if sudo chmod "$HOME_PERMS" "$home_dir"; then
            print_success "Set permissions $HOME_PERMS on $home_dir"
        else
            print_warning "Failed to set permissions on $home_dir"
        fi
    fi
    
    # Create .ssh directory with proper permissions
    local ssh_dir="$home_dir/.ssh"
    if sudo mkdir -p "$ssh_dir"; then
        sudo chown "$username:$username" "$ssh_dir"
        sudo chmod 700 "$ssh_dir"
        print_success "Created SSH directory for $username"
    else
        print_warning "Failed to create SSH directory for $username"
    fi
}

# Function to setup devops user specifics
setup_devops_user() {
    local username="devops"
    
    print_info "Setting up DevOps user specifics..."
    
    # Create common directories for DevOps work
    local work_dirs=(
        "/home/$username/scripts"
        "/home/$username/deployments"
        "/home/$username/configs"
        "/home/$username/backups"
    )
    
    for dir in "${work_dirs[@]}"; do
        if sudo mkdir -p "$dir"; then
            sudo chown "$username:$username" "$dir"
            sudo chmod 755 "$dir"
            print_success "Created: $dir"
        else
            print_warning "Failed to create: $dir"
        fi
    done
    
    # Add useful aliases to .bashrc
    local bashrc="/home/$username/.bashrc"
    if [[ -f "$bashrc" ]]; then
        sudo tee -a "$bashrc" > /dev/null << 'EOF'

# DevOps aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ps='ps aux'
alias ports='netstat -tuln'
alias syslog='sudo tail -f /var/log/syslog'
alias reload-nginx='sudo systemctl reload nginx'
alias reload-apache='sudo systemctl reload apache2'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline'

EOF
        sudo chown "$username:$username" "$bashrc"
        print_success "Added DevOps aliases to .bashrc"
    fi
}

# Function to setup shadower user specifics  
setup_shadower_user() {
    local username="shadower"
    
    print_info "Setting up Shadower user specifics..."
    
    # Create directories for security monitoring
    local security_dirs=(
        "/home/$username/logs"
        "/home/$username/reports"
        "/home/$username/scripts"
        "/home/$username/configs"
    )
    
    for dir in "${security_dirs[@]}"; do
        if sudo mkdir -p "$dir"; then
            sudo chown "$username:$username" "$dir"
            sudo chmod 700 "$dir"  # More restrictive for security user
            print_success "Created: $dir"
        else
            print_warning "Failed to create: $dir"
        fi
    done
    
    # Add security-focused aliases to .bashrc
    local bashrc="/home/$username/.bashrc"
    if [[ -f "$bashrc" ]]; then
        sudo tee -a "$bashrc" > /dev/null << 'EOF'

# Security monitoring aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ps='ps aux'
alias ports='netstat -tuln'
alias conns='ss -tuln'

# Security logs
alias auth-log='sudo tail -f /var/log/auth.log'
alias syslog='sudo tail -f /var/log/syslog'
alias fail2ban-log='sudo tail -f /var/log/fail2ban.log'
alias ufw-log='sudo tail -f /var/log/ufw.log'

# Security checks
alias listening='sudo netstat -plnt'
alias processes='sudo ps auxf'
alias logins='last -10'
alias failed-logins='sudo grep "Failed password" /var/log/auth.log | tail -10'

EOF
        sudo chown "$username:$username" "$bashrc"
        print_success "Added security aliases to .bashrc"
    fi
}

# Function to verify users
verify_users() {
    print_info "Verifying created users..."
    
    local all_good=true
    
    for username in "${!USERS[@]}"; do
        if user_exists "$username"; then
            local user_info=$(id "$username")
            print_success "✓ $username exists: $user_info"
        else
            print_error "✗ $username missing"
            all_good=false
        fi
    done
    
    if $all_good; then
        print_success "All users created successfully!"
        return 0
    else
        print_error "Some users are missing"
        return 1
    fi
}

# Function to show user summary
show_user_summary() {
    echo
    print_info "Created users summary:"
    echo
    echo "├── devops"
    echo "│   ├── Groups: $DEVOPS_GROUPS"
    echo "│   ├── Purpose: DevOps operations, deployments, server management"
    echo "│   └── Directories: scripts, deployments, configs, backups"
    echo "│"
    echo "└── shadower"
    echo "    ├── Groups: $SHADOWER_GROUPS" 
    echo "    ├── Purpose: Security monitoring, log analysis, threat detection"
    echo "    └── Directories: logs, reports, scripts, configs"
    echo
    print_info "Both users have SSH directories configured and custom aliases"
    echo
}

# Main installation function
main() {
    print_header "BashMin User Creation Script"
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_info "Running as root"
    elif sudo -n true 2>/dev/null; then
        print_info "Sudo access confirmed"
    else
        print_error "This script requires sudo access"
        exit 1
    fi
    
    # Create devops user
    create_user "devops" "${USERS[devops]}" "$DEVOPS_GROUPS"
    setup_devops_user
    
    # Create shadower user  
    create_user "shadower" "${USERS[shadower]}" "$SHADOWER_GROUPS"
    setup_shadower_user
    
    # Verify everything is created properly
    if verify_users; then
        print_success "User creation completed successfully!"
        show_user_summary
        return 0
    else
        print_error "User creation failed!"
        return 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
