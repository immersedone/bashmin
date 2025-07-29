#!/bin/bash
#
# Script: security/fail2ban/install.sh
# Description: Install and configure fail2ban intrusion prevention system
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
readonly FAIL2BAN_CONFIG_DIR="/etc/fail2ban"
readonly FAIL2BAN_MAIN_CONFIG="$FAIL2BAN_CONFIG_DIR/fail2ban.conf"
readonly FAIL2BAN_LOCAL_CONFIG="$FAIL2BAN_CONFIG_DIR/fail2ban.local"
readonly FAIL2BAN_JAIL_CONFIG="$FAIL2BAN_CONFIG_DIR/jail.conf"
readonly FAIL2BAN_JAIL_LOCAL="$FAIL2BAN_CONFIG_DIR/jail.local"
readonly FAIL2BAN_JAIL_DIR="$FAIL2BAN_CONFIG_DIR/jail.d"
readonly FAIL2BAN_FILTER_DIR="$FAIL2BAN_CONFIG_DIR/filter.d"
readonly FAIL2BAN_ACTION_DIR="$FAIL2BAN_CONFIG_DIR/action.d"
readonly FAIL2BAN_LOG_DIR="/var/log/fail2ban"
readonly FAIL2BAN_LOG_FILE="$FAIL2BAN_LOG_DIR/fail2ban.log"
readonly FAIL2BAN_RUN_DIR="/var/run/fail2ban"
readonly FAIL2BAN_SOCKET="$FAIL2BAN_RUN_DIR/fail2ban.sock"
readonly BASHMIN_MAIN_CONFIG="$PROJECT_ROOT/system/etc/fail2ban/fail2ban.conf"
readonly BASHMIN_JAIL_CONFIG="$PROJECT_ROOT/system/etc/fail2ban/jail.conf"
readonly BASHMIN_NGINX_FILTER="$PROJECT_ROOT/system/etc/fail2ban/filter.d/nginx-base-req-limit.conf"
readonly BASHMIN_LOGROTATE_CONF="$PROJECT_ROOT/system/etc/logrotate.d/fail2ban"
readonly BASHMIN_SYSTEMD_SERVICE="$PROJECT_ROOT/system/etc/systemd/system/fail2ban.service"

