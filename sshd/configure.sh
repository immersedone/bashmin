#!/bin/bash
#
# Script: sshd/configure.sh
# Description: Configure OpenSSH daemon with security hardening and bashmin integration
# Usage: ./configure.sh [OPTIONS]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly SSHD_BANNER="/etc/ssh/sshd-banner"
readonly BASHMIN_CONFIG_SOURCE="$SCRIPT_DIR/sshd_config"
readonly BASHMIN_BANNER_SOURCE="$SCRIPT_DIR/sshd-banner"
readonly SSH_SERVICE="ssh"
readonly DEFAULT_SSH_PORT="22"
readonly DEFAULT_MAX_AUTH_TRIES="3"
readonly DEFAULT_MAX_SESSIONS="2"

# Configuration variables
SSH_PORT="$DEFAULT_SSH_PORT"
ALLOW_ROOT_LOGIN="no"
ALLOW_PASSWORD_AUTH=false
ALLOW_EMPTY_PASSWORDS=false
PUBKEY_AUTHENTICATION=true
MAX_AUTH_TRIES="$DEFAULT_MAX_AUTH_TRIES"
MAX_SESSIONS="$DEFAULT_MAX_SESSIONS"
ALLOWED_USERS=()
DENIED_USERS=()
ALLOWED_GROUPS=()
DENIED_GROUPS=()
PASSWORD_AUTH_USERS=()
PASSWORD_AUTH_GROUPS=()
ENABLE_X11_FORWARDING=false
ENABLE_AGENT_FORWARDING=false
ENABLE_TCP_FORWARDING=false
ENABLE_BANNER=true
LOG_LEVEL="VERBOSE"
CLIENT_ALIVE_INTERVAL="600"
CLIENT_ALIVE_COUNT_MAX="3"
LOGIN_GRACE_TIME="60"
PERMIT_TUNNEL=false
ENABLE_COMPRESSION=false
USE_DNS=false
PROTOCOL_VERSION="2"
CUSTOM_CIPHERS=""
CUSTOM_MACS=""
CUSTOM_KEXALGORITHMS=""
BACKUP_EXISTING=true
USE_BASHMIN_CONFIG=false
FORCE_CONFIGURE=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            SSH_PORT="$2"
            shift 2
            ;;
        --allow-root)
            ALLOW_ROOT_LOGIN="$2"
            shift 2
            ;;
        --allow-password)
            ALLOW_PASSWORD_AUTH=true
            shift
            ;;
        --deny-empty-passwords)
            ALLOW_EMPTY_PASSWORDS=false
            shift
            ;;
        --disable-pubkey)
            PUBKEY_AUTHENTICATION=false
            shift
            ;;
        --max-auth-tries)
            MAX_AUTH_TRIES="$2"
            shift 2
            ;;
        --max-sessions)
            MAX_SESSIONS="$2"
            shift 2
            ;;
        --allow-users)
            IFS=',' read -ra ALLOWED_USERS <<< "$2"
            shift 2
            ;;
        --deny-users)
            IFS=',' read -ra DENIED_USERS <<< "$2"
            shift 2
            ;;
        --allow-groups)
            IFS=',' read -ra ALLOWED_GROUPS <<< "$2"
            shift 2
            ;;
        --deny-groups)
            IFS=',' read -ra DENIED_GROUPS <<< "$2"
            shift 2
            ;;
        --password-auth-users)
            IFS=',' read -ra PASSWORD_AUTH_USERS <<< "$2"
            shift 2
            ;;
        --password-auth-groups)
            IFS=',' read -ra PASSWORD_AUTH_GROUPS <<< "$2"
            shift 2
            ;;
        --enable-x11)
            ENABLE_X11_FORWARDING=true
            shift
            ;;
        --enable-agent-forwarding)
            ENABLE_AGENT_FORWARDING=true
            shift
            ;;
        --enable-tcp-forwarding)
            ENABLE_TCP_FORWARDING=true
            shift
            ;;
        --disable-banner)
            ENABLE_BANNER=false
            shift
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --client-alive-interval)
            CLIENT_ALIVE_INTERVAL="$2"
            shift 2
            ;;
        --client-alive-count)
            CLIENT_ALIVE_COUNT_MAX="$2"
            shift 2
            ;;
        --login-grace-time)
            LOGIN_GRACE_TIME="$2"
            shift 2
            ;;
        --enable-tunnel)
            PERMIT_TUNNEL=true
            shift
            ;;
        --enable-compression)
            ENABLE_COMPRESSION=true
            shift
            ;;
        --enable-dns)
            USE_DNS=true
            shift
            ;;
        --ciphers)
            CUSTOM_CIPHERS="$2"
            shift 2
            ;;
        --macs)
            CUSTOM_MACS="$2"
            shift 2
            ;;
        --kex-algorithms)
            CUSTOM_KEXALGORITHMS="$2"
            shift 2
            ;;
        --no-backup)
            BACKUP_EXISTING=false
            shift
            ;;
        --use-bashmin-config)
            USE_BASHMIN_CONFIG=true
            shift
            ;;
        --force)
            FORCE_CONFIGURE=true
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

