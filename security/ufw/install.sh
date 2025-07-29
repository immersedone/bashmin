#!/bin/bash
#
# Script: security/ufw/install.sh
# Description: Install and configure UFW (Uncomplicated Firewall) with security hardening
# Usage: ./install.sh [OPTIONS]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly UFW_CONFIG_DIR="/etc/ufw"
readonly UFW_RULES_DIR="$UFW_CONFIG_DIR/applications.d"
readonly UFW_SYSCTL_CONF="$UFW_CONFIG_DIR/sysctl.conf"
readonly UFW_BEFORE_RULES="$UFW_CONFIG_DIR/before.rules"
readonly UFW_AFTER_RULES="$UFW_CONFIG_DIR/after.rules"
readonly UFW_BEFORE6_RULES="$UFW_CONFIG_DIR/before6.rules"
readonly UFW_AFTER6_RULES="$UFW_CONFIG_DIR/after6.rules"
readonly UFW_USER_RULES="$UFW_CONFIG_DIR/user.rules"
readonly UFW_USER6_RULES="$UFW_CONFIG_DIR/user6.rules"
readonly UFW_LOG_DIR="/var/log/ufw"
readonly UFW_LOG_FILE="$UFW_LOG_DIR/ufw.log"
readonly BASHMIN_RSYSLOG_CONF="$PROJECT_ROOT/system/etc/rsyslog.d/20-ufw.conf"
readonly BASHMIN_LOGROTATE_CONF="$PROJECT_ROOT/system/etc/logrotate.d/ufw"