# Configuration variables
ENABLE_SSH_JAIL=true
ENABLE_NGINX_JAILS=false
ENABLE_APACHE_JAILS=false
ENABLE_POSTFIX_JAILS=false
ENABLE_DOVECOT_JAILS=false
ENABLE_VSFTPD_JAILS=false
ENABLE_PROFTPD_JAILS=false
ENABLE_MYSQL_JAILS=false
ENABLE_PHPMYADMIN_JAILS=false
ENABLE_WORDPRESS_JAILS=false
ENABLE_CUSTOM_JAILS=()
DEFAULT_BAN_TIME="1h"
DEFAULT_FIND_TIME="10m"
DEFAULT_MAX_RETRY="5"
DEFAULT_BACKEND="auto"
LOG_LEVEL="INFO"
LOG_TARGET="file"
IGNORE_IPS=("127.0.0.1/8" "::1")
TRUSTED_NETWORKS=()
ENABLE_EMAIL_NOTIFICATIONS=false
NOTIFICATION_EMAIL=""
EMAIL_SENDER="fail2ban@$(hostname -f)"
SMTP_HOST="localhost"
SMTP_PORT="25"
ENABLE_SLACK_NOTIFICATIONS=false
SLACK_WEBHOOK=""
ENABLE_PERSISTENT_BANS=false
PERSISTENT_BAN_FILE="/var/lib/fail2ban/persistent.bans"
ENABLE_GEOGRAPHIC_BLOCKING=false
BLOCKED_COUNTRIES=()
ENABLE_WHITELIST_MANAGEMENT=true
ENABLE_RECIDIVE_JAIL=true
RECIDIVE_BAN_TIME="1w"
RECIDIVE_FIND_TIME="1d"
RECIDIVE_MAX_RETRY="5"
CUSTOM_ACTIONS=()
FORCE_INSTALL=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Function to show help and exit
show_help_and_exit() {
    cat << EOF
Usage: $0 [OPTIONS]

Install and configure fail2ban intrusion prevention system with advanced security features.

SERVICE JAILS:
    --enable-nginx              Enable Nginx protection jails
    --enable-apache             Enable Apache protection jails
    --enable-postfix            Enable Postfix mail server protection
    --enable-dovecot            Enable Dovecot IMAP/POP3 protection
    --enable-vsftpd             Enable vsftpd FTP server protection
    --enable-proftpd            Enable ProFTPD server protection
    --enable-mysql              Enable MySQL/MariaDB protection
    --enable-phpmyadmin         Enable phpMyAdmin protection
    --enable-wordpress          Enable WordPress protection
    --disable-ssh               Disable SSH protection (enabled by default)

SECURITY SETTINGS:
    --ban-time TIME             Default ban duration (default: 1h)
    --find-time TIME            Time window for violations (default: 10m)
    --max-retry COUNT           Max failures before ban (default: 5)
    --backend TYPE              Log monitoring backend: auto, polling, systemd (default: auto)

NETWORK CONFIGURATION:
    --ignore-ips IPS            Comma-separated IPs to never ban (default: 127.0.0.1/8,::1)
    --trusted-networks NETS     Comma-separated trusted networks to never ban
    --enable-geographic-blocking Enable country-based blocking
    --blocked-countries CODES   Comma-separated country codes to block (e.g., CN,RU,KP)

ADVANCED FEATURES:
    --enable-recidive           Enable recidive jail for repeat offenders (default: enabled)
    --recidive-ban-time TIME    Ban time for repeat offenders (default: 1w)
    --recidive-find-time TIME   Time window for recidive detection (default: 1d)
    --recidive-max-retry COUNT  Max recidive violations (default: 5)
    --enable-persistent-bans    Enable persistent bans across restarts
    --persistent-ban-file FILE  File for persistent ban storage

NOTIFICATIONS:
    --email EMAIL               Email address for ban notifications
    --email-sender EMAIL        Sender email address (default: fail2ban@hostname)
    --smtp-host HOST            SMTP server for notifications (default: localhost)
    --smtp-port PORT            SMTP port (default: 25)
    --slack-webhook URL         Slack webhook URL for notifications

LOGGING:
    --log-level LEVEL           Log level: CRITICAL, ERROR, WARNING, NOTICE, INFO, DEBUG (default: INFO)
    --log-target TARGET         Log target: file, syslog, stdout, stderr (default: file)

CUSTOM CONFIGURATION:
    --custom-jails JAILS        Comma-separated list of custom jail names to enable
    --custom-actions ACTIONS    Comma-separated list of custom actions to configure

SETUP OPTIONS:
    --force                     Force reinstall even if fail2ban is configured
    --quiet                     Suppress non-essential output
    --verbose                   Enable verbose output
    --dry-run                   Show what would be configured without executing
    -h, --help                  Show this help message

SECURITY PROFILES:
    Basic Server:               Default SSH protection only
    Web Server:                 Add --enable-nginx or --enable-apache
    Mail Server:                Add --enable-postfix --enable-dovecot
    Database Server:            Add --enable-mysql --enable-phpmyadmin
    Full Protection:            Add --enable-nginx --enable-postfix --enable-mysql

EXAMPLES:
    # Basic SSH protection
    $0

    # Web server with Nginx protection
    $0 --enable-nginx --ban-time 2h --max-retry 3

    # Mail server configuration
    $0 --enable-postfix --enable-dovecot --email admin@example.com

    # High-security setup with geographic blocking
    $0 --enable-nginx --enable-mysql --blocked-countries CN,RU,KP \
       --ban-time 24h --recidive-ban-time 30d

    # Development server with custom settings
    $0 --trusted-networks 192.168.1.0/24,10.0.0.0/8 \
       --ban-time 30m --max-retry 10

    # Enterprise setup with notifications
    $0 --enable-nginx --enable-postfix --enable-mysql \
       --email security@company.com --slack-webhook https://hooks.slack.com/...

    # Custom jail configuration
    $0 --custom-jails "custom-app,api-protection" \
       --custom-actions "telegram-notify,webhook-alert"

ADVANCED EXAMPLES:
    # Persistent bans with email alerts
    $0 --enable-persistent-bans --email admin@example.com \
       --enable-nginx --ban-time 7d

    # Geographic blocking with Slack notifications
    $0 --enable-geographic-blocking --blocked-countries CN,RU,IR,KP \
       --slack-webhook https://hooks.slack.com/services/... \
       --ban-time 24h

NOTES:
    - Requires sudo privileges
    - Automatically configures iptables/netfilter integration
    - Uses existing bashmin configurations for optimized settings
    - Supports systemd journal monitoring for better performance
    - Creates comprehensive jail configurations for common services
    - Integrates with existing log rotation and system monitoring

SECURITY FEATURES:
    - Intelligent IP whitelisting and trusted network management
    - Recidive jail for repeat offenders with escalating penalties
    - Geographic blocking based on country codes
    - Email and Slack notifications for security events
    - Persistent ban storage across service restarts
    - Custom filter and action support for specialized protection

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --enable-nginx)
            ENABLE_NGINX_JAILS=true
            shift
            ;;
        --enable-apache)
            ENABLE_APACHE_JAILS=true
            shift
            ;;
        --enable-postfix)
            ENABLE_POSTFIX_JAILS=true
            shift
            ;;
        --enable-dovecot)
            ENABLE_DOVECOT_JAILS=true
            shift
            ;;
        --enable-vsftpd)
            ENABLE_VSFTPD_JAILS=true
            shift
            ;;
        --enable-proftpd)
            ENABLE_PROFTPD_JAILS=true
            shift
            ;;
        --enable-mysql)
            ENABLE_MYSQL_JAILS=true
            shift
            ;;
        --enable-phpmyadmin)
            ENABLE_PHPMYADMIN_JAILS=true
            shift
            ;;
        --enable-wordpress)
            ENABLE_WORDPRESS_JAILS=true
            shift
            ;;
        --disable-ssh)
            ENABLE_SSH_JAIL=false
            shift
            ;;
        --ban-time)
            DEFAULT_BAN_TIME="$2"
            shift 2
            ;;
        --find-time)
            DEFAULT_FIND_TIME="$2"
            shift 2
            ;;
        --max-retry)
            DEFAULT_MAX_RETRY="$2"
            shift 2
            ;;
        --backend)
            DEFAULT_BACKEND="$2"
            shift 2
            ;;
        --ignore-ips)
            IFS=',' read -ra IGNORE_IPS <<< "$2"
            shift 2
            ;;
        --trusted-networks)
            IFS=',' read -ra TRUSTED_NETWORKS <<< "$2"
            shift 2
            ;;
        --enable-geographic-blocking)
            ENABLE_GEOGRAPHIC_BLOCKING=true
            shift
            ;;
        --blocked-countries)
            IFS=',' read -ra BLOCKED_COUNTRIES <<< "$2"
            ENABLE_GEOGRAPHIC_BLOCKING=true
            shift 2
            ;;
        --enable-recidive)
            ENABLE_RECIDIVE_JAIL=true
            shift
            ;;
        --recidive-ban-time)
            RECIDIVE_BAN_TIME="$2"
            shift 2
            ;;
        --recidive-find-time)
            RECIDIVE_FIND_TIME="$2"
            shift 2
            ;;
        --recidive-max-retry)
            RECIDIVE_MAX_RETRY="$2"
            shift 2
            ;;
        --enable-persistent-bans)
            ENABLE_PERSISTENT_BANS=true
            shift
            ;;
        --persistent-ban-file)
            PERSISTENT_BAN_FILE="$2"
            ENABLE_PERSISTENT_BANS=true
            shift 2
            ;;
        --email)
            NOTIFICATION_EMAIL="$2"
            ENABLE_EMAIL_NOTIFICATIONS=true
            shift 2
            ;;
        --email-sender)
            EMAIL_SENDER="$2"
            shift 2
            ;;
        --smtp-host)
            SMTP_HOST="$2"
            shift 2
            ;;
        --smtp-port)
            SMTP_PORT="$2"
            shift 2
            ;;
        --slack-webhook)
            SLACK_WEBHOOK="$2"
            ENABLE_SLACK_NOTIFICATIONS=true
            shift 2
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --log-target)
            LOG_TARGET="$2"
            shift 2
            ;;
        --custom-jails)
            IFS=',' read -ra ENABLE_CUSTOM_JAILS <<< "$2"
            shift 2
            ;;
        --custom-actions)
            IFS=',' read -ra CUSTOM_ACTIONS <<< "$2"
            shift 2
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
    
    # Check if Ubuntu/Debian
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_warning "fail2ban installation may differ on $OS"
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
    
    # Check if fail2ban is already configured and force is not set
    if [[ -f "$FAIL2BAN_JAIL_LOCAL" && "$FORCE_INSTALL" == false ]]; then
        print_error "fail2ban is already configured (jail.local exists)"
        print_info "Use --force to reconfigure"
        exit 1
    fi
    
    # Validate log level
    case "$LOG_LEVEL" in
        CRITICAL|ERROR|WARNING|NOTICE|INFO|DEBUG) ;;
        *)
            print_error "Invalid log level: $LOG_LEVEL"
            exit 1
            ;;
    esac
    
    # Validate log target
    case "$LOG_TARGET" in
        file|syslog|stdout|stderr) ;;
        *)
            print_error "Invalid log target: $LOG_TARGET"
            exit 1
            ;;
    esac
    
    # Validate backend
    case "$DEFAULT_BACKEND" in
        auto|polling|systemd|pyinotify|gamin) ;;
        *)
            print_error "Invalid backend: $DEFAULT_BACKEND"
            exit 1
            ;;
    esac
    
    # Validate time formats
    if ! validate_time_format "$DEFAULT_BAN_TIME"; then
        print_error "Invalid ban time format: $DEFAULT_BAN_TIME"
        exit 1
    fi
    
    if ! validate_time_format "$DEFAULT_FIND_TIME"; then
        print_error "Invalid find time format: $DEFAULT_FIND_TIME"
        exit 1
    fi
    
    # Validate max retry
    if [[ ! "$DEFAULT_MAX_RETRY" =~ ^[0-9]+$ ]] || [[ "$DEFAULT_MAX_RETRY" -lt 1 ]] || [[ "$DEFAULT_MAX_RETRY" -gt 50 ]]; then
        print_error "Invalid max retry count: $DEFAULT_MAX_RETRY (1-50)"
        exit 1
    fi
    
    # Validate email format if provided
    if [[ -n "$NOTIFICATION_EMAIL" ]]; then
        if [[ ! "$NOTIFICATION_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "Invalid email format: $NOTIFICATION_EMAIL"
            exit 1
        fi
    fi
    
    # Check for iptables
    if ! command -v iptables >/dev/null 2>&1; then
        print_warning "iptables not found - fail2ban may not work properly"
    fi
    
    # Check for required services if jails are enabled
    check_service_availability
}

# Function to validate time format
validate_time_format() {
    local time_str="$1"
    # Accept formats like: 10m, 1h, 1d, 1w, 600 (seconds)
    if [[ "$time_str" =~ ^[0-9]+[smhdw]?$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check service availability
check_service_availability() {
    if [[ "$ENABLE_NGINX_JAILS" == true ]] && ! command -v nginx >/dev/null 2>&1; then
        print_warning "Nginx not found but Nginx jails requested"
    fi
    
    if [[ "$ENABLE_APACHE_JAILS" == true ]] && ! command -v apache2 >/dev/null 2>&1 && ! command -v httpd >/dev/null 2>&1; then
        print_warning "Apache not found but Apache jails requested"
    fi
    
    if [[ "$ENABLE_POSTFIX_JAILS" == true ]] && ! command -v postfix >/dev/null 2>&1; then
        print_warning "Postfix not found but Postfix jails requested"
    fi
    
    if [[ "$ENABLE_MYSQL_JAILS" == true ]] && ! command -v mysql >/dev/null 2>&1 && ! command -v mariadb >/dev/null 2>&1; then
        print_warning "MySQL/MariaDB not found but MySQL jails requested"
    fi
}

# Function to install fail2ban packages
install_fail2ban() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install fail2ban packages"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installing fail2ban packages..."
    fi
    
    # Update package cache
    sudo apt-get update -qq
    
    # Install packages
    local packages=("fail2ban")
    
    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then
        packages+=("mailutils")
    fi
    
    if [[ "$ENABLE_GEOGRAPHIC_BLOCKING" == true ]]; then
        packages+=("geoip-database" "python3-geoip")
    fi
    
    sudo apt-get install -y "${packages[@]}"
    
    # Verify installation
    if ! command -v fail2ban-server >/dev/null 2>&1; then
        print_error "fail2ban installation failed"
        exit 1
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "fail2ban packages installed successfully"
    fi
}

# Function to create required directories
create_directories() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create fail2ban directories"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Creating fail2ban directories..."
    fi
    
    # Create directories
    sudo mkdir -p "$FAIL2BAN_LOG_DIR"
    sudo mkdir -p "$FAIL2BAN_RUN_DIR"
    sudo mkdir -p "$FAIL2BAN_JAIL_DIR"
    
    if [[ "$ENABLE_PERSISTENT_BANS" == true ]]; then
        sudo mkdir -p "$(dirname "$PERSISTENT_BAN_FILE")"
    fi
    
    # Set permissions
    sudo chown root:adm "$FAIL2BAN_LOG_DIR"
    sudo chmod 755 "$FAIL2BAN_LOG_DIR"
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "fail2ban directories created"
    fi
}

# Function to backup existing configuration
backup_existing_config() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would backup existing fail2ban configuration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Backing up existing fail2ban configuration..."
    fi
    
    local backup_dir="/etc/fail2ban/backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -d "$FAIL2BAN_CONFIG_DIR" ]]; then
        sudo mkdir -p "$backup_dir"
        sudo cp -r "$FAIL2BAN_CONFIG_DIR"/* "$backup_dir"/ 2>/dev/null || true
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Configuration backed up to: $backup_dir"
        fi
    fi
}

# Function to configure main fail2ban settings
configure_main_settings() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure main fail2ban settings"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring main fail2ban settings..."
    fi
    
    # Use bashmin configuration if available, otherwise create custom
    if [[ -f "$BASHMIN_MAIN_CONFIG" ]]; then
        sudo cp "$BASHMIN_MAIN_CONFIG" "$FAIL2BAN_MAIN_CONFIG"
    fi
    
    # Create local configuration overrides
    cat << EOF | sudo tee "$FAIL2BAN_LOCAL_CONFIG" >/dev/null
# fail2ban local configuration
# Generated by bashmin on $(date)

[Definition]
loglevel = $LOG_LEVEL
EOF

    case "$LOG_TARGET" in
        file)
            echo "logtarget = $FAIL2BAN_LOG_FILE" | sudo tee -a "$FAIL2BAN_LOCAL_CONFIG" >/dev/null
            ;;
        syslog)
            echo "logtarget = SYSLOG" | sudo tee -a "$FAIL2BAN_LOCAL_CONFIG" >/dev/null
            ;;
        stdout)
            echo "logtarget = STDOUT" | sudo tee -a "$FAIL2BAN_LOCAL_CONFIG" >/dev/null
            ;;
        stderr)
            echo "logtarget = STDERR" | sudo tee -a "$FAIL2BAN_LOCAL_CONFIG" >/dev/null
            ;;
    esac
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Main fail2ban settings configured"
    fi
}

# Function to configure jail settings
configure_jail_settings() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure fail2ban jail settings"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring fail2ban jail settings..."
    fi
    
    # Use bashmin jail configuration as base if available
    if [[ -f "$BASHMIN_JAIL_CONFIG" ]]; then
        sudo cp "$BASHMIN_JAIL_CONFIG" "$FAIL2BAN_JAIL_CONFIG"
    fi
    
    # Create jail.local with custom settings
    cat << EOF | sudo tee "$FAIL2BAN_JAIL_LOCAL" >/dev/null
# fail2ban jail local configuration
# Generated by bashmin on $(date)

[DEFAULT]
# Ban settings
bantime = $DEFAULT_BAN_TIME
findtime = $DEFAULT_FIND_TIME
maxretry = $DEFAULT_MAX_RETRY

# Backend
backend = $DEFAULT_BACKEND

# Ignore IPs and networks
ignoreip = $(IFS=' '; echo "${IGNORE_IPS[*]}")$(if [[ ${#TRUSTED_NETWORKS[@]} -gt 0 ]]; then echo " $(IFS=' '; echo "${TRUSTED_NETWORKS[*]}")"; fi)

# Actions
EOF

    # Add email action if configured
    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then
        cat << EOF | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null
action = %(action_mwl)s
# Email configuration
destemail = $NOTIFICATION_EMAIL
sender = $EMAIL_SENDER
mta = mail
EOF
    else
        cat << EOF | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null
action = %(action_)s
EOF
    fi
    
    # Configure individual jails
    configure_ssh_jail
    
    if [[ "$ENABLE_NGINX_JAILS" == true ]]; then
        configure_nginx_jails
    fi
    
    if [[ "$ENABLE_APACHE_JAILS" == true ]]; then
        configure_apache_jails
    fi
    
    if [[ "$ENABLE_POSTFIX_JAILS" == true ]]; then
        configure_postfix_jails
    fi
    
    if [[ "$ENABLE_DOVECOT_JAILS" == true ]]; then
        configure_dovecot_jails
    fi
    
    if [[ "$ENABLE_MYSQL_JAILS" == true ]]; then
        configure_mysql_jails
    fi
    
    if [[ "$ENABLE_PHPMYADMIN_JAILS" == true ]]; then
        configure_phpmyadmin_jails
    fi
    
    if [[ "$ENABLE_WORDPRESS_JAILS" == true ]]; then
        configure_wordpress_jails
    fi
    
    if [[ "$ENABLE_RECIDIVE_JAIL" == true ]]; then
        configure_recidive_jail
    fi
    
    # Configure custom jails
    configure_custom_jails
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Jail settings configured"
    fi
}

# Function to configure SSH jail
configure_ssh_jail() {
    if [[ "$ENABLE_SSH_JAIL" == false ]]; then
        return 0
    fi
    
    cat << 'EOF' | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null

# SSH jail
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 1h
EOF
}

# Function to configure Nginx jails
configure_nginx_jails() {
    cat << 'EOF' | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null

# Nginx jails
[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[nginx-noscript]
enabled = true
filter = nginx-noscript
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 6

[nginx-bad-request]
enabled = true
filter = nginx-bad-request
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2

[nginx-noproxy]
enabled = true
filter = nginx-noproxy
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2

EOF
    
    # Add custom nginx rate limiting filter if available
    if [[ -f "$BASHMIN_NGINX_FILTER" ]]; then
        sudo cp "$BASHMIN_NGINX_FILTER" "$FAIL2BAN_FILTER_DIR/"
        cat << 'EOF' | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null
[nginx-req-limit]
enabled = true
filter = nginx-base-req-limit
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 60
bantime = 300

EOF
    fi
}

# Function to configure Apache jails
configure_apache_jails() {
    cat << 'EOF' | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null

# Apache jails
[apache-auth]
enabled = true
filter = apache-auth
port = http,https
logpath = /var/log/apache*/*error.log
maxretry = 6

[apache-badbots]
enabled = true
filter = apache-badbots
port = http,https
logpath = /var/log/apache*/*access.log
bantime = 48h
maxretry = 1

[apache-noscript]
enabled = true
filter = apache-noscript
port = http,https
logpath = /var/log/apache*/*access.log

[apache-overflows]
enabled = true
filter = apache-overflows
port = http,https
logpath = /var/log/apache*/*error.log
maxretry = 2

[apache-nohome]
enabled = true
filter = apache-nohome
port = http,https
logpath = /var/log/apache*/*access.log
maxretry = 2

[apache-botsearch]
enabled = true
filter = apache-botsearch
port = http,https
logpath = /var/log/apache*/*access.log

EOF
}

# Function to configure Postfix jails
configure_postfix_jails() {
    cat << 'EOF' | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null

# Postfix jails
[postfix-sasl]
enabled = true
filter = postfix-sasl
port = smtp,465,submission
logpath = /var/log/mail.log
backend = %(postfix_backend)s

[postfix-rbl]
enabled = true
filter = postfix-rbl
port = smtp,465,submission
logpath = /var/log/mail.log
backend = %(postfix_backend)s
maxretry = 1

[postfix]
enabled = true
filter = postfix
port = smtp,465,submission
logpath = /var/log/mail.log
backend = %(postfix_backend)s

EOF
}

# Function to configure Dovecot jails
configure_dovecot_jails() {
    cat << 'EOF' | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null

# Dovecot jails
[dovecot]
enabled = true
filter = dovecot
port = pop3,pop3s,imap,imaps,submission,465,sieve
logpath = /var/log/mail.log
backend = %(dovecot_backend)s

EOF
}

# Function to configure MySQL jails
configure_mysql_jails() {
    cat << 'EOF' | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null

# MySQL jails
[mysqld-auth]
enabled = true
filter = mysqld-auth
port = 3306
logpath = /var/log/mysql/error.log
maxretry = 5

EOF
}

# Function to configure phpMyAdmin jails
configure_phpmyadmin_jails() {
    cat << 'EOF' | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null

# phpMyAdmin jails
[phpmyadmin-syslog]
enabled = true
filter = phpmyadmin-syslog
port = http,https
logpath = /var/log/auth.log

EOF
}

# Function to configure WordPress jails
configure_wordpress_jails() {
    cat << 'EOF' | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null

# WordPress jails
[wordpress-auth]
enabled = true
filter = wordpress-auth
port = http,https
logpath = /var/log/nginx/access.log
          /var/log/apache*/*access.log
maxretry = 3

[wordpress-hard]
enabled = true
filter = wordpress-hard
port = http,https
logpath = /var/log/nginx/access.log
          /var/log/apache*/*access.log
maxretry = 1
bantime = 1d

[wordpress-soft]
enabled = true
filter = wordpress-soft
port = http,https
logpath = /var/log/nginx/access.log
          /var/log/apache*/*access.log
maxretry = 5
bantime = 1h

EOF
}

# Function to configure recidive jail
configure_recidive_jail() {
    cat << EOF | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null

# Recidive jail for repeat offenders
[recidive]
enabled = true
filter = recidive
logpath = $FAIL2BAN_LOG_FILE
action = %(action_mwl)s
bantime = $RECIDIVE_BAN_TIME
findtime = $RECIDIVE_FIND_TIME
maxretry = $RECIDIVE_MAX_RETRY

EOF
}

# Function to configure custom jails
configure_custom_jails() {
    for jail in "${ENABLE_CUSTOM_JAILS[@]}"; do
        cat << EOF | sudo tee -a "$FAIL2BAN_JAIL_LOCAL" >/dev/null

# Custom jail: $jail
[$jail]
enabled = true
filter = $jail
port = http,https
logpath = /var/log/custom/$jail.log
maxretry = 5

EOF
    done
}

# Function to configure custom filters
configure_custom_filters() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure custom filters"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring custom filters..."
    fi
    
    # Copy bashmin custom filters
    if [[ -f "$BASHMIN_NGINX_FILTER" ]]; then
        sudo cp "$BASHMIN_NGINX_FILTER" "$FAIL2BAN_FILTER_DIR/"
    fi
    
    # Create WordPress filters if enabled
    if [[ "$ENABLE_WORDPRESS_JAILS" == true ]]; then
        create_wordpress_filters
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Custom filters configured"
    fi
}

