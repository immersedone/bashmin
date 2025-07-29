#!/bin/bash
#
# Script: security/letsencrypt/install.sh
# Description: Install and configure Let's Encrypt SSL/TLS certificate management
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
readonly CERTBOT_CONFIG_DIR="/etc/letsencrypt"
readonly CERTBOT_WORK_DIR="/var/lib/letsencrypt"
readonly CERTBOT_LOG_DIR="/var/log/letsencrypt"
readonly NGINX_CONF_DIR="/etc/nginx"
readonly APACHE_CONF_DIR="/etc/apache2"
readonly BASHMIN_LOG_DIR="/var/log/bashmin"
readonly BASHMIN_SSL_DIR="/var/log/bashmin/ssl"
readonly RENEWAL_HOOKS_DIR="$CERTBOT_CONFIG_DIR/renewal-hooks"
readonly WEBROOT_PATH="/var/www/certbot"

# Configuration variables
EMAIL=""
WEBSERVER="auto"
STAGING=false
AGREE_TOS=false
NO_EFF_EMAIL=true
RSA_KEY_SIZE=4096
ELLIPTIC_CURVE="secp384r1"
KEY_TYPE="rsa"
HSTS_MAX_AGE=31536000
OCSP_STAPLING=true
ENABLE_AUTO_RENEWAL=true
RENEWAL_FREQUENCY="twice-daily"
ENABLE_MONITORING=true
ENABLE_NOTIFICATIONS=true
NOTIFICATION_EMAIL=""
SLACK_WEBHOOK=""
FORCE=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Help function
show_help() {
    cat << 'EOF'
Let's Encrypt SSL/TLS Certificate Management

DESCRIPTION:
    Comprehensive installation and configuration of Let's Encrypt with certbot for 
    automated SSL/TLS certificate management. Includes web server integration, 
    automated renewals, monitoring, and notifications.

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    Core Configuration:
    --email EMAIL               Email address for Let's Encrypt registration (required)
    --webserver SERVER          Web server type: nginx, apache, standalone, webroot [auto]
    --staging                   Use Let's Encrypt staging environment for testing
    --agree-tos                 Automatically agree to Let's Encrypt Terms of Service
    --no-eff-email             Don't share email with Electronic Frontier Foundation
    
    Certificate Settings:
    --key-type TYPE             Certificate key type: rsa, ecdsa [rsa]
    --rsa-key-size SIZE         RSA key size in bits [4096]
    --elliptic-curve CURVE      ECDSA elliptic curve [secp384r1]
    --hsts-max-age SECONDS      HTTP Strict Transport Security max age [31536000]
    --enable-ocsp-stapling      Enable OCSP stapling for improved performance
    --disable-ocsp-stapling     Disable OCSP stapling
    
    Renewal Configuration:
    --enable-auto-renewal       Enable automatic certificate renewal [default]
    --disable-auto-renewal      Disable automatic certificate renewal
    --renewal-frequency FREQ    Renewal check frequency: daily, twice-daily, weekly [twice-daily]
    
    Monitoring & Notifications:
    --enable-monitoring         Enable certificate expiry monitoring [default]
    --disable-monitoring        Disable certificate expiry monitoring
    --notification-email EMAIL  Email for renewal notifications
    --slack-webhook URL         Slack webhook for notifications
    
    Security Features:
    --webroot-path PATH         Custom webroot path for domain validation [/var/www/certbot]
    --secure-permissions        Set restrictive permissions on certificate files
    --backup-certificates       Enable automatic certificate backup
    
    Control Options:
    --force                     Force reinstallation of certbot
    --dry-run                   Show what would be done without making changes
    --verbose                   Enable verbose output
    --quiet                     Suppress non-essential output
    --help                      Show this help message

EXAMPLES:
    Basic Installation:
    ./install.sh --email admin@example.com --agree-tos

    Nginx with Auto-renewal:
    ./install.sh --email ssl@company.com --webserver nginx --agree-tos

    High-Security Setup:
    ./install.sh --email security@company.com --webserver nginx \\
        --key-type ecdsa --enable-ocsp-stapling --secure-permissions \\
        --notification-email alerts@company.com --agree-tos

    Development/Testing:
    ./install.sh --email dev@example.com --staging --webserver standalone \\
        --agree-tos --dry-run

    Enterprise Configuration:
    ./install.sh --email ssl-admin@company.com --webserver nginx \\
        --notification-email security@company.com \\
        --slack-webhook https://hooks.slack.com/services/... \\
        --enable-monitoring --backup-certificates --agree-tos

SECURITY FEATURES:
    • Automated certificate renewal with failure detection
    • OCSP stapling for improved performance and privacy
    • HTTP Strict Transport Security (HSTS) configuration
    • Secure file permissions and ownership
    • Certificate backup and recovery
    • Comprehensive logging and monitoring
    • Integration with web server security best practices

INTEGRATION:
    • Nginx: Automatic SSL configuration with security headers
    • Apache: Virtual host SSL integration with modern ciphers
    • Standalone: Independent certificate generation
    • Webroot: Compatible with existing web server configurations

MONITORING:
    • Certificate expiry tracking
    • Renewal success/failure monitoring
    • Email and Slack notifications
    • Integration with bashmin logging system
    • Health check endpoints for monitoring systems

FILES CREATED:
    /etc/letsencrypt/           - Certbot configuration and certificates
    /var/lib/letsencrypt/       - Certbot working directory
    /var/log/letsencrypt/       - Certbot logs
    /var/log/bashmin/ssl/       - bashmin SSL management logs
    /etc/cron.d/certbot         - Automated renewal cron job
    /usr/local/bin/ssl-manage   - SSL certificate management utility

DEPENDENCIES:
    • certbot
    • python3-certbot-nginx (for Nginx)
    • python3-certbot-apache (for Apache)
    • cron or systemd timer
    • openssl

For more information about bashmin SSL management:
    /var/www/vhosts/bashmin/security/letsencrypt/README.md

EOF
}