Configure OpenSSH daemon with security hardening and bashmin integration.

CONNECTION OPTIONS:
    --port PORT                 SSH port number (default: $DEFAULT_SSH_PORT)
    --allow-root MODE           Root login mode: yes, no, prohibit-password (default: no)
    --client-alive-interval SEC Keep-alive interval in seconds (default: 600)
    --client-alive-count MAX    Max keep-alive count before disconnect (default: 3)
    --login-grace-time SEC      Grace time for authentication in seconds (default: 60)

AUTHENTICATION OPTIONS:
    --allow-password            Allow password authentication globally (default: disabled, use specific user/group options instead)
    --deny-empty-passwords      Explicitly deny empty passwords (default: enabled)
    --disable-pubkey            Disable public key authentication
    --max-auth-tries NUM        Maximum authentication attempts (default: $DEFAULT_MAX_AUTH_TRIES)
    --max-sessions NUM          Maximum concurrent sessions (default: $DEFAULT_MAX_SESSIONS)

ACCESS CONTROL:
    --allow-users USERS         Comma-separated list of allowed users
    --deny-users USERS          Comma-separated list of denied users
    --allow-groups GROUPS       Comma-separated list of allowed groups
    --deny-groups GROUPS        Comma-separated list of denied groups
    --password-auth-users USERS Comma-separated list of users allowed password auth (others use pubkey only)
    --password-auth-groups GROUPS Comma-separated list of groups allowed password auth (others use pubkey only)

FORWARDING & TUNNELING:
    --enable-x11                Enable X11 forwarding (default: disabled)
    --enable-agent-forwarding   Enable SSH agent forwarding (default: disabled)
    --enable-tcp-forwarding     Enable TCP forwarding (default: disabled)
    --enable-tunnel             Enable tunnel device forwarding (default: disabled)

SECURITY OPTIONS:
    --log-level LEVEL           Logging level: QUIET, FATAL, ERROR, INFO, VERBOSE, DEBUG (default: VERBOSE)
    --enable-compression        Enable compression (default: disabled for security)
    --enable-dns                Enable DNS lookup for connecting hosts (default: disabled)
    --ciphers LIST              Custom cipher list (comma-separated)
    --macs LIST                 Custom MAC algorithm list (comma-separated)
    --kex-algorithms LIST       Custom key exchange algorithm list (comma-separated)

CONFIGURATION OPTIONS:
    --disable-banner            Disable login banner
    --use-bashmin-config        Use bashmin's hardened SSH configuration template
    --no-backup                 Don't backup existing configuration
    --force                     Force configuration even if SSH is running
    --quiet                     Suppress non-essential output
    --verbose                   Enable verbose output
    --dry-run                   Show what would be configured without executing
    -h, --help                  Show this help message