# Function to create WordPress filters
create_wordpress_filters() {
    # WordPress authentication filter
    cat << 'EOF' | sudo tee "$FAIL2BAN_FILTER_DIR/wordpress-auth.conf" >/dev/null
[Definition]
failregex = ^<HOST> .* "POST .*wp-login\.php
            ^<HOST> .* "POST .*xmlrpc\.php
ignoreregex =
EOF
    
    # WordPress hard attacks filter
    cat << 'EOF' | sudo tee "$FAIL2BAN_FILTER_DIR/wordpress-hard.conf" >/dev/null
[Definition]
failregex = ^<HOST> .* "(GET|POST) .*/wp-admin.*"
            ^<HOST> .* "(GET|POST) .*/wp-content/uploads/.*\.php"
            ^<HOST> .* "(GET|POST) .*eval\(.*"
            ^<HOST> .* "(GET|POST) .*base64_decode.*"
ignoreregex =
EOF
    
    # WordPress soft attacks filter
    cat << 'EOF' | sudo tee "$FAIL2BAN_FILTER_DIR/wordpress-soft.conf" >/dev/null
[Definition]
failregex = ^<HOST> .* "GET .*\?.*(\"|'|\)|\(|;|\||`).*"
            ^<HOST> .* "GET .*wp-config\.php.*"
            ^<HOST> .* "GET .*wp-includes.*"
ignoreregex =
EOF
}