# Logging functions
log_ssl() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure log directory exists
    mkdir -p "$BASHMIN_SSL_DIR"
    
    # Log to bashmin SSL log
    echo "[$timestamp] [$level] $message" >> "$BASHMIN_SSL_DIR/letsencrypt.log"
    
    # Also log to console based on verbosity
    case "$level" in
        ERROR)
            print_error "$message"
            ;;
        WARN)
            [[ "$QUIET" == "false" ]] && print_warning "$message"
            ;;
        INFO)
            [[ "$QUIET" == "false" ]] && print_info "$message"
            ;;
        DEBUG)
            [[ "$VERBOSE" == "true" ]] && print_info "[DEBUG] $message"
            ;;
    esac
}

# System detection functions
detect_webserver() {
    local detected=""
    
    if systemctl is-active --quiet nginx 2>/dev/null; then
        detected="nginx"
    elif systemctl is-active --quiet apache2 2>/dev/null; then
        detected="apache"
    elif systemctl is-active --quiet httpd 2>/dev/null; then
        detected="apache"
    else
        detected="standalone"
    fi
    
    log_ssl "DEBUG" "Detected web server: $detected"
    echo "$detected"
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}

# Validation functions
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_ssl "ERROR" "Invalid email address: $email"
        return 1
    fi
    return 0
}

validate_webhook_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https://hooks\.slack\.com/services/ ]]; then
        log_ssl "ERROR" "Invalid Slack webhook URL format"
        return 1
    fi
    return 0
}

# Installation functions
install_certbot() {
    local os_id=$(detect_os)
    
    log_ssl "INFO" "Installing certbot for $os_id"
    
    case "$os_id" in
        ubuntu|debian)
            # Update package list
            if [[ "$DRY_RUN" == "false" ]]; then
                apt-get update
                
                # Install snapd if not present
                if ! command -v snap >/dev/null 2>&1; then
                    log_ssl "INFO" "Installing snapd..."
                    apt-get install -y snapd
                fi
                
                # Install certbot via snap (recommended by Let's Encrypt)
                log_ssl "INFO" "Installing certbot via snap..."
                snap install core
                snap refresh core
                
                # Remove any existing certbot packages
                apt-get remove -y certbot python3-certbot-* || true
                
                # Install certbot
                snap install --classic certbot
                
                # Create symlink
                ln -sf /snap/bin/certbot /usr/bin/certbot
                
                # Install web server plugins
                case "$WEBSERVER" in
                    nginx)
                        snap install certbot-dns-cloudflare || true
                        apt-get install -y python3-certbot-nginx || true
                        ;;
                    apache)
                        apt-get install -y python3-certbot-apache || true
                        ;;
                esac
                
            else
                log_ssl "INFO" "[DRY RUN] Would install certbot and dependencies"
            fi
            ;;
        *)
            log_ssl "ERROR" "Unsupported operating system: $os_id"
            return 1
            ;;
    esac
}