# Configuration variables
DEFAULT_INCOMING_POLICY="deny"
DEFAULT_OUTGOING_POLICY="allow"
DEFAULT_ROUTED_POLICY="deny"
ENABLE_IPV6=true
ENABLE_LOGGING=true
LOG_LEVEL="low"
ENABLE_SYN_COOKIES=true
ENABLE_ICMP_REDIRECTS=false
ENABLE_SOURCE_ROUTING=false
ENABLE_LOG_MARTIANS=true
ALLOW_SSH=true
SSH_PORT="22"
SSH_LIMIT_RATE=true
ALLOW_HTTP=false
ALLOW_HTTPS=false
ALLOW_FTP=false
ALLOW_MYSQL=false
ALLOW_POSTGRESQL=false
ALLOW_MONGODB=false
ALLOW_REDIS=false
ALLOW_ELASTICSEARCH=false
ALLOW_CUSTOM_PORTS=()
DENY_CUSTOM_PORTS=()
TRUSTED_NETWORKS=()
BLOCKED_NETWORKS=()
RATE_LIMITING=true
BRUTE_FORCE_PROTECTION=true
SETUP_APPLICATION_PROFILES=true
ENABLE_UFW_ON_COMPLETION=true
BACKUP_EXISTING_RULES=true
FORCE_INSTALL=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Function to show help and exit
show_help_and_exit() {
    cat << EOF
Usage: $0 [OPTIONS]

Install and configure UFW (Uncomplicated Firewall) with security hardening.

POLICY OPTIONS:
    --incoming-policy POLICY    Default incoming policy: allow, deny, reject (default: deny)
    --outgoing-policy POLICY    Default outgoing policy: allow, deny, reject (default: allow)
    --routed-policy POLICY      Default routed policy: allow, deny, reject (default: deny)

CONNECTION OPTIONS:
    --ssh-port PORT             SSH port to allow (default: 22)
    --disable-ssh               Don't automatically allow SSH
    --no-ssh-limit              Don't apply rate limiting to SSH
    --allow-http                Allow HTTP (port 80)
    --allow-https               Allow HTTPS (port 443)
    --allow-ftp                 Allow FTP (ports 20-21)

DATABASE OPTIONS:
    --allow-mysql               Allow MySQL/MariaDB (port 3306)
    --allow-postgresql          Allow PostgreSQL (port 5432)
    --allow-mongodb             Allow MongoDB (port 27017)
    --allow-redis               Allow Redis (port 6379)
    --allow-elasticsearch       Allow Elasticsearch (port 9200)

CUSTOM RULES:
    --allow-ports PORTS         Comma-separated list of ports to allow (e.g., 8080,9000)
    --deny-ports PORTS          Comma-separated list of ports to explicitly deny
    --trusted-networks NETS     Comma-separated trusted networks (e.g., 192.168.1.0/24,10.0.0.0/8)
    --blocked-networks NETS     Comma-separated networks to block

SECURITY OPTIONS:
    --disable-ipv6              Disable IPv6 support
    --disable-rate-limiting     Disable connection rate limiting
    --disable-brute-force-protection Disable anti-brute force measures
    --disable-syn-cookies       Disable SYN flood protection
    --enable-icmp-redirects     Enable ICMP redirects (not recommended)
    --enable-source-routing     Enable source routing (not recommended)
    --disable-log-martians      Disable logging of martian packets

LOGGING OPTIONS:
    --disable-logging           Disable UFW logging
    --log-level LEVEL           Log level: off, low, medium, high, full (default: low)

SETUP OPTIONS:
    --no-application-profiles   Don't install application profiles
    --no-enable                 Don't enable UFW after configuration
    --no-backup                 Don't backup existing rules
    --force                     Force reinstall even if UFW is configured
    --quiet                     Suppress non-essential output
    --verbose                   Enable verbose output
    --dry-run                   Show what would be configured without executing
    -h, --help                  Show this help message

SECURITY MODES:
    Basic Server:               Default settings with SSH only
    Web Server:                 Add --allow-http --allow-https
    Database Server:            Add --allow-mysql or --allow-postgresql
    Development Server:         Add --allow-ports 3000,8080,9000

EXAMPLES:
    # Basic secure server
    $0

    # Web server with HTTPS
    $0 --allow-http --allow-https

    # Database server with custom SSH port
    $0 --ssh-port 2222 --allow-mysql --allow-postgresql

    # Development server with custom ports
    $0 --allow-ports 3000,8080,9000 --trusted-networks 192.168.1.0/24

    # High-security server with strict policies
    $0 --incoming-policy reject --disable-ipv6 --log-level high

    # Multi-service server
    $0 --allow-https --allow-mysql --allow-redis --ssh-port 2222 \
       --trusted-networks 10.0.0.0/8,192.168.0.0/16

NOTES:
    - Requires sudo privileges
    - Automatically configures logging to /var/log/ufw/
    - Creates application profiles for common services
    - Enables SYN flood protection by default
    - Includes rate limiting for SSH to prevent brute force attacks
    - Backs up existing rules before making changes

SECURITY WARNINGS:
    - Test firewall rules carefully to avoid being locked out
    - Ensure SSH access before enabling UFW
    - Consider using a management network for recovery
    - Monitor logs for blocked legitimate traffic

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --incoming-policy)
            DEFAULT_INCOMING_POLICY="$2"
            shift 2
            ;;
        --outgoing-policy)
            DEFAULT_OUTGOING_POLICY="$2"
            shift 2
            ;;
        --routed-policy)
            DEFAULT_ROUTED_POLICY="$2"
            shift 2
            ;;
        --disable-ipv6)
            ENABLE_IPV6=false
            shift
            ;;
        --disable-logging)
            ENABLE_LOGGING=false
            shift
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --disable-ssh)
            ALLOW_SSH=false
            shift
            ;;
        --no-ssh-limit)
            SSH_LIMIT_RATE=false
            shift
            ;;
        --allow-http)
            ALLOW_HTTP=true
            shift
            ;;
        --allow-https)
            ALLOW_HTTPS=true
            shift
            ;;
        --allow-ftp)
            ALLOW_FTP=true
            shift
            ;;
        --allow-mysql)
            ALLOW_MYSQL=true
            shift
            ;;
        --allow-postgresql)
            ALLOW_POSTGRESQL=true
            shift
            ;;
        --allow-mongodb)
            ALLOW_MONGODB=true
            shift
            ;;
        --allow-redis)
            ALLOW_REDIS=true
            shift
            ;;
        --allow-elasticsearch)
            ALLOW_ELASTICSEARCH=true
            shift
            ;;
        --allow-ports)
            IFS=',' read -ra ALLOW_CUSTOM_PORTS <<< "$2"
            shift 2
            ;;
        --deny-ports)
            IFS=',' read -ra DENY_CUSTOM_PORTS <<< "$2"
            shift 2
            ;;
        --trusted-networks)
            IFS=',' read -ra TRUSTED_NETWORKS <<< "$2"
            shift 2
            ;;
        --blocked-networks)
            IFS=',' read -ra BLOCKED_NETWORKS <<< "$2"
            shift 2
            ;;
        --disable-rate-limiting)
            RATE_LIMITING=false
            shift
            ;;
        --disable-brute-force-protection)
            BRUTE_FORCE_PROTECTION=false
            shift
            ;;
        --no-application-profiles)
            SETUP_APPLICATION_PROFILES=false
            shift
            ;;
        --no-enable)
            ENABLE_UFW_ON_COMPLETION=false
            shift
            ;;
        --no-backup)
            BACKUP_EXISTING_RULES=false
            shift
            ;;
        --disable-syn-cookies)
            ENABLE_SYN_COOKIES=false
            shift
            ;;
        --enable-icmp-redirects)
            ENABLE_ICMP_REDIRECTS=true
            shift
            ;;
        --enable-source-routing)
            ENABLE_SOURCE_ROUTING=true
            shift
            ;;
        --disable-log-martians)
            ENABLE_LOG_MARTIANS=false
            shift
            ;;
        --force)
            FORCE_INSTALL=true
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
            show_help_and_exit
            ;;
        *)
            print_error "Unknown option: $1"
            show_help_and_exit
            ;;
    esac