# Function to configure custom actions
configure_custom_actions() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure custom actions"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring custom actions..."
    fi
    
    # Configure Slack notifications if enabled
    if [[ "$ENABLE_SLACK_NOTIFICATIONS" == true ]]; then
        create_slack_action
    fi
    
    # Configure persistent bans if enabled
    if [[ "$ENABLE_PERSISTENT_BANS" == true ]]; then
        create_persistent_ban_action
    fi
    
    # Configure geographic blocking if enabled
    if [[ "$ENABLE_GEOGRAPHIC_BLOCKING" == true ]]; then
        create_geographic_blocking_action
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Custom actions configured"
    fi
}

# Function to create Slack action
create_slack_action() {
    cat << EOF | sudo tee "$FAIL2BAN_ACTION_DIR/slack-webhook.conf" >/dev/null
[Definition]
actionstart = curl -X POST -H 'Content-type: application/json' --data '{"text":"fail2ban <name> jail started"}' $SLACK_WEBHOOK
actionstop = curl -X POST -H 'Content-type: application/json' --data '{"text":"fail2ban <name> jail stopped"}' $SLACK_WEBHOOK
actioncheck =
actionban = curl -X POST -H 'Content-type: application/json' --data '{"text":"fail2ban: banned <ip> from <name> jail"}' $SLACK_WEBHOOK
actionunban = curl -X POST -H 'Content-type: application/json' --data '{"text":"fail2ban: unbanned <ip> from <name> jail"}' $SLACK_WEBHOOK

[Init]
name = default

EOF
}