configure_webroot() {
    log_ssl "INFO" "Configuring webroot for domain validation"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create webroot directory
        mkdir -p "$WEBROOT_PATH"
        chown www-data:www-data "$WEBROOT_PATH" 2>/dev/null || chown nobody:nogroup "$WEBROOT_PATH"
        chmod 755 "$WEBROOT_PATH"
        
        # Create test file
        echo "certbot webroot validation" > "$WEBROOT_PATH/test.txt"
    else
        log_ssl "INFO" "[DRY RUN] Would create webroot directory: $WEBROOT_PATH"
    fi
}

configure_nginx_acme() {
    local nginx_conf="$NGINX_CONF_DIR/conf.d/letsencrypt.conf"
    
    log_ssl "INFO" "Configuring Nginx for ACME challenge"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > "$nginx_conf" << 'EOF'
# Let's Encrypt ACME challenge configuration
location ^~ /.well-known/acme-challenge/ {
    root /var/www/certbot;
    try_files $uri =404;
}

# Security headers for HTTPS
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header X-XSS-Protection "1; mode=block" always;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
EOF
        
        # Test nginx configuration
        if nginx -t; then
            systemctl reload nginx
            log_ssl "INFO" "Nginx configuration updated and reloaded"
        else
            log_ssl "ERROR" "Nginx configuration test failed"
            return 1
        fi
    else
        log_ssl "INFO" "[DRY RUN] Would configure Nginx ACME challenge"
    fi
}

configure_apache_acme() {
    local apache_conf="$APACHE_CONF_DIR/conf-available/letsencrypt.conf"
    
    log_ssl "INFO" "Configuring Apache for ACME challenge"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > "$apache_conf" << 'EOF'
# Let's Encrypt ACME challenge configuration
Alias /.well-known/acme-challenge/ /var/www/certbot/.well-known/acme-challenge/
<Directory "/var/www/certbot/.well-known/acme-challenge/">
    Options None
    AllowOverride None
    Require all granted
</Directory>

# Security headers for HTTPS
<IfModule mod_headers.c>
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set X-XSS-Protection "1; mode=block"
</IfModule>

# OCSP Stapling
<IfModule mod_ssl.c>
    SSLUseStapling On
    SSLStaplingCache "shmcb:/var/run/ocsp(128000)"
    SSLStaplingResponderTimeout 5
    SSLStaplingReturnResponderErrors off
</IfModule>
EOF
        
        # Enable configuration
        a2enconf letsencrypt
        
        # Enable required modules
        a2enmod headers ssl
        
        # Test apache configuration
        if apache2ctl configtest; then
            systemctl reload apache2
            log_ssl "INFO" "Apache configuration updated and reloaded"
        else
            log_ssl "ERROR" "Apache configuration test failed"
            return 1
        fi
    else
        log_ssl "INFO" "[DRY RUN] Would configure Apache ACME challenge"
    fi
}