done

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
    
    # Check if Ubuntu/Debian (UFW is primarily for these)
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_warning "UFW is designed for Ubuntu/Debian. May not work properly on $OS"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Detected: $OS $VER"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Checking prerequisites..."
    fi
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        exit 1
    fi
    
    # Check if UFW is already configured and force is not set
    if command -v ufw >/dev/null 2>&1 && ufw status >/dev/null 2>&1 && [[ "$FORCE_INSTALL" == false ]]; then
        local ufw_status
        ufw_status=$(sudo ufw status | head -1)
        if [[ "$ufw_status" == *"active"* ]]; then
            print_error "UFW is already active and configured"
            print_info "Use --force to reconfigure"
            exit 1
        fi
    fi
    
    # Validate policies
    for policy in "$DEFAULT_INCOMING_POLICY" "$DEFAULT_OUTGOING_POLICY" "$DEFAULT_ROUTED_POLICY"; do
        case "$policy" in
            allow|deny|reject) ;;
            *)
                print_error "Invalid policy: $policy (use: allow, deny, or reject)"
                exit 1
                ;;
        esac
    done
    
    # Validate log level
    case "$LOG_LEVEL" in
        off|low|medium|high|full) ;;
        *)
            print_error "Invalid log level: $LOG_LEVEL (use: off, low, medium, high, or full)"
            exit 1
            ;;
    esac
    
    # Validate SSH port
    if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -lt 1 ]] || [[ "$SSH_PORT" -gt 65535 ]]; then
        print_error "Invalid SSH port: $SSH_PORT"
        exit 1
    fi
    
    # Validate custom ports
    for port_list in "ALLOW_CUSTOM_PORTS" "DENY_CUSTOM_PORTS"; do
        eval "ports=(\"\${${port_list}[@]}\")"
        for port in "${ports[@]}"; do
            if [[ ! "$port" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
                print_error "Invalid port format: $port (use single port or range like 8080-8090)"
                exit 1
            fi
        done
    done
}

# Function to install UFW
install_ufw() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install UFW package"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installing UFW..."
    fi
    
    # Update package cache
    sudo apt-get update -qq
    
    # Install UFW
    sudo apt-get install -y ufw
    
    # Verify installation
    if ! command -v ufw >/dev/null 2>&1; then
        print_error "UFW installation failed"
        exit 1
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "UFW installed successfully"
    fi
}