SECURITY MODES:
    Basic Hardening:            Default settings with key-only authentication
    Bashmin Template:           Use pre-configured hardened template (--use-bashmin-config)
    Custom Security:            Specify custom ciphers, MACs, and algorithms

EXAMPLES:
    # Basic hardening with custom port
    $0 --port 2222 --allow-users admin,deploy

    # Use bashmin's hardened template
    $0 --use-bashmin-config --port 2222

    # Production server with strict access control
    $0 --port 2222 --allow-users admin --deny-users root --max-auth-tries 2

    # Development server with password auth for specific users
    $0 --password-auth-users dev,test --enable-x11 --allow-users dev,test

    # Allow password auth for developers group only
    $0 --password-auth-groups developers --allow-groups developers,admins

    # High-security configuration with custom crypto
    $0 --port 2222 --ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com \
       --macs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com

NOTES:
    - Requires sudo privileges
    - Automatically installs OpenSSH server if not present
    - Automatically tests configuration before applying
    - Creates backup of existing configuration (unless --no-backup)
    - Restarts SSH service after successful configuration
    - Use --dry-run to preview changes before applying

SECURITY RECOMMENDATIONS:
    - Change default port (--port)
    - Disable root login (default)
    - Use key-based authentication only (default)
    - Limit user access (--allow-users)
    - Enable verbose logging (default)
    - Use strong ciphers and MACs

EOF
}

# Function to detect system information
detect_system() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Detecting system information..."
    fi
    
    # Detect OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    # Check if Ubuntu/Debian (SSH configuration is similar across these)
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_warning "This script is optimized for Ubuntu/Debian but may work on $OS"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Detected: $OS $VER"
    fi
}

# Function to install OpenSSH server
install_openssh_server() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install OpenSSH server with: sudo apt install -y openssh-server"
        echo "[DRY-RUN] Would enable and start SSH service"
        return 0
    fi

    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installing OpenSSH server..."
    fi

    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_info "This installation requires sudo privileges. Please enter your password when prompted."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges"
            exit 1
        fi
    fi

    # Update package lists
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Updating package lists..."
    fi

    if ! sudo apt update -qq; then
        print_error "Failed to update package lists"
        exit 1
    fi

    # Install OpenSSH server
    print_info "Installing openssh-server package..."

    if sudo apt install -y openssh-server; then
        print_success "OpenSSH server installed successfully"

        # Enable and start the service
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Enabling and starting SSH service..."
        fi

        sudo systemctl enable ssh >/dev/null 2>&1
        sudo systemctl start ssh >/dev/null 2>&1

        # Verify installation
        if command -v sshd >/dev/null 2>&1; then
            print_success "OpenSSH server is now ready for configuration"
        else
            print_error "OpenSSH server installation verification failed"
            exit 1
        fi
    else
        print_error "Failed to install OpenSSH server"
        print_info "Try installing manually with: sudo apt-get install openssh-server"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Checking prerequisites..."
    fi
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. Please enter your password when prompted."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges"
            exit 1
        fi
    fi
    
    # Check if OpenSSH server is installed
    if ! command -v sshd >/dev/null 2>&1; then
        print_warning "OpenSSH server is not installed"
        if [[ "$DRY_RUN" == true ]]; then
            print_info "[DRY-RUN] Would prompt to install OpenSSH server"
            print_info "[DRY-RUN] Install command: sudo apt-get install openssh-server"
        elif confirm_action "Install OpenSSH server now?" "Y"; then
            install_openssh_server
        else
            print_info "OpenSSH server installation cancelled"
            print_info "Install manually with: sudo apt-get install openssh-server"
            exit 1
        fi
    fi
    
    # Check if SSH service exists
    if ! systemctl list-unit-files | grep -q "^ssh.service\|^sshd.service"; then
        print_error "SSH service not found"
        exit 1
    fi
    
    # Validate port number
    if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -lt 1 ]] || [[ "$SSH_PORT" -gt 65535 ]]; then
        print_error "Invalid SSH port: $SSH_PORT"
        exit 1
    fi
    
    # Validate numeric settings
    for value in "$MAX_AUTH_TRIES" "$MAX_SESSIONS" "$CLIENT_ALIVE_INTERVAL" "$CLIENT_ALIVE_COUNT_MAX" "$LOGIN_GRACE_TIME"; do
        if [[ ! "$value" =~ ^[0-9]+$ ]]; then
            print_error "Invalid numeric value: $value"
            exit 1
        fi
    done
    
    # Validate log level
    case "$LOG_LEVEL" in
        QUIET|FATAL|ERROR|INFO|VERBOSE|DEBUG|DEBUG1|DEBUG2|DEBUG3) ;;
        *) 
            print_error "Invalid log level: $LOG_LEVEL"
            print_info "Valid levels: QUIET, FATAL, ERROR, INFO, VERBOSE, DEBUG"
            exit 1
            ;;
    esac
    
    # Validate root login setting
    case "$ALLOW_ROOT_LOGIN" in
        yes|no|prohibit-password|forced-commands-only) ;;
        *)
            print_error "Invalid root login setting: $ALLOW_ROOT_LOGIN"
            print_info "Valid options: yes, no, prohibit-password, forced-commands-only"
            exit 1
            ;;
    esac
}