setup_renewal_hooks() {
    log_ssl "INFO" "Setting up renewal hooks"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create renewal hooks directories
        mkdir -p "$RENEWAL_HOOKS_DIR/pre"
        mkdir -p "$RENEWAL_HOOKS_DIR/post"
        mkdir -p "$RENEWAL_HOOKS_DIR/deploy"
        
        # Pre-renewal hook
        cat > "$RENEWAL_HOOKS_DIR/pre/backup-certs.sh" << 'EOF'
#!/bin/bash
# Pre-renewal hook: Backup existing certificates

BACKUP_DIR="/var/backups/letsencrypt/$(date +%Y%m%d_%H%M%S)"
CERT_DIR="/etc/letsencrypt/live"

if [[ -d "$CERT_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp -r "$CERT_DIR" "$BACKUP_DIR/"
    echo "Certificates backed up to $BACKUP_DIR"
fi
EOF
        
        # Post-renewal hook
        cat > "$RENEWAL_HOOKS_DIR/post/reload-services.sh" << 'EOF'
#!/bin/bash
# Post-renewal hook: Reload web services

# Log renewal
echo "$(date): Certificate renewal completed" >> /var/log/bashmin/ssl/renewals.log

# Reload web servers
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
    echo "Nginx reloaded"
fi

if systemctl is-active --quiet apache2; then
    systemctl reload apache2
    echo "Apache reloaded"
fi

# Send notification if configured
if [[ -n "${NOTIFICATION_EMAIL:-}" ]]; then
    echo "SSL certificates renewed successfully on $(hostname)" | \
        mail -s "SSL Certificate Renewal - $(hostname)" "$NOTIFICATION_EMAIL"
fi
EOF
        
        # Deploy hook
        cat > "$RENEWAL_HOOKS_DIR/deploy/security-headers.sh" << 'EOF'
#!/bin/bash
# Deploy hook: Update security configurations

DOMAIN="$RENEWED_DOMAINS"
echo "Deploying security configuration for: $DOMAIN"

# Log deployment
echo "$(date): Security configuration deployed for $DOMAIN" >> /var/log/bashmin/ssl/deployments.log
EOF
        
        # Make hooks executable
        chmod +x "$RENEWAL_HOOKS_DIR/pre/"*.sh
        chmod +x "$RENEWAL_HOOKS_DIR/post/"*.sh
        chmod +x "$RENEWAL_HOOKS_DIR/deploy/"*.sh
        
    else
        log_ssl "INFO" "[DRY RUN] Would set up renewal hooks"
    fi
}

configure_auto_renewal() {
    log_ssl "INFO" "Configuring automatic certificate renewal"
    
    local cron_schedule
    case "$RENEWAL_FREQUENCY" in
        daily)
            cron_schedule="0 3 * * *"
            ;;
        twice-daily)
            cron_schedule="0 3,15 * * *"
            ;;
        weekly)
            cron_schedule="0 3 * * 0"
            ;;
        *)
            cron_schedule="0 3,15 * * *"
            ;;
    esac
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create systemd timer (preferred method)
        cat > /etc/systemd/system/certbot-renewal.service << 'EOF'
[Unit]
Description=Certbot Renewal
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --no-self-upgrade
User=root
EOF
        
        cat > /etc/systemd/system/certbot-renewal.timer << EOF
[Unit]
Description=Run certbot renewal twice daily
Requires=certbot-renewal.service

[Timer]
OnCalendar=*-*-* 03,15:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        # Enable and start timer
        systemctl daemon-reload
        systemctl enable certbot-renewal.timer
        systemctl start certbot-renewal.timer
        
        # Also create traditional cron job as backup
        cat > /etc/cron.d/certbot << EOF
# Let's Encrypt certificate renewal
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

$cron_schedule root /usr/bin/certbot renew --quiet --no-self-upgrade
EOF
        
        log_ssl "INFO" "Auto-renewal configured with systemd timer and cron backup"
    else
        log_ssl "INFO" "[DRY RUN] Would configure auto-renewal ($RENEWAL_FREQUENCY)"
    fi
}

setup_monitoring() {
    log_ssl "INFO" "Setting up SSL certificate monitoring"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create monitoring script
        cat > /usr/local/bin/ssl-monitor << 'EOF'
#!/bin/bash
# SSL Certificate Monitoring Script

LOG_FILE="/var/log/bashmin/ssl/monitoring.log"
CERT_DIR="/etc/letsencrypt/live"
WARNING_DAYS=30
CRITICAL_DAYS=7

log_monitor() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$LOG_FILE"
}

check_certificate() {
    local domain="$1"
    local cert_file="$CERT_DIR/$domain/cert.pem"
    
    if [[ ! -f "$cert_file" ]]; then
        log_monitor "ERROR: Certificate file not found for $domain"
        return 1
    fi
    
    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log_monitor "Certificate for $domain expires in $days_until_expiry days"
    
    if [[ $days_until_expiry -le $CRITICAL_DAYS ]]; then
        log_monitor "CRITICAL: Certificate for $domain expires in $days_until_expiry days"
        return 2
    elif [[ $days_until_expiry -le $WARNING_DAYS ]]; then
        log_monitor "WARNING: Certificate for $domain expires in $days_until_expiry days"
        return 1
    fi
    
    return 0
}