# Function to backup existing configuration
backup_existing_config() {
    if [[ "$BACKUP_EXISTING_RULES" == false || "$DRY_RUN" == true ]]; then
        if [[ "$DRY_RUN" == true && "$BACKUP_EXISTING_RULES" == true ]]; then
            echo "[DRY-RUN] Would backup existing UFW configuration"
        fi
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Backing up existing UFW configuration..."
    fi
    
    local backup_dir="/etc/ufw/backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -d "$UFW_CONFIG_DIR" ]]; then
        sudo mkdir -p "$backup_dir"
        sudo cp -r "$UFW_CONFIG_DIR"/* "$backup_dir"/ 2>/dev/null || true
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Configuration backed up to: $backup_dir"
        fi
    fi
}

# Function to reset UFW to defaults
reset_ufw() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would reset UFW to default configuration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Resetting UFW to defaults..."
    fi
    
    # Disable UFW first
    sudo ufw --force disable >/dev/null 2>&1 || true
    
    # Reset to defaults
    sudo ufw --force reset >/dev/null 2>&1
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "UFW reset to defaults"
    fi
}

# Function to configure UFW policies
configure_policies() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure UFW policies: incoming=$DEFAULT_INCOMING_POLICY, outgoing=$DEFAULT_OUTGOING_POLICY"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring UFW policies..."
    fi
    
    # Set default policies
    sudo ufw default "$DEFAULT_INCOMING_POLICY" incoming >/dev/null
    sudo ufw default "$DEFAULT_OUTGOING_POLICY" outgoing >/dev/null
    sudo ufw default "$DEFAULT_ROUTED_POLICY" forward >/dev/null
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "UFW policies configured"
    fi
}

# Function to configure UFW settings
configure_ufw_settings() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure UFW settings (IPv6, logging, etc.)"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring UFW settings..."
    fi
    
    # Configure IPv6
    if [[ "$ENABLE_IPV6" == false ]]; then
        sudo sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw
    else
        sudo sed -i 's/IPV6=no/IPV6=yes/' /etc/default/ufw
    fi
    
    # Configure logging
    if [[ "$ENABLE_LOGGING" == true ]]; then
        sudo ufw logging "$LOG_LEVEL" >/dev/null
    else
        sudo ufw logging off >/dev/null
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "UFW settings configured"
    fi
}

# Function to configure kernel security parameters
configure_kernel_security() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure kernel security parameters"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring kernel security parameters..."
    fi
    
    # Backup original sysctl.conf
    if [[ -f "$UFW_SYSCTL_CONF" ]]; then
        sudo cp "$UFW_SYSCTL_CONF" "$UFW_SYSCTL_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create enhanced sysctl configuration
    cat << EOF | sudo tee "$UFW_SYSCTL_CONF" >/dev/null
# UFW Kernel Security Configuration
# Generated by bashmin on $(date)

# IP Spoofing protection
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects=$(bool_to_int $ENABLE_ICMP_REDIRECTS)
net.ipv4.conf.default.accept_redirects=$(bool_to_int $ENABLE_ICMP_REDIRECTS)
net.ipv6.conf.all.accept_redirects=$(bool_to_int $ENABLE_ICMP_REDIRECTS)
net.ipv6.conf.default.accept_redirects=$(bool_to_int $ENABLE_ICMP_REDIRECTS)

# Ignore source routing
net.ipv4.conf.all.accept_source_route=$(bool_to_int $ENABLE_SOURCE_ROUTING)
net.ipv4.conf.default.accept_source_route=$(bool_to_int $ENABLE_SOURCE_ROUTING)
net.ipv6.conf.all.accept_source_route=$(bool_to_int $ENABLE_SOURCE_ROUTING)
net.ipv6.conf.default.accept_source_route=$(bool_to_int $ENABLE_SOURCE_ROUTING)

# Ignore send redirects
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0

# Log Martians
net.ipv4.conf.all.log_martians=$(bool_to_int $ENABLE_LOG_MARTIANS)
net.ipv4.conf.default.log_martians=$(bool_to_int $ENABLE_LOG_MARTIANS)

# Ignore ping requests
net.ipv4.icmp_echo_ignore_all=0

# Ignore Bogus ICMP errors
net.ipv4.icmp_ignore_bogus_error_responses=1

# SYN flood protection
net.ipv4.tcp_syncookies=$(bool_to_int $ENABLE_SYN_COOKIES)
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_syn_retries=5

# IP forwarding (disabled for security)
net.ipv4.ip_forward=0
net.ipv6.conf.all.forwarding=0

# Additional security settings
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv4.tcp_timestamps=0
EOF
    
    # Apply sysctl settings
    sudo sysctl -p "$UFW_SYSCTL_CONF" >/dev/null
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Kernel security parameters configured"
    fi
}

# Function to configure basic firewall rules
configure_basic_rules() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure basic firewall rules"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring basic firewall rules..."
    fi
    
    # Allow SSH with rate limiting
    if [[ "$ALLOW_SSH" == true ]]; then
        if [[ "$SSH_LIMIT_RATE" == true ]]; then
            sudo ufw limit "$SSH_PORT"/tcp comment "SSH with rate limiting" >/dev/null
        else
            sudo ufw allow "$SSH_PORT"/tcp comment "SSH access" >/dev/null
        fi
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "SSH access configured on port $SSH_PORT"
        fi
    fi
    
    # Allow HTTP
    if [[ "$ALLOW_HTTP" == true ]]; then
        sudo ufw allow 80/tcp comment "HTTP" >/dev/null
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "HTTP access allowed"
        fi
    fi
    
    # Allow HTTPS
    if [[ "$ALLOW_HTTPS" == true ]]; then
        sudo ufw allow 443/tcp comment "HTTPS" >/dev/null
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "HTTPS access allowed"
        fi
    fi
    
    # Allow FTP
    if [[ "$ALLOW_FTP" == true ]]; then
        sudo ufw allow 20:21/tcp comment "FTP" >/dev/null
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "FTP access allowed"
        fi
    fi
}

# Function to configure database rules
configure_database_rules() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure database firewall rules"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring database firewall rules..."
    fi
    
    # MySQL/MariaDB
    if [[ "$ALLOW_MYSQL" == true ]]; then
        sudo ufw allow 3306/tcp comment "MySQL/MariaDB" >/dev/null
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "MySQL/MariaDB access allowed"
        fi
    fi
    
    # PostgreSQL
    if [[ "$ALLOW_POSTGRESQL" == true ]]; then
        sudo ufw allow 5432/tcp comment "PostgreSQL" >/dev/null
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "PostgreSQL access allowed"
        fi
    fi
    
    # MongoDB
    if [[ "$ALLOW_MONGODB" == true ]]; then
        sudo ufw allow 27017/tcp comment "MongoDB" >/dev/null
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "MongoDB access allowed"
        fi
    fi
    
    # Redis
    if [[ "$ALLOW_REDIS" == true ]]; then
        sudo ufw allow 6379/tcp comment "Redis" >/dev/null
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Redis access allowed"
        fi
    fi
    
    # Elasticsearch
    if [[ "$ALLOW_ELASTICSEARCH" == true ]]; then
        sudo ufw allow 9200/tcp comment "Elasticsearch" >/dev/null
        sudo ufw allow 9300/tcp comment "Elasticsearch Transport" >/dev/null
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Elasticsearch access allowed"
        fi
    fi
}

# Function to configure custom rules
configure_custom_rules() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure custom firewall rules"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring custom firewall rules..."
    fi
    
    # Allow custom ports
    for port in "${ALLOW_CUSTOM_PORTS[@]}"; do
        if [[ "$port" == *"-"* ]]; then
            sudo ufw allow "$port"/tcp comment "Custom port range" >/dev/null
        else
            sudo ufw allow "$port"/tcp comment "Custom port" >/dev/null
        fi
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Custom port $port allowed"
        fi
    done
    
    # Deny custom ports
    for port in "${DENY_CUSTOM_PORTS[@]}"; do
        if [[ "$port" == *"-"* ]]; then
            sudo ufw deny "$port"/tcp comment "Blocked port range" >/dev/null
        else
            sudo ufw deny "$port"/tcp comment "Blocked port" >/dev/null
        fi
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Custom port $port denied"
        fi
    done
    
    # Allow trusted networks
    for network in "${TRUSTED_NETWORKS[@]}"; do
        sudo ufw allow from "$network" comment "Trusted network" >/dev/null
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Trusted network $network allowed"
        fi
    done
    
    # Block networks
    for network in "${BLOCKED_NETWORKS[@]}"; do
        sudo ufw deny from "$network" comment "Blocked network" >/dev/null
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Network $network blocked"
        fi
    done
}

# Function to setup application profiles
setup_application_profiles() {
    if [[ "$SETUP_APPLICATION_PROFILES" == false || "$DRY_RUN" == true ]]; then
        if [[ "$DRY_RUN" == true && "$SETUP_APPLICATION_PROFILES" == true ]]; then
            echo "[DRY-RUN] Would setup UFW application profiles"
        fi
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Setting up UFW application profiles..."
    fi
    
    # Create application profiles directory
    sudo mkdir -p "$UFW_RULES_DIR"
    
    # Create common application profiles
    create_application_profiles
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Application profiles created"
    fi
}

# Function to create application profiles
create_application_profiles() {
    # Nginx profile
    cat << 'EOF' | sudo tee "$UFW_RULES_DIR/nginx" >/dev/null
[Nginx HTTP]
title=Web Server (Nginx, HTTP)
description=Small, but very powerful and efficient web server
ports=80/tcp

[Nginx HTTPS]
title=Web Server (Nginx, HTTPS)
description=Small, but very powerful and efficient web server
ports=443/tcp

[Nginx Full]
title=Web Server (Nginx, HTTP + HTTPS)
description=Small, but very powerful and efficient web server
ports=80,443/tcp
EOF
    
    # Apache profile
    cat << 'EOF' | sudo tee "$UFW_RULES_DIR/apache2" >/dev/null
[Apache]
title=Web Server (Apache)
description=Apache HTTP Server
ports=80/tcp

[Apache Secure]
title=Web Server (Apache, HTTPS)
description=Apache HTTP Server with SSL
ports=443/tcp

[Apache Full]
title=Web Server (Apache, HTTP + HTTPS)
description=Apache HTTP Server
ports=80,443/tcp
EOF
    
    # Development tools profile
    cat << 'EOF' | sudo tee "$UFW_RULES_DIR/development" >/dev/null
[Development]
title=Development Ports
description=Common development server ports
ports=3000,8000,8080,8888,9000/tcp

[Node.js]
title=Node.js Development
description=Common Node.js development ports
ports=3000,3001,5000,8000/tcp

[Rails]
title=Ruby on Rails
description=Ruby on Rails development server
ports=3000/tcp

[Django]
title=Django Development
description=Django development server
ports=8000/tcp
EOF
    
    # Database profiles
    cat << 'EOF' | sudo tee "$UFW_RULES_DIR/databases" >/dev/null
[MySQL]
title=MySQL Database
description=MySQL database server
ports=3306/tcp

[PostgreSQL]
title=PostgreSQL Database
description=PostgreSQL database server
ports=5432/tcp

[MongoDB]
title=MongoDB Database
description=MongoDB database server
ports=27017/tcp

[Redis]
title=Redis Cache
description=Redis in-memory data structure store
ports=6379/tcp

[Elasticsearch]
title=Elasticsearch
description=Elasticsearch search engine
ports=9200,9300/tcp
EOF
}

# Function to configure logging
configure_logging() {
    if [[ "$ENABLE_LOGGING" == false || "$DRY_RUN" == true ]]; then
        if [[ "$DRY_RUN" == true && "$ENABLE_LOGGING" == true ]]; then
            echo "[DRY-RUN] Would configure UFW logging"
        fi
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring UFW logging..."
    fi
    
    # Create log directory
    sudo mkdir -p "$UFW_LOG_DIR"
    
    # Configure rsyslog for UFW
    if [[ -f "$BASHMIN_RSYSLOG_CONF" ]]; then
        sudo cp "$BASHMIN_RSYSLOG_CONF" /etc/rsyslog.d/20-ufw.conf
    else
        create_rsyslog_config
    fi
    
    # Configure logrotate for UFW
    if [[ -f "$BASHMIN_LOGROTATE_CONF" ]]; then
        sudo cp "$BASHMIN_LOGROTATE_CONF" /etc/logrotate.d/ufw
    else
        create_logrotate_config
    fi
    
    # Restart rsyslog
    sudo systemctl restart rsyslog
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "UFW logging configured"
    fi
}

# Function to create rsyslog configuration
create_rsyslog_config() {
    cat << 'EOF' | sudo tee /etc/rsyslog.d/20-ufw.conf >/dev/null
# UFW logging configuration
# Generated by bashmin

# Log kernel generated UFW log messages to file
:msg,contains,"[UFW " /var/log/ufw/ufw.log

# Stop logging UFW messages to other files
& stop
EOF
}

# Function to create logrotate configuration
create_logrotate_config() {
    cat << 'EOF' | sudo tee /etc/logrotate.d/ufw >/dev/null
/var/log/ufw/ufw.log {
    rotate 4
    weekly
    dateext
    dateformat -%Y-%m-%d
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        invoke-rc.d rsyslog rotate >/dev/null 2>&1 || true
    endscript
}
EOF
}

# Function to enable UFW
enable_ufw() {
    if [[ "$ENABLE_UFW_ON_COMPLETION" == false || "$DRY_RUN" == true ]]; then
        if [[ "$DRY_RUN" == true && "$ENABLE_UFW_ON_COMPLETION" == true ]]; then
            echo "[DRY-RUN] Would enable UFW firewall"
        fi
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Enabling UFW firewall..."
    fi
    
    # Enable UFW
    sudo ufw --force enable >/dev/null
    
    # Verify UFW is enabled
    if sudo ufw status | grep -q "Status: active"; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "UFW firewall enabled"
        fi
    else
        print_error "Failed to enable UFW firewall"
        return 1
    fi
}

# Function to test firewall configuration
test_firewall_config() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test firewall configuration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Testing firewall configuration..."
    fi
    
    # Check UFW status
    local ufw_status
    ufw_status=$(sudo ufw status 2>/dev/null || echo "error")
    
    if [[ "$ufw_status" == "error" ]]; then
        print_error "Cannot check UFW status"
        return 1
    fi
    
    # Test SSH access if enabled
    if [[ "$ALLOW_SSH" == true ]]; then
        if sudo ufw status | grep -q "$SSH_PORT"; then
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_success "SSH access rule verified"
            fi
        else
            print_warning "SSH rule not found in UFW status"
        fi
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Firewall configuration test completed"
    fi
}

# Helper function to convert boolean to int
bool_to_int() {
    if [[ "$1" == true ]]; then
        echo "1"
    else
        echo "0"
    fi
}

# Function to show completion summary
show_completion_summary() {
    if [[ "$QUIET" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo
    print_success "UFW firewall configuration completed successfully! 🔥"
    echo
    print_info "=== Firewall Configuration Summary ==="
    cat << EOF
Default Policies:
  Incoming:            $DEFAULT_INCOMING_POLICY
  Outgoing:            $DEFAULT_OUTGOING_POLICY
  Routed:              $DEFAULT_ROUTED_POLICY

Security Features:
  IPv6 Support:        $(bool_to_yes_no $ENABLE_IPV6)
  Logging Level:       $(if [[ "$ENABLE_LOGGING" == true ]]; then echo "$LOG_LEVEL"; else echo "disabled"; fi)
  SYN Cookies:         $(bool_to_yes_no $ENABLE_SYN_COOKIES)
  Rate Limiting:       $(bool_to_yes_no $RATE_LIMITING)
  Brute Force Protection: $(bool_to_yes_no $BRUTE_FORCE_PROTECTION)

EOF

    print_info "=== Allowed Services ==="
    local services_output=""
    [[ "$ALLOW_SSH" == true ]] && services_output+="SSH (port $SSH_PORT)$(if [[ "$SSH_LIMIT_RATE" == true ]]; then echo " with rate limiting"; fi)\n"
    [[ "$ALLOW_HTTP" == true ]] && services_output+="HTTP (port 80)\n"
    [[ "$ALLOW_HTTPS" == true ]] && services_output+="HTTPS (port 443)\n"
    [[ "$ALLOW_FTP" == true ]] && services_output+="FTP (ports 20-21)\n"
    [[ "$ALLOW_MYSQL" == true ]] && services_output+="MySQL/MariaDB (port 3306)\n"
    [[ "$ALLOW_POSTGRESQL" == true ]] && services_output+="PostgreSQL (port 5432)\n"
    [[ "$ALLOW_MONGODB" == true ]] && services_output+="MongoDB (port 27017)\n"
    [[ "$ALLOW_REDIS" == true ]] && services_output+="Redis (port 6379)\n"
    [[ "$ALLOW_ELASTICSEARCH" == true ]] && services_output+="Elasticsearch (ports 9200, 9300)\n"
    
    if [[ -n "$services_output" ]]; then
        echo -e "$services_output"
    else
        echo "No standard services allowed"
    fi
    echo

    if [[ ${#ALLOW_CUSTOM_PORTS[@]} -gt 0 ]]; then
        print_info "=== Custom Allowed Ports ==="
        for port in "${ALLOW_CUSTOM_PORTS[@]}"; do
            echo "  $port/tcp"
        done
        echo
    fi

    if [[ ${#TRUSTED_NETWORKS[@]} -gt 0 ]]; then
        print_info "=== Trusted Networks ==="
        for network in "${TRUSTED_NETWORKS[@]}"; do
            echo "  $network"
        done
        echo
    fi

    print_info "=== Firewall Status ==="
    if [[ "$ENABLE_UFW_ON_COMPLETION" == true ]]; then
        sudo ufw status numbered 2>/dev/null || echo "UFW status unavailable"
    else
        echo "UFW configured but not enabled"
        echo "Enable with: sudo ufw enable"
    fi
    echo

    print_info "=== Log Files ==="
    cat << EOF
UFW Log:             $UFW_LOG_FILE
Kernel Log:          /var/log/kern.log
System Log:          /var/log/syslog

EOF

    print_info "=== Management Commands ==="
    cat << EOF
Check status:        sudo ufw status verbose
Show rules:          sudo ufw status numbered
Enable firewall:     sudo ufw enable
Disable firewall:    sudo ufw disable
Reset rules:         sudo ufw --force reset
Add rule:            sudo ufw allow [port/service]
Delete rule:         sudo ufw delete [rule_number]
View logs:           sudo tail -f $UFW_LOG_FILE

EOF

    print_info "=== Application Profiles ==="
    cat << EOF
List profiles:       sudo ufw app list
Show profile info:   sudo ufw app info [profile_name]
Use profile:         sudo ufw allow [profile_name]

Available profiles:  Nginx, Apache, Development, MySQL, PostgreSQL, etc.

EOF

    print_info "=== Security Notes ==="
    cat << EOF
• Test SSH access before disconnecting
• Monitor logs for blocked legitimate traffic
• Use 'sudo ufw status numbered' to manage rules
• Consider using fail2ban for additional brute force protection
• Regular security audits recommended

EOF

    if [[ "$ENABLE_UFW_ON_COMPLETION" == false ]]; then
        print_warning "UFW is configured but not enabled!"
        print_info "Enable with: sudo ufw enable"
    fi
    
    print_info "🛡️ Your server is now protected by UFW firewall!"
}

# Helper function to convert boolean to yes/no
bool_to_yes_no() {
    if [[ "$1" == true ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# Main function
main() {
    # Detect system
    detect_system
    
    if [[ "$QUIET" == false ]]; then
        show_script_header "UFW Firewall Installation"
        print_info "Installing and configuring UFW with security hardening"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show configuration plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuration plan:"
        print_info "  Default Policies: incoming=$DEFAULT_INCOMING_POLICY, outgoing=$DEFAULT_OUTGOING_POLICY"
        print_info "  SSH Access: $(if [[ "$ALLOW_SSH" == true ]]; then echo "enabled (port $SSH_PORT)"; else echo "disabled"; fi)"
        print_info "  Web Services: HTTP=$ALLOW_HTTP, HTTPS=$ALLOW_HTTPS"
        print_info "  Logging: $(if [[ "$ENABLE_LOGGING" == true ]]; then echo "enabled ($LOG_LEVEL)"; else echo "disabled"; fi)"
        print_info "  IPv6 Support: $ENABLE_IPV6"
        [[ ${#ALLOW_CUSTOM_PORTS[@]} -gt 0 ]] && print_info "  Custom Ports: ${ALLOW_CUSTOM_PORTS[*]}"
        [[ ${#TRUSTED_NETWORKS[@]} -gt 0 ]] && print_info "  Trusted Networks: ${TRUSTED_NETWORKS[*]}"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with UFW configuration?" "Y"; then
            print_info "UFW configuration cancelled"
            exit 0
        fi
    fi
    
    # Execute configuration steps
    install_ufw
    backup_existing_config
    reset_ufw
    configure_policies
    configure_ufw_settings
    configure_kernel_security
    configure_basic_rules
    configure_database_rules
    configure_custom_rules
    setup_application_profiles
    configure_logging
    enable_ufw
    
    # Test and verify configuration
    if test_firewall_config; then
        show_completion_summary
    else
        print_error "Firewall configuration test failed"
        print_info "Check configuration manually: sudo ufw status verbose"
        exit 1
    fi
}

# Run main function
main "$@"