# Function to backup existing configuration
backup_existing_config() {
    if [[ "$BACKUP_EXISTING" == false || "$DRY_RUN" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would backup existing SSH configuration"
        fi
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Backing up existing SSH configuration..."
    fi
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Backup main config
    if [[ -f "$SSHD_CONFIG" ]]; then
        sudo cp "$SSHD_CONFIG" "$SSHD_CONFIG.backup.$timestamp"
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Backed up: $SSHD_CONFIG.backup.$timestamp"
        fi
    fi
    
    # Backup banner if exists
    if [[ -f "$SSHD_BANNER" ]]; then
        sudo cp "$SSHD_BANNER" "$SSHD_BANNER.backup.$timestamp"
    fi
}

# Function to configure SSH daemon
configure_sshd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure SSH daemon with the specified settings"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring SSH daemon..."
    fi
    
    if [[ "$USE_BASHMIN_CONFIG" == true ]]; then
        configure_from_bashmin_template
    else
        configure_custom_settings
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "SSH daemon configuration completed"
    fi
}

# Function to use bashmin template configuration
configure_from_bashmin_template() {
    if [[ ! -f "$BASHMIN_CONFIG_SOURCE" ]]; then
        print_error "Bashmin SSH configuration template not found: $BASHMIN_CONFIG_SOURCE"
        exit 1
    fi
    
    # Copy bashmin template
    sudo cp "$BASHMIN_CONFIG_SOURCE" "$SSHD_CONFIG"
    
    # Apply port customization if different from default
    if [[ "$SSH_PORT" != "$DEFAULT_SSH_PORT" ]]; then
        sudo sed -i "s/^#Port 22/Port $SSH_PORT/" "$SSHD_CONFIG"
        sudo sed -i "s/^Port 22/Port $SSH_PORT/" "$SSHD_CONFIG"
    fi
    
    # Apply user restrictions if specified
    if [[ ${#ALLOWED_USERS[@]} -gt 0 ]]; then
        local users_list
        users_list=$(IFS=' '; echo "${ALLOWED_USERS[*]}")
        sudo sed -i "s/AllowUsers.*/AllowUsers $users_list/" "$SSHD_CONFIG"
    fi
    
    # Apply group restrictions if specified
    if [[ ${#ALLOWED_GROUPS[@]} -gt 0 ]]; then
        local groups_list
        groups_list=$(IFS=' '; echo "${ALLOWED_GROUPS[*]}")
        echo "AllowGroups $groups_list" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi
    
    if [[ ${#DENIED_USERS[@]} -gt 0 ]]; then
        local denied_users_list
        denied_users_list=$(IFS=' '; echo "${DENIED_USERS[*]}")
        echo "DenyUsers $denied_users_list" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi
    
    if [[ ${#DENIED_GROUPS[@]} -gt 0 ]]; then
        local denied_groups_list
        denied_groups_list=$(IFS=' '; echo "${DENIED_GROUPS[*]}")
        echo "DenyGroups $denied_groups_list" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi

    # Add Match blocks for password authentication even when using bashmin template
    apply_password_auth_match_blocks
}

# Function to configure custom settings
configure_custom_settings() {
    # Start with a secure base configuration
    create_secure_base_config
    
    # Apply all custom settings
    apply_connection_settings
    apply_authentication_settings
    apply_access_control_settings
    apply_forwarding_settings
    apply_security_settings
    apply_crypto_settings
}

# Function to create secure base configuration
create_secure_base_config() {
    cat << EOF | sudo tee "$SSHD_CONFIG" >/dev/null
# OpenSSH Server Configuration
# Generated by bashmin on $(date)
# For more information, see sshd_config(5)

# Connection Settings
Port $SSH_PORT
Protocol 2
AddressFamily any
ListenAddress 0.0.0.0

# Host Keys
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Logging
SyslogFacility AUTH
LogLevel $LOG_LEVEL

# Connection Management
LoginGraceTime ${LOGIN_GRACE_TIME}s
MaxAuthTries $MAX_AUTH_TRIES
MaxSessions $MAX_SESSIONS
ClientAliveInterval $CLIENT_ALIVE_INTERVAL
ClientAliveCountMax $CLIENT_ALIVE_COUNT_MAX

# Authentication
PermitRootLogin $ALLOW_ROOT_LOGIN
PubkeyAuthentication $(bool_to_yes_no $PUBKEY_AUTHENTICATION)
PasswordAuthentication $(bool_to_yes_no $ALLOW_PASSWORD_AUTH)
PermitEmptyPasswords $(bool_to_yes_no $ALLOW_EMPTY_PASSWORDS)
ChallengeResponseAuthentication no

# Forwarding and Tunneling
AllowAgentForwarding $(bool_to_yes_no $ENABLE_AGENT_FORWARDING)
AllowTcpForwarding $(bool_to_yes_no $ENABLE_TCP_FORWARDING)
X11Forwarding $(bool_to_yes_no $ENABLE_X11_FORWARDING)
PermitTunnel $(bool_to_yes_no $PERMIT_TUNNEL)

# Security Settings
StrictModes yes
IgnoreRhosts yes
HostbasedAuthentication no
PermitUserEnvironment no
Compression $(bool_to_yes_no $ENABLE_COMPRESSION)
UseDNS $(bool_to_yes_no $USE_DNS)
TCPKeepAlive no

# Subsystems
Subsystem sftp /usr/lib/openssh/sftp-server

# Misc
PrintMotd no
UsePAM yes
AcceptEnv LANG LC_*

EOF
}

# Function to apply connection settings
apply_connection_settings() {
    # Already handled in base config
    return 0
}

# Function to apply authentication settings
apply_authentication_settings() {
    # Already handled in base config
    return 0
}

# Function to apply access control settings
apply_access_control_settings() {
    # Add user and group restrictions
    if [[ ${#ALLOWED_USERS[@]} -gt 0 ]]; then
        local users_list
        users_list=$(IFS=' '; echo "${ALLOWED_USERS[*]}")
        echo "AllowUsers $users_list" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi

    if [[ ${#DENIED_USERS[@]} -gt 0 ]]; then
        local users_list
        users_list=$(IFS=' '; echo "${DENIED_USERS[*]}")
        echo "DenyUsers $users_list" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi

    if [[ ${#ALLOWED_GROUPS[@]} -gt 0 ]]; then
        local groups_list
        groups_list=$(IFS=' '; echo "${ALLOWED_GROUPS[*]}")
        echo "AllowGroups $groups_list" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi

    if [[ ${#DENIED_GROUPS[@]} -gt 0 ]]; then
        local groups_list
        groups_list=$(IFS=' '; echo "${DENIED_GROUPS[*]}")
        echo "DenyGroups $groups_list" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi

    # Add Match blocks for users/groups that need password authentication
    apply_password_auth_match_blocks
}

# Function to apply Match blocks for password authentication
apply_password_auth_match_blocks() {
    # Add Match blocks for users that need password authentication
    if [[ ${#PASSWORD_AUTH_USERS[@]} -gt 0 ]]; then
        echo "" | sudo tee -a "$SSHD_CONFIG" >/dev/null
        echo "# Match blocks for users requiring password authentication" | sudo tee -a "$SSHD_CONFIG" >/dev/null
        for user in "${PASSWORD_AUTH_USERS[@]}"; do
            cat << EOF | sudo tee -a "$SSHD_CONFIG" >/dev/null
Match User $user
    PasswordAuthentication yes
    PubkeyAuthentication yes
    AuthenticationMethods publickey,password

EOF
        done
    fi

    # Add Match blocks for groups that need password authentication
    if [[ ${#PASSWORD_AUTH_GROUPS[@]} -gt 0 ]]; then
        if [[ ${#PASSWORD_AUTH_USERS[@]} -eq 0 ]]; then
            echo "" | sudo tee -a "$SSHD_CONFIG" >/dev/null
            echo "# Match blocks for groups requiring password authentication" | sudo tee -a "$SSHD_CONFIG" >/dev/null
        fi
        for group in "${PASSWORD_AUTH_GROUPS[@]}"; do
            cat << EOF | sudo tee -a "$SSHD_CONFIG" >/dev/null
Match Group $group
    PasswordAuthentication yes
    PubkeyAuthentication yes
    AuthenticationMethods publickey,password

EOF
        done
    fi
}

# Function to apply forwarding settings
apply_forwarding_settings() {
    # Already handled in base config
    return 0
}

# Function to apply security settings
apply_security_settings() {
    # Add banner configuration
    if [[ "$ENABLE_BANNER" == true ]]; then
        echo "Banner $SSHD_BANNER" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi
}

# Function to apply cryptographic settings
apply_crypto_settings() {
    # Add custom ciphers if specified
    if [[ -n "$CUSTOM_CIPHERS" ]]; then
        echo "Ciphers $CUSTOM_CIPHERS" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi
    
    # Add custom MACs if specified
    if [[ -n "$CUSTOM_MACS" ]]; then
        echo "MACs $CUSTOM_MACS" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi
    
    # Add custom key exchange algorithms if specified
    if [[ -n "$CUSTOM_KEXALGORITHMS" ]]; then
        echo "KexAlgorithms $CUSTOM_KEXALGORITHMS" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi
}

# Function to configure banner
configure_banner() {
    if [[ "$ENABLE_BANNER" == false || "$DRY_RUN" == true ]]; then
        if [[ "$DRY_RUN" == true && "$ENABLE_BANNER" == true ]]; then
            echo "[DRY-RUN] Would configure SSH banner"
        fi
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring SSH banner..."
    fi
    
    # Use bashmin banner if available, otherwise create a simple one
    if [[ -f "$BASHMIN_BANNER_SOURCE" ]]; then
        sudo cp "$BASHMIN_BANNER_SOURCE" "$SSHD_BANNER"
    else
        create_simple_banner
    fi
    
    # Set proper permissions
    sudo chmod 644 "$SSHD_BANNER"
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "SSH banner configured"
    fi
}

# Function to create a simple banner if bashmin banner doesn't exist
create_simple_banner() {
    cat << 'EOF' | sudo tee "$SSHD_BANNER" >/dev/null
============================================================================

                    AUTHORIZED ACCESS ONLY

    This system is for authorized users only. All activities on this
    system are monitored and recorded. By accessing this system, you
    acknowledge that you have no expectation of privacy and consent
    to monitoring.

    Unauthorized access is prohibited and may be subject to criminal
    and civil penalties.

============================================================================
EOF
}

# Function to test SSH configuration
test_sshd_config() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test SSH configuration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Testing SSH configuration..."
    fi
    
    # Test the configuration
    if sudo sshd -t -f "$SSHD_CONFIG" 2>/dev/null; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "SSH configuration test passed"
        fi
        return 0
    else
        print_error "SSH configuration test failed"
        sudo sshd -t -f "$SSHD_CONFIG" 2>&1 | head -5
        return 1
    fi
}

# Function to restart SSH service
restart_ssh_service() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would restart SSH service"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Restarting SSH service..."
    fi
    
    # Determine correct service name
    local service_name="ssh"
    if systemctl list-unit-files | grep -q "^sshd.service"; then
        service_name="sshd"
    fi
    
    # Restart the service
    if sudo systemctl restart "$service_name"; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "SSH service restarted successfully"
        fi
    else
        print_error "Failed to restart SSH service"
        print_info "Check status: sudo systemctl status $service_name"
        return 1
    fi
    
    # Verify service is running
    if ! systemctl is-active --quiet "$service_name"; then
        print_error "SSH service is not running after restart"
        return 1
    fi
}

# Helper function to convert boolean to yes/no
bool_to_yes_no() {
    if [[ "$1" == true ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# Function to show configuration summary
show_completion_summary() {
    if [[ "$QUIET" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo
    print_success "SSH daemon configuration completed successfully! 🔒"
    echo
    print_info "=== SSH Configuration Summary ==="
    cat << EOF
SSH Port:            $SSH_PORT
Root Login:          $ALLOW_ROOT_LOGIN
Password Auth:       $(bool_to_yes_no $ALLOW_PASSWORD_AUTH)
Public Key Auth:     $(bool_to_yes_no $PUBKEY_AUTHENTICATION)
Max Auth Tries:      $MAX_AUTH_TRIES
Max Sessions:        $MAX_SESSIONS
X11 Forwarding:      $(bool_to_yes_no $ENABLE_X11_FORWARDING)
Agent Forwarding:    $(bool_to_yes_no $ENABLE_AGENT_FORWARDING)
TCP Forwarding:      $(bool_to_yes_no $ENABLE_TCP_FORWARDING)
Banner:              $(bool_to_yes_no $ENABLE_BANNER)
Log Level:           $LOG_LEVEL
Client Alive:        ${CLIENT_ALIVE_INTERVAL}s (max $CLIENT_ALIVE_COUNT_MAX)

EOF

    if [[ ${#ALLOWED_USERS[@]} -gt 0 ]] || [[ ${#PASSWORD_AUTH_USERS[@]} -gt 0 ]] || [[ ${#PASSWORD_AUTH_GROUPS[@]} -gt 0 ]]; then
        print_info "=== Access Control ==="
        if [[ ${#ALLOWED_USERS[@]} -gt 0 ]]; then
            echo "Allowed Users:       ${ALLOWED_USERS[*]}"
        fi
        if [[ ${#DENIED_USERS[@]} -gt 0 ]]; then
            echo "Denied Users:        ${DENIED_USERS[*]}"
        fi
        if [[ ${#ALLOWED_GROUPS[@]} -gt 0 ]]; then
            echo "Allowed Groups:      ${ALLOWED_GROUPS[*]}"
        fi
        if [[ ${#DENIED_GROUPS[@]} -gt 0 ]]; then
            echo "Denied Groups:       ${DENIED_GROUPS[*]}"
        fi
        if [[ ${#PASSWORD_AUTH_USERS[@]} -gt 0 ]]; then
            echo "Password Auth Users: ${PASSWORD_AUTH_USERS[*]}"
        fi
        if [[ ${#PASSWORD_AUTH_GROUPS[@]} -gt 0 ]]; then
            echo "Password Auth Groups: ${PASSWORD_AUTH_GROUPS[*]}"
        fi
        echo
    fi

    print_info "=== Service Information ==="
    local service_name="ssh"
    if systemctl list-unit-files | grep -q "^sshd.service"; then
        service_name="sshd"
    fi
    cat << EOF
Service Status:      $(systemctl is-active $service_name)
Service Enabled:     $(systemctl is-enabled $service_name)
Config File:         $SSHD_CONFIG
Banner File:         $(if [[ "$ENABLE_BANNER" == true ]]; then echo "$SSHD_BANNER"; else echo "Disabled"; fi)

EOF

    print_info "=== Connection Information ==="
    cat << EOF
Connect Command:     ssh -p $SSH_PORT user@hostname
Local Test:          ssh -p $SSH_PORT localhost
Config Test:         sudo sshd -t

EOF

    print_info "=== Management Commands ==="
    cat << EOF
View status:         sudo systemctl status $service_name
View logs:           sudo journalctl -u $service_name -f
Reload config:       sudo systemctl reload $service_name
Test config:         sudo sshd -t
Edit config:         sudo nano $SSHD_CONFIG

EOF

    print_info "=== Security Notes ==="
    cat << EOF
• SSH is configured with security hardening
• Consider using fail2ban for additional protection
• Monitor SSH logs regularly for suspicious activity
• Keep SSH keys secure and rotate them periodically
• Use strong passwords if password authentication is enabled

EOF

    if [[ "$SSH_PORT" != "$DEFAULT_SSH_PORT" ]]; then
        print_warning "SSH port changed to $SSH_PORT"
        print_info "Update firewall rules: sudo ufw allow $SSH_PORT/tcp"
        print_info "Remove old rule: sudo ufw delete allow $DEFAULT_SSH_PORT/tcp"
    fi
    
    print_info "🛡️ Your SSH daemon is now securely configured!"
}

# Main function
main() {
    # Detect system
    detect_system
    
    if [[ "$QUIET" == false ]]; then
        show_script_header "SSH Daemon Configuration"
        print_info "Configuring OpenSSH daemon with security hardening"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show configuration plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuration plan:"
        print_info "  SSH Port: $SSH_PORT"
        print_info "  Root Login: $ALLOW_ROOT_LOGIN"
        print_info "  Password Auth: $(bool_to_yes_no $ALLOW_PASSWORD_AUTH)"
        print_info "  Public Key Auth: $(bool_to_yes_no $PUBKEY_AUTHENTICATION)"
        print_info "  Max Auth Tries: $MAX_AUTH_TRIES"
        print_info "  Use Bashmin Config: $(bool_to_yes_no $USE_BASHMIN_CONFIG)"
        [[ ${#ALLOWED_USERS[@]} -gt 0 ]] && print_info "  Allowed Users: ${ALLOWED_USERS[*]}"
        [[ ${#PASSWORD_AUTH_USERS[@]} -gt 0 ]] && print_info "  Password Auth Users: ${PASSWORD_AUTH_USERS[*]}"
        [[ ${#PASSWORD_AUTH_GROUPS[@]} -gt 0 ]] && print_info "  Password Auth Groups: ${PASSWORD_AUTH_GROUPS[*]}"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with SSH configuration?" "Y"; then
            print_info "SSH configuration cancelled"
            exit 0
        fi
    fi
    
    # Execute configuration steps
    backup_existing_config
    configure_sshd
    configure_banner
    
    # Test and apply configuration
    if test_sshd_config; then
        restart_ssh_service
        show_completion_summary
    else
        print_error "SSH configuration failed validation"
        print_info "Configuration has been created but not applied due to errors"
        exit 1
    fi
}

# Run main function
main "$@"