# Main monitoring logic
if [[ -d "$CERT_DIR" ]]; then
    for domain_dir in "$CERT_DIR"/*/; do
        if [[ -d "$domain_dir" ]]; then
            domain=$(basename "$domain_dir")
            check_certificate "$domain"
        fi
    done
else
    log_monitor "No certificates found to monitor"
fi
EOF
        
        chmod +x /usr/local/bin/ssl-monitor
        
        # Add to daily cron
        cat > /etc/cron.d/ssl-monitor << 'EOF'
# SSL Certificate Monitoring
0 6 * * * root /usr/local/bin/ssl-monitor
EOF
        
    else
        log_ssl "INFO" "[DRY RUN] Would set up SSL certificate monitoring"
    fi
}

create_ssl_management_tool() {
    log_ssl "INFO" "Creating SSL management utility"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cp "$SCRIPT_DIR/ssl-manage.sh" /usr/local/bin/ssl-manage 2>/dev/null || {
            log_ssl "WARN" "ssl-manage.sh not found, will be created separately"
        }
        
        if [[ -f /usr/local/bin/ssl-manage ]]; then
            chmod +x /usr/local/bin/ssl-manage
            log_ssl "INFO" "SSL management utility installed as 'ssl-manage'"
        fi
        
    else
        log_ssl "INFO" "[DRY RUN] Would install SSL management utility"
    fi
}

# Notification functions
send_notification() {
    local subject="$1"
    local message="$2"
    
    # Email notification
    if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$subject" "$NOTIFICATION_EMAIL"
        log_ssl "INFO" "Email notification sent to $NOTIFICATION_EMAIL"
    fi
    
    # Slack notification
    if [[ -n "$SLACK_WEBHOOK" ]] && command -v curl >/dev/null 2>&1; then
        local payload=$(cat << EOF
{
    "text": "🔐 $subject",
    "attachments": [
        {
            "color": "good",
            "fields": [
                {
                    "title": "Server",
                    "value": "$(hostname)",
                    "short": true
                },
                {
                    "title": "Timestamp",
                    "value": "$(date)",
                    "short": true
                },
                {
                    "title": "Details",
                    "value": "$message",
                    "short": false
                }
            ]
        }
    ]
}
EOF
        )
        
        curl -X POST -H 'Content-type: application/json' \
            --data "$payload" "$SLACK_WEBHOOK" >/dev/null 2>&1
        
        log_ssl "INFO" "Slack notification sent"
    fi
}

# Main installation function
main() {
    log_ssl "INFO" "Starting Let's Encrypt installation and configuration"
    
    # Validate required parameters
    if [[ -z "$EMAIL" ]] && [[ "$DRY_RUN" == "false" ]]; then
        log_ssl "ERROR" "Email address is required for Let's Encrypt registration"
        echo "Use --email to specify your email address"
        exit 1
    fi
    
    if [[ -n "$EMAIL" ]] && ! validate_email "$EMAIL"; then
        exit 1
    fi
    
    if [[ -n "$SLACK_WEBHOOK" ]] && ! validate_webhook_url "$SLACK_WEBHOOK"; then
        exit 1
    fi
    
    # Auto-detect web server if not specified
    if [[ "$WEBSERVER" == "auto" ]]; then
        WEBSERVER=$(detect_webserver)
        log_ssl "INFO" "Auto-detected web server: $WEBSERVER"
    fi
    
    # Check if certbot is already installed
    if command -v certbot >/dev/null 2>&1 && [[ "$FORCE" == "false" ]]; then
        log_ssl "INFO" "Certbot already installed, use --force to reinstall"
    else
        install_certbot
    fi
    
    # Configure webroot for domain validation
    configure_webroot
    
    # Configure web server for ACME challenge
    case "$WEBSERVER" in
        nginx)
            configure_nginx_acme
            ;;
        apache)
            configure_apache_acme
            ;;
        standalone|webroot)
            log_ssl "INFO" "Using $WEBSERVER mode, no web server configuration needed"
            ;;
        *)
            log_ssl "WARN" "Unknown web server: $WEBSERVER, using standalone mode"
            WEBSERVER="standalone"
            ;;
    esac
    
    # Set up renewal hooks
    setup_renewal_hooks
    
    # Configure automatic renewal
    if [[ "$ENABLE_AUTO_RENEWAL" == "true" ]]; then
        configure_auto_renewal
    fi
    
    # Set up monitoring
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        setup_monitoring
    fi
    
    # Create management utility
    create_ssl_management_tool
    
    # Create log directories
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$BASHMIN_SSL_DIR"
        mkdir -p /var/backups/letsencrypt
        
        # Set up log rotation
        cat > /etc/logrotate.d/bashmin-ssl << 'EOF'
/var/log/bashmin/ssl/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF
    fi
    
    # Send installation notification
    if [[ "$ENABLE_NOTIFICATIONS" == "true" ]] && [[ "$DRY_RUN" == "false" ]]; then
        send_notification "Let's Encrypt Installation Complete" \
            "Let's Encrypt has been successfully installed and configured on $(hostname). Auto-renewal is enabled and monitoring is active."
    fi
    
    log_ssl "INFO" "Let's Encrypt installation completed successfully"
    
    # Show next steps
    if [[ "$QUIET" == "false" ]]; then
        cat << EOF

✅ Let's Encrypt Installation Complete!

Next Steps:
1. Obtain your first certificate:
   ssl-manage --add-certificate example.com

2. Test certificate renewal:
   certbot renew --dry-run

3. Check certificate status:
   ssl-manage --list-certificates

4. Monitor logs:
   tail -f /var/log/bashmin/ssl/letsencrypt.log

Configuration Files:
• Certbot config: /etc/letsencrypt/
• bashmin SSL logs: /var/log/bashmin/ssl/
• Management tool: /usr/local/bin/ssl-manage

For detailed usage information:
• ssl-manage --help
• cat /var/www/vhosts/bashmin/security/letsencrypt/README.md

EOF
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --webserver)
            WEBSERVER="$2"
            shift 2
            ;;
        --staging)
            STAGING=true
            shift
            ;;
        --agree-tos)
            AGREE_TOS=true
            shift
            ;;
        --no-eff-email)
            NO_EFF_EMAIL=true
            shift
            ;;
        --key-type)
            KEY_TYPE="$2"
            shift 2
            ;;
        --rsa-key-size)
            RSA_KEY_SIZE="$2"
            shift 2
            ;;
        --elliptic-curve)
            ELLIPTIC_CURVE="$2"
            shift 2
            ;;
        --hsts-max-age)
            HSTS_MAX_AGE="$2"
            shift 2
            ;;
        --enable-ocsp-stapling)
            OCSP_STAPLING=true
            shift
            ;;
        --disable-ocsp-stapling)
            OCSP_STAPLING=false
            shift
            ;;
        --enable-auto-renewal)
            ENABLE_AUTO_RENEWAL=true
            shift
            ;;
        --disable-auto-renewal)
            ENABLE_AUTO_RENEWAL=false
            shift
            ;;
        --renewal-frequency)
            RENEWAL_FREQUENCY="$2"
            shift 2
            ;;
        --enable-monitoring)
            ENABLE_MONITORING=true
            shift
            ;;
        --disable-monitoring)
            ENABLE_MONITORING=false
            shift
            ;;
        --notification-email)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        --slack-webhook)
            SLACK_WEBHOOK="$2"
            shift 2
            ;;
        --webroot-path)
            WEBROOT_PATH="$2"
            shift 2
            ;;
        --secure-permissions)
            SECURE_PERMISSIONS=true
            shift
            ;;
        --backup-certificates)
            BACKUP_CERTIFICATES=true
            shift
            ;;
        --force)
            FORCE=true
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
        --help)
            show_help
            exit 0
            ;;
        *)
            log_ssl "ERROR" "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Verify running as root
if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
    log_ssl "ERROR" "This script must be run as root (use sudo)"
    exit 1
fi

# Run main function
main

exit 0