# Function to create persistent ban action
create_persistent_ban_action() {
    cat << EOF | sudo tee "$FAIL2BAN_ACTION_DIR/persistent-bans.conf" >/dev/null
[Definition]
actionstart = touch $PERSISTENT_BAN_FILE
actionstop =
actioncheck =
actionban = echo "<ip>" >> $PERSISTENT_BAN_FILE
actionunban = sed -i '/<ip>/d' $PERSISTENT_BAN_FILE

[Init]

EOF
    
    # Create script to restore persistent bans on startup
    cat << 'EOF' | sudo tee /usr/local/bin/fail2ban-restore-bans.sh >/dev/null
#!/bin/bash
# Restore persistent bans on fail2ban startup

PERSISTENT_BAN_FILE="/var/lib/fail2ban/persistent.bans"

if [[ -f "$PERSISTENT_BAN_FILE" ]]; then
    while read -r ip; do
        if [[ -n "$ip" ]]; then
            fail2ban-client set recidive banip "$ip" 2>/dev/null || true
        fi
    done < "$PERSISTENT_BAN_FILE"
fi
EOF
    
    sudo chmod +x /usr/local/bin/fail2ban-restore-bans.sh
}

# Function to create geographic blocking action
create_geographic_blocking_action() {
    if [[ ${#BLOCKED_COUNTRIES[@]} -eq 0 ]]; then
        return 0
    fi
    
    cat << 'EOF' | sudo tee "$FAIL2BAN_ACTION_DIR/geoip-block.conf" >/dev/null
[Definition]
actionstart =
actionstop =
actioncheck =
actionban = COUNTRY=$(geoiplookup <ip> | awk -F': ' '{print $2}' | awk -F', ' '{print $1}')
            if echo "$(blocked_countries)" | grep -q "$COUNTRY"; then
                iptables -I fail2ban-geoblock -s <ip> -j DROP
            fi
actionunban = iptables -D fail2ban-geoblock -s <ip> -j DROP 2>/dev/null || true

[Init]
blocked_countries = %BLOCKED_COUNTRIES%

EOF
    
    # Replace placeholder with actual countries
    local countries_str=$(IFS=','; echo "${BLOCKED_COUNTRIES[*]}")
    sudo sed -i "s/%BLOCKED_COUNTRIES%/$countries_str/g" "$FAIL2BAN_ACTION_DIR/geoip-block.conf"
}

# Function to configure log rotation
configure_log_rotation() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure log rotation"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring log rotation..."
    fi
    
    # Use bashmin logrotate configuration if available
    if [[ -f "$BASHMIN_LOGROTATE_CONF" ]]; then
        sudo cp "$BASHMIN_LOGROTATE_CONF" /etc/logrotate.d/fail2ban
    else
        create_logrotate_config
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Log rotation configured"
    fi
}

# Function to create logrotate configuration
create_logrotate_config() {
    cat << 'EOF' | sudo tee /etc/logrotate.d/fail2ban >/dev/null
/var/log/fail2ban.log {
    rotate 30
    dateext
    dateformat -%Y-%m-%d
    daily
    rotate 4
    compress
    delaycompress
    missingok
    postrotate
        fail2ban-client flushlogs 1>/dev/null
    endscript
    create 640 root adm
}
EOF
}

# Function to configure systemd service
configure_systemd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure systemd service"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring systemd service..."
    fi
    
    # Use bashmin systemd service if available
    if [[ -f "$BASHMIN_SYSTEMD_SERVICE" ]]; then
        sudo cp "$BASHMIN_SYSTEMD_SERVICE" /etc/systemd/system/fail2ban.service
    fi
    
    # Enable service
    sudo systemctl daemon-reload
    sudo systemctl enable fail2ban
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Systemd service configured"
    fi
}

# Function to start services
start_services() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would start fail2ban service"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Starting fail2ban service..."
    fi
    
    # Start fail2ban
    sudo systemctl start fail2ban
    
    # Check status
    if sudo systemctl is-active fail2ban >/dev/null 2>&1; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "fail2ban service started successfully"
        fi
    else
        print_error "Failed to start fail2ban service"
        return 1
    fi
}

# Function to test configuration
test_configuration() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test fail2ban configuration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Testing fail2ban configuration..."
    fi
    
    # Test configuration syntax
    if sudo fail2ban-client -t >/dev/null 2>&1; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "fail2ban configuration syntax is valid"
        fi
    else
        print_error "fail2ban configuration syntax error"
        return 1
    fi
    
    # Test jail status
    local jail_count
    jail_count=$(sudo fail2ban-client status 2>/dev/null | grep "Jail list:" | awk -F: '{print $2}' | wc -w)
    
    if [[ "$jail_count" -gt 0 ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "fail2ban has $jail_count active jails"
        fi
    else
        print_warning "No active jails found"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Configuration testing completed"
    fi
}

# Function to show completion summary
show_completion_summary() {
    if [[ "$QUIET" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo
    print_success "fail2ban installation and configuration completed successfully! 🛡️"
    echo
    print_info "=== fail2ban Configuration Summary ==="
    cat << EOF
General Settings:
  Ban Time:              $DEFAULT_BAN_TIME
  Find Time:             $DEFAULT_FIND_TIME
  Max Retry:             $DEFAULT_MAX_RETRY
  Backend:               $DEFAULT_BACKEND
  Log Level:             $LOG_LEVEL
  Log Target:            $LOG_TARGET

EOF

    print_info "=== Active Jails ==="
    local jails_output=""
    [[ "$ENABLE_SSH_JAIL" == true ]] && jails_output+="SSH (sshd)\n"
    [[ "$ENABLE_NGINX_JAILS" == true ]] && jails_output+="Nginx (http-auth, noscript, bad-request, noproxy, botsearch)\n"
    [[ "$ENABLE_APACHE_JAILS" == true ]] && jails_output+="Apache (auth, badbots, noscript, overflows, nohome, botsearch)\n"
    [[ "$ENABLE_POSTFIX_JAILS" == true ]] && jails_output+="Postfix (postfix, postfix-sasl, postfix-rbl)\n"
    [[ "$ENABLE_DOVECOT_JAILS" == true ]] && jails_output+="Dovecot (dovecot)\n"
    [[ "$ENABLE_MYSQL_JAILS" == true ]] && jails_output+="MySQL (mysqld-auth)\n"
    [[ "$ENABLE_PHPMYADMIN_JAILS" == true ]] && jails_output+="phpMyAdmin (phpmyadmin-syslog)\n"
    [[ "$ENABLE_WORDPRESS_JAILS" == true ]] && jails_output+="WordPress (wordpress-auth, wordpress-hard, wordpress-soft)\n"
    [[ "$ENABLE_RECIDIVE_JAIL" == true ]] && jails_output+="Recidive (repeat offenders)\n"
    
    if [[ -n "$jails_output" ]]; then
        echo -e "$jails_output"
    else
        echo "Only SSH jail enabled"
    fi
    echo

    if [[ ${#TRUSTED_NETWORKS[@]} -gt 0 ]]; then
        print_info "=== Trusted Networks (Never Banned) ==="
        for network in "${TRUSTED_NETWORKS[@]}"; do
            echo "  $network"
        done
        echo
    fi

    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then
        print_info "=== Email Notifications ==="
        cat << EOF
Notification Email:    $NOTIFICATION_EMAIL
Email Sender:          $EMAIL_SENDER
SMTP Host:             $SMTP_HOST:$SMTP_PORT

EOF
    fi

    if [[ "$ENABLE_SLACK_NOTIFICATIONS" == true ]]; then
        print_info "=== Slack Notifications ==="
        echo "Webhook URL: $SLACK_WEBHOOK"
        echo
    fi

    print_info "=== File Locations ==="
    cat << EOF
Configuration:         $FAIL2BAN_CONFIG_DIR
Local Configuration:   $FAIL2BAN_JAIL_LOCAL
Log File:              $FAIL2BAN_LOG_FILE
Socket:                $FAIL2BAN_SOCKET
Filters:               $FAIL2BAN_FILTER_DIR
Actions:               $FAIL2BAN_ACTION_DIR

EOF

    if [[ "$ENABLE_PERSISTENT_BANS" == true ]]; then
        print_info "=== Persistent Bans ==="
        echo "Ban File: $PERSISTENT_BAN_FILE"
        echo "Restore Script: /usr/local/bin/fail2ban-restore-bans.sh"
        echo
    fi

    print_info "=== Service Status ==="
    sudo systemctl is-active fail2ban 2>/dev/null || echo "fail2ban: inactive"
    sudo systemctl is-enabled fail2ban 2>/dev/null || echo "fail2ban: disabled"
    echo

    print_info "=== Active Jails Status ==="
    sudo fail2ban-client status 2>/dev/null || echo "Unable to get jail status"
    echo

    print_info "=== Management Commands ==="
    cat << EOF
Check status:          sudo fail2ban-client status
List jails:            sudo fail2ban-client status
Jail status:           sudo fail2ban-client status [jail_name]
Ban IP manually:       sudo fail2ban-client set [jail] banip [ip]
Unban IP:              sudo fail2ban-client set [jail] unbanip [ip]
Reload configuration:  sudo fail2ban-client reload
View logs:             sudo tail -f $FAIL2BAN_LOG_FILE

EOF

    print_info "=== Jail Management ==="
    cat << EOF
View banned IPs:       sudo fail2ban-client status sshd
Start jail:            sudo fail2ban-client start [jail_name]
Stop jail:             sudo fail2ban-client stop [jail_name]
Jail statistics:       sudo fail2ban-client status [jail_name]

EOF

    print_info "=== Log Analysis ==="
    cat << EOF
Recent bans:           sudo grep "Ban " $FAIL2BAN_LOG_FILE | tail -10
Recent unbans:         sudo grep "Unban " $FAIL2BAN_LOG_FILE | tail -10
Jail activity:         sudo grep "\[sshd\]" $FAIL2BAN_LOG_FILE | tail -10
Error logs:            sudo grep "ERROR" $FAIL2BAN_LOG_FILE

EOF

    print_info "=== Security Notes ==="
    cat << EOF
• Monitor banned IPs regularly to avoid blocking legitimate users
• Review logs for persistent attack patterns
• Consider geographic blocking for high-risk countries
• Use trusted networks for administrative access
• Test ban/unban functionality after configuration changes
• Keep fail2ban filters updated for new attack vectors

EOF

    if [[ "$ENABLE_RECIDIVE_JAIL" == true ]]; then
        print_info "Recidive jail is active - repeat offenders get longer bans ($RECIDIVE_BAN_TIME)"
    fi
    
    if [[ "$ENABLE_GEOGRAPHIC_BLOCKING" == true ]]; then
        print_info "Geographic blocking is enabled for countries: ${BLOCKED_COUNTRIES[*]}"
    fi
    
    print_info "🔒 Your server is now protected by fail2ban intrusion prevention!"
}

# Main function
main() {
    # Detect system
    detect_system
    
    if [[ "$QUIET" == false ]]; then
        show_script_header "fail2ban Intrusion Prevention Installation"
        print_info "Installing and configuring fail2ban with advanced security features"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show configuration plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuration plan:"
        print_info "  SSH Protection: $ENABLE_SSH_JAIL"
        print_info "  Nginx Protection: $ENABLE_NGINX_JAILS"
        print_info "  Apache Protection: $ENABLE_APACHE_JAILS"
        print_info "  Mail Protection: $(if [[ "$ENABLE_POSTFIX_JAILS" == true || "$ENABLE_DOVECOT_JAILS" == true ]]; then echo "enabled"; else echo "disabled"; fi)"
        print_info "  Database Protection: $ENABLE_MYSQL_JAILS"
        print_info "  Ban Time: $DEFAULT_BAN_TIME"
        print_info "  Max Retry: $DEFAULT_MAX_RETRY"
        print_info "  Email Notifications: $ENABLE_EMAIL_NOTIFICATIONS"
        [[ -n "$NOTIFICATION_EMAIL" ]] && print_info "  Notification Email: $NOTIFICATION_EMAIL"
        print_info "  Recidive Jail: $ENABLE_RECIDIVE_JAIL"
        print_info "  Persistent Bans: $ENABLE_PERSISTENT_BANS"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with fail2ban configuration?" "Y"; then
            print_info "fail2ban configuration cancelled"
            exit 0
        fi
    fi
    
    # Execute installation steps
    install_fail2ban
    create_directories
    backup_existing_config
    configure_main_settings
    configure_jail_settings
    configure_custom_filters
    configure_custom_actions
    configure_log_rotation
    configure_systemd
    start_services
    
    # Test and verify configuration
    if test_configuration; then
        show_completion_summary
    else
        print_error "fail2ban configuration test failed"
        print_info "Check configuration manually: sudo fail2ban-client -t"
        exit 1
    fi
}

# Run main function
main "$@"
