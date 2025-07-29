#!/bin/bash
#
# Script: security/letsencrypt/ssl-manage.sh
# Description: SSL/TLS Certificate Management Utility
# Usage: ./ssl-manage.sh [OPTIONS] [COMMAND]
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
readonly CERTBOT_LIVE_DIR="$CERTBOT_CONFIG_DIR/live"
readonly BASHMIN_SSL_DIR="/var/log/bashmin/ssl"
readonly NGINX_SITES_DIR="/etc/nginx/sites-available"
readonly APACHE_SITES_DIR="/etc/apache2/sites-available"
readonly BACKUP_DIR="/var/backups/letsencrypt"

# Configuration variables
DOMAIN=""
EMAIL=""
WEBSERVER="auto"
STAGING=false
FORCE_RENEWAL=false
SKIP_VALIDATION=false
EXPAND_CERTIFICATE=false
STANDALONE_PORT=80
WEBROOT_PATH="/var/www/certbot"
KEY_TYPE="rsa"
RSA_KEY_SIZE=4096
MUST_STAPLE=false
HSTS_PRELOAD=false
REDIRECT_HTTP=true
ENABLE_OCSP=true
DRY_RUN=false
VERBOSE=false
QUIET=false
FORCE=false

# Help function
show_help() {
    cat << 'EOF'
SSL/TLS Certificate Management Utility

DESCRIPTION:
    Comprehensive SSL/TLS certificate management for Let's Encrypt certificates.
    Handles certificate creation, renewal, revocation, and web server integration.

USAGE:
    ssl-manage [OPTIONS] COMMAND [DOMAIN]

COMMANDS:
    Certificate Management:
    --add-certificate DOMAIN       Request new SSL certificate for domain
    --renew-certificate DOMAIN     Force renewal of specific certificate
    --revoke-certificate DOMAIN    Revoke and delete certificate
    --expand-certificate DOMAIN    Add domains to existing certificate
    --list-certificates            List all managed certificates
    --check-certificate DOMAIN     Check certificate status and expiry
    
    Testing & Validation:
    --test-renewal DOMAIN          Test certificate renewal (dry run)
    --validate-certificate DOMAIN  Validate certificate installation
    --test-configuration          Test web server SSL configuration
    
    Management Operations:
    --backup-certificates          Backup all certificates
    --restore-certificates DATE    Restore certificates from backup
    --update-renewals              Update auto-renewal configuration
    --cleanup-expired              Remove expired certificates
    
    Information & Status:
    --certificate-info DOMAIN      Show detailed certificate information
    --show-configuration           Display current SSL configuration
    --check-expiry                 Check all certificate expiry dates
    --show-logs                    Display recent SSL management logs

OPTIONS:
    Certificate Configuration:
    --email EMAIL                  Email for Let's Encrypt registration
    --webserver TYPE               Web server: nginx, apache, standalone [auto]
    --staging                      Use Let's Encrypt staging environment
    --key-type TYPE                Key type: rsa, ecdsa [rsa]
    --rsa-key-size SIZE            RSA key size [4096]
    --must-staple                  Enable OCSP Must-Staple
    --webroot-path PATH            Custom webroot path [/var/www/certbot]
    --standalone-port PORT         Standalone mode port [80]
    
    Web Server Integration:
    --redirect-http                Enable HTTP to HTTPS redirect [default]
    --no-redirect                  Disable HTTP to HTTPS redirect
    --enable-hsts                  Enable HTTP Strict Transport Security
    --hsts-preload                 Enable HSTS preload
    --enable-ocsp                  Enable OCSP stapling [default]
    --disable-ocsp                 Disable OCSP stapling
    
    Domain Management:
    --expand                       Add domain to existing certificate
    --domains "domain1,domain2"    Multiple domains for certificate
    --wildcard                     Request wildcard certificate (requires DNS validation)
    
    Control Options:
    --force                        Force certificate operations
    --skip-validation              Skip domain validation checks
    --dry-run                      Show what would be done
    --verbose                      Enable verbose output
    --quiet                        Suppress non-essential output
    --help                         Show this help message

EXAMPLES:
    Request New Certificate:
    ssl-manage --add-certificate example.com --email admin@example.com

    Multi-Domain Certificate:
    ssl-manage --add-certificate example.com \\
        --domains "example.com,www.example.com,api.example.com"

    Wildcard Certificate:
    ssl-manage --add-certificate example.com --wildcard \\
        --email admin@example.com

    Force Certificate Renewal:
    ssl-manage --renew-certificate example.com --force

    Test Renewal:
    ssl-manage --test-renewal example.com --staging

    Check Certificate Status:
    ssl-manage --check-certificate example.com

    List All Certificates:
    ssl-manage --list-certificates

    Backup Certificates:
    ssl-manage --backup-certificates

    Nginx Integration:
    ssl-manage --add-certificate example.com --webserver nginx \\
        --redirect-http --enable-hsts

    Apache Integration:
    ssl-manage --add-certificate example.com --webserver apache \\
        --enable-ocsp --hsts-preload

    Standalone Mode:
    ssl-manage --add-certificate example.com --webserver standalone \\
        --standalone-port 8080

SECURITY FEATURES:
    • Automatic web server configuration with security headers
    • OCSP stapling for improved performance
    • HSTS (HTTP Strict Transport Security) support
    • Secure cipher suite configuration
    • Certificate backup and recovery
    • Comprehensive validation and testing

INTEGRATION:
    • Nginx: Automatic virtual host SSL configuration
    • Apache: SSL virtual host with security headers
    • Standalone: Independent certificate management
    • Monitoring: Integration with certificate expiry monitoring

FILES:
    Configuration: /etc/letsencrypt/
    Certificates: /etc/letsencrypt/live/
    Logs: /var/log/bashmin/ssl/
    Backups: /var/backups/letsencrypt/

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
    echo "[$timestamp] [$level] ssl-manage: $message" >> "$BASHMIN_SSL_DIR/ssl-manage.log"
    
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

# Utility functions
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

validate_domain() {
    local domain="$1"
    
    # Basic domain format validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_ssl "ERROR" "Invalid domain format: $domain"
        return 1
    fi
    
    # Check if domain resolves (unless skip validation)
    if [[ "$SKIP_VALIDATION" == "false" ]]; then
        if ! nslookup "$domain" >/dev/null 2>&1; then
            log_ssl "WARN" "Domain $domain does not resolve to an IP address"
            if [[ "$FORCE" == "false" ]]; then
                log_ssl "ERROR" "Use --force to proceed anyway or --skip-validation"
                return 1
            fi
        fi
    fi
    
    return 0
}

certificate_exists() {
    local domain="$1"
    [[ -d "$CERTBOT_LIVE_DIR/$domain" ]]
}

get_certificate_expiry() {
    local domain="$1"
    local cert_file="$CERTBOT_LIVE_DIR/$domain/cert.pem"
    
    if [[ -f "$cert_file" ]]; then
        openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2
    else
        echo "Certificate not found"
    fi
}

days_until_expiry() {
    local domain="$1"
    local expiry_date=$(get_certificate_expiry "$domain")
    
    if [[ "$expiry_date" != "Certificate not found" ]]; then
        local expiry_epoch=$(date -d "$expiry_date" +%s)
        local current_epoch=$(date +%s)
        local days=$(( (expiry_epoch - current_epoch) / 86400 ))
        echo "$days"
    else
        echo "-1"
    fi
}

# Certificate management functions
add_certificate() {
    local domain="$1"
    
    log_ssl "INFO" "Requesting SSL certificate for domain: $domain"
    
    # Validate domain
    if ! validate_domain "$domain"; then
        return 1
    fi
    
    # Check if certificate already exists
    if certificate_exists "$domain" && [[ "$FORCE" == "false" ]]; then
        log_ssl "ERROR" "Certificate already exists for $domain (use --force to overwrite)"
        return 1
    fi
    
    # Auto-detect web server if needed
    if [[ "$WEBSERVER" == "auto" ]]; then
        WEBSERVER=$(detect_webserver)
    fi
    
    # Build certbot command
    local certbot_cmd="certbot certonly"
    
    # Add staging if requested
    if [[ "$STAGING" == "true" ]]; then
        certbot_cmd+=" --staging"
    fi
    
    # Add email if provided
    if [[ -n "$EMAIL" ]]; then
        certbot_cmd+=" --email $EMAIL --agree-tos --no-eff-email"
    fi
    
    # Configure authentication method
    case "$WEBSERVER" in
        nginx)
            certbot_cmd+=" --nginx"
            ;;
        apache)
            certbot_cmd+=" --apache"
            ;;
        standalone)
            certbot_cmd+=" --standalone"
            if [[ "$STANDALONE_PORT" != "80" ]]; then
                certbot_cmd+=" --http-01-port $STANDALONE_PORT"
            fi
            ;;
        webroot)
            certbot_cmd+=" --webroot --webroot-path $WEBROOT_PATH"
            ;;
        *)
            log_ssl "ERROR" "Unsupported web server: $WEBSERVER"
            return 1
            ;;
    esac
    
    # Add domain
    certbot_cmd+=" -d $domain"
    
    # Add additional domains if specified
    if [[ -n "${DOMAINS:-}" ]]; then
        IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
        for d in "${DOMAIN_ARRAY[@]}"; do
            d=$(echo "$d" | xargs)  # trim whitespace
            if [[ "$d" != "$domain" ]]; then
                certbot_cmd+=" -d $d"
            fi
        done
    fi
    
    # Add key type options
    if [[ "$KEY_TYPE" == "ecdsa" ]]; then
        certbot_cmd+=" --key-type ecdsa --elliptic-curve secp384r1"
    else
        certbot_cmd+=" --key-type rsa --rsa-key-size $RSA_KEY_SIZE"
    fi
    
    # Add OCSP Must-Staple if requested
    if [[ "$MUST_STAPLE" == "true" ]]; then
        certbot_cmd+=" --must-staple"
    fi
    
    # Execute certbot command
    if [[ "$DRY_RUN" == "true" ]]; then
        log_ssl "INFO" "[DRY RUN] Would execute: $certbot_cmd"
        return 0
    fi
    
    log_ssl "DEBUG" "Executing: $certbot_cmd"
    
    if eval "$certbot_cmd"; then
        log_ssl "INFO" "Certificate successfully obtained for $domain"
        
        # Configure web server if needed
        case "$WEBSERVER" in
            nginx)
                configure_nginx_ssl "$domain"
                ;;
            apache)
                configure_apache_ssl "$domain"
                ;;
        esac
        
        return 0
    else
        log_ssl "ERROR" "Failed to obtain certificate for $domain"
        return 1
    fi
}

renew_certificate() {
    local domain="$1"
    
    log_ssl "INFO" "Renewing SSL certificate for domain: $domain"
    
    if ! certificate_exists "$domain"; then
        log_ssl "ERROR" "Certificate does not exist for $domain"
        return 1
    fi
    
    local certbot_cmd="certbot renew"
    
    if [[ -n "$domain" ]]; then
        certbot_cmd+=" --cert-name $domain"
    fi
    
    if [[ "$FORCE_RENEWAL" == "true" ]]; then
        certbot_cmd+=" --force-renewal"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        certbot_cmd+=" --dry-run"
        log_ssl "INFO" "[DRY RUN] Testing certificate renewal"
    fi
    
    log_ssl "DEBUG" "Executing: $certbot_cmd"
    
    if eval "$certbot_cmd"; then
        if [[ "$DRY_RUN" == "false" ]]; then
            log_ssl "INFO" "Certificate successfully renewed for $domain"
        else
            log_ssl "INFO" "Certificate renewal test successful for $domain"
        fi
        return 0
    else
        log_ssl "ERROR" "Failed to renew certificate for $domain"
        return 1
    fi
}

revoke_certificate() {
    local domain="$1"
    
    log_ssl "INFO" "Revoking SSL certificate for domain: $domain"
    
    if ! certificate_exists "$domain"; then
        log_ssl "ERROR" "Certificate does not exist for $domain"
        return 1
    fi
    
    local cert_path="$CERTBOT_LIVE_DIR/$domain/cert.pem"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_ssl "INFO" "[DRY RUN] Would revoke certificate: $cert_path"
        return 0
    fi
    
    # Revoke certificate
    if certbot revoke --cert-path "$cert_path"; then
        log_ssl "INFO" "Certificate revoked for $domain"
        
        # Delete certificate files
        if certbot delete --cert-name "$domain"; then
            log_ssl "INFO" "Certificate files deleted for $domain"
        fi
        
        return 0
    else
        log_ssl "ERROR" "Failed to revoke certificate for $domain"
        return 1
    fi
}

list_certificates() {
    log_ssl "INFO" "Listing all managed certificates"
    
    if [[ ! -d "$CERTBOT_LIVE_DIR" ]]; then
        log_ssl "INFO" "No certificates found"
        return 0
    fi
    
    printf "%-30s %-15s %-25s %-10s\n" "DOMAIN" "STATUS" "EXPIRES" "DAYS LEFT"
    printf "%s\n" "$(printf '=%.0s' {1..80})"
    
    for cert_dir in "$CERTBOT_LIVE_DIR"/*/; do
        if [[ -d "$cert_dir" ]]; then
            local domain=$(basename "$cert_dir")
            local cert_file="$cert_dir/cert.pem"
            
            if [[ -f "$cert_file" ]]; then
                local expiry_date=$(get_certificate_expiry "$domain")
                local days_left=$(days_until_expiry "$domain")
                local status="Valid"
                
                if [[ $days_left -lt 0 ]]; then
                    status="Expired"
                elif [[ $days_left -lt 7 ]]; then
                    status="Critical"
                elif [[ $days_left -lt 30 ]]; then
                    status="Warning"
                fi
                
                printf "%-30s %-15s %-25s %-10s\n" \
                    "$domain" "$status" "$expiry_date" "$days_left"
            fi
        fi
    done
}

check_certificate() {
    local domain="$1"
    
    log_ssl "INFO" "Checking certificate status for domain: $domain"
    
    if ! certificate_exists "$domain"; then
        log_ssl "ERROR" "Certificate does not exist for $domain"
        return 1
    fi
    
    local cert_file="$CERTBOT_LIVE_DIR/$domain/cert.pem"
    local key_file="$CERTBOT_LIVE_DIR/$domain/privkey.pem"
    local chain_file="$CERTBOT_LIVE_DIR/$domain/chain.pem"
    local fullchain_file="$CERTBOT_LIVE_DIR/$domain/fullchain.pem"
    
    echo "Certificate Information for: $domain"
    echo "=================================="
    
    # Basic certificate info
    if [[ -f "$cert_file" ]]; then
        echo "Certificate File: $cert_file"
        echo "Subject: $(openssl x509 -subject -noout -in "$cert_file" | cut -d= -f2-)"
        echo "Issuer: $(openssl x509 -issuer -noout -in "$cert_file" | cut -d= -f2-)"
        echo "Serial: $(openssl x509 -serial -noout -in "$cert_file" | cut -d= -f2)"
        echo "Not Before: $(openssl x509 -startdate -noout -in "$cert_file" | cut -d= -f2)"
        echo "Not After: $(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)"
        
        local days_left=$(days_until_expiry "$domain")
        echo "Days Until Expiry: $days_left"
        
        # SANs
        local sans=$(openssl x509 -text -noout -in "$cert_file" | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/DNS://g')
        echo "Subject Alternative Names: $sans"
        
        # Key info
        local key_size=$(openssl x509 -text -noout -in "$cert_file" | grep "Public Key" | sed 's/.*(\([0-9]*\) bit).*/\1/')
        echo "Key Size: $key_size bits"
        
        # OCSP Must-Staple
        if openssl x509 -text -noout -in "$cert_file" | grep -q "OCSP Must-Staple"; then
            echo "OCSP Must-Staple: Yes"
        else
            echo "OCSP Must-Staple: No"
        fi
    fi
    
    # File permissions
    echo ""
    echo "File Status:"
    echo "Certificate: $(test -f "$cert_file" && echo "✓ Present" || echo "✗ Missing")"
    echo "Private Key: $(test -f "$key_file" && echo "✓ Present" || echo "✗ Missing")"
    echo "Chain: $(test -f "$chain_file" && echo "✓ Present" || echo "✗ Missing")"
    echo "Full Chain: $(test -f "$fullchain_file" && echo "✓ Present" || echo "✗ Missing")"
    
    # Test certificate validity
    echo ""
    echo "Validation:"
    if openssl x509 -checkend 86400 -noout -in "$cert_file" >/dev/null 2>&1; then
        echo "Certificate Validity: ✓ Valid for next 24 hours"
    else
        echo "Certificate Validity: ✗ Expires within 24 hours"
    fi
    
    # Check key-cert match
    local cert_hash=$(openssl x509 -noout -modulus -in "$cert_file" | openssl md5)
    local key_hash=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5)
    
    if [[ "$cert_hash" == "$key_hash" ]]; then
        echo "Key-Certificate Match: ✓ Valid"
    else
        echo "Key-Certificate Match: ✗ Mismatch"
    fi
}

configure_nginx_ssl() {
    local domain="$1"
    
    log_ssl "INFO" "Configuring Nginx SSL for domain: $domain"
    
    local nginx_conf="$NGINX_SITES_DIR/$domain-ssl.conf"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_ssl "INFO" "[DRY RUN] Would create Nginx SSL configuration: $nginx_conf"
        return 0
    fi
    
    cat > "$nginx_conf" << EOF
# SSL configuration for $domain
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    # SSL Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/$domain/chain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Document root
    root /var/www/vhosts/$domain;
    index index.html index.htm index.php;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # PHP configuration (if needed)
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }
}

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    
    # ACME challenge
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files \$uri =404;
    }
    
    # Redirect to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF
    
    # Test nginx configuration
    if nginx -t; then
        # Enable site
        ln -sf "$nginx_conf" /etc/nginx/sites-enabled/
        systemctl reload nginx
        log_ssl "INFO" "Nginx SSL configuration created and enabled for $domain"
    else
        log_ssl "ERROR" "Nginx configuration test failed"
        return 1
    fi
}

configure_apache_ssl() {
    local domain="$1"
    
    log_ssl "INFO" "Configuring Apache SSL for domain: $domain"
    
    local apache_conf="$APACHE_SITES_DIR/$domain-ssl.conf"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_ssl "INFO" "[DRY RUN] Would create Apache SSL configuration: $apache_conf"
        return 0
    fi
    
    cat > "$apache_conf" << EOF
# SSL Virtual Host for $domain
<VirtualHost *:443>
    ServerName $domain
    DocumentRoot /var/www/vhosts/$domain
    
    # SSL Configuration
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$domain/cert.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$domain/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/$domain/chain.pem
    
    # SSL Security
    SSLProtocol All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    SSLHonorCipherOrder on
    SSLCompression off
    SSLSessionTickets off
    
    # OCSP Stapling
    SSLUseStapling on
    SSLStaplingResponderTimeout 5
    SSLStaplingReturnResponderErrors off
    
    # Security Headers
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set X-XSS-Protection "1; mode=block"
    
    # Logging
    ErrorLog \${APACHE_LOG_DIR}/$domain-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$domain-ssl-access.log combined
    
    <Directory /var/www/vhosts/$domain>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

# HTTP to HTTPS redirect
<VirtualHost *:80>
    ServerName $domain
    DocumentRoot /var/www/vhosts/$domain
    
    # ACME challenge
    Alias /.well-known/acme-challenge/ /var/www/certbot/.well-known/acme-challenge/
    <Directory "/var/www/certbot/.well-known/acme-challenge/">
        Options None
        AllowOverride None
        Require all granted
    </Directory>
    
    # Redirect to HTTPS
    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>
EOF
    
    # Test apache configuration
    if apache2ctl configtest; then
        # Enable site and required modules
        a2enmod ssl headers rewrite
        a2ensite "$domain-ssl.conf"
        systemctl reload apache2
        log_ssl "INFO" "Apache SSL configuration created and enabled for $domain"
    else
        log_ssl "ERROR" "Apache configuration test failed"
        return 1
    fi
}

backup_certificates() {
    log_ssl "INFO" "Backing up SSL certificates"
    
    local backup_date=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/$backup_date"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_ssl "INFO" "[DRY RUN] Would backup certificates to: $backup_path"
        return 0
    fi
    
    mkdir -p "$backup_path"
    
    if [[ -d "$CERTBOT_CONFIG_DIR" ]]; then
        cp -r "$CERTBOT_CONFIG_DIR" "$backup_path/"
        log_ssl "INFO" "Certificates backed up to: $backup_path"
        
        # Create backup manifest
        cat > "$backup_path/manifest.txt" << EOF
Backup Date: $(date)
Server: $(hostname)
Certbot Version: $(certbot --version 2>&1)
Certificates Backed Up:
$(find "$CERTBOT_LIVE_DIR" -name "cert.pem" -exec dirname {} \; 2>/dev/null | sed 's|.*/||' | sort)
EOF
        
        # Compress backup
        tar -czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "$backup_date"
        rm -rf "$backup_path"
        
        log_ssl "INFO" "Compressed backup created: $backup_path.tar.gz"
    else
        log_ssl "WARN" "No certificates found to backup"
    fi
}

# Command parsing and execution
main() {
    # Auto-detect web server if not specified
    if [[ "$WEBSERVER" == "auto" ]]; then
        WEBSERVER=$(detect_webserver)
    fi
    
    # Execute based on command
    case "${COMMAND:-}" in
        add-certificate)
            if [[ -z "$DOMAIN" ]]; then
                log_ssl "ERROR" "Domain is required for certificate addition"
                exit 1
            fi
            add_certificate "$DOMAIN"
            ;;
        renew-certificate)
            if [[ -z "$DOMAIN" ]]; then
                log_ssl "ERROR" "Domain is required for certificate renewal"
                exit 1
            fi
            renew_certificate "$DOMAIN"
            ;;
        revoke-certificate)
            if [[ -z "$DOMAIN" ]]; then
                log_ssl "ERROR" "Domain is required for certificate revocation"
                exit 1
            fi
            revoke_certificate "$DOMAIN"
            ;;
        list-certificates)
            list_certificates
            ;;
        check-certificate)
            if [[ -z "$DOMAIN" ]]; then
                log_ssl "ERROR" "Domain is required for certificate check"
                exit 1
            fi
            check_certificate "$DOMAIN"
            ;;
        test-renewal)
            if [[ -z "$DOMAIN" ]]; then
                log_ssl "ERROR" "Domain is required for renewal test"
                exit 1
            fi
            DRY_RUN=true
            renew_certificate "$DOMAIN"
            ;;
        backup-certificates)
            backup_certificates
            ;;
        *)
            log_ssl "ERROR" "Unknown command: ${COMMAND:-}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# Parse command line arguments
COMMAND=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --add-certificate)
            COMMAND="add-certificate"
            DOMAIN="$2"
            shift 2
            ;;
        --renew-certificate)
            COMMAND="renew-certificate"
            DOMAIN="$2"
            shift 2
            ;;
        --revoke-certificate)
            COMMAND="revoke-certificate"
            DOMAIN="$2"
            shift 2
            ;;
        --expand-certificate)
            COMMAND="expand-certificate"
            DOMAIN="$2"
            EXPAND_CERTIFICATE=true
            shift 2
            ;;
        --list-certificates)
            COMMAND="list-certificates"
            shift
            ;;
        --check-certificate)
            COMMAND="check-certificate"
            DOMAIN="$2"
            shift 2
            ;;
        --test-renewal)
            COMMAND="test-renewal"
            DOMAIN="$2"
            shift 2
            ;;
        --backup-certificates)
            COMMAND="backup-certificates"
            shift
            ;;
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
        --key-type)
            KEY_TYPE="$2"
            shift 2
            ;;
        --rsa-key-size)
            RSA_KEY_SIZE="$2"
            shift 2
            ;;
        --must-staple)
            MUST_STAPLE=true
            shift
            ;;
        --webroot-path)
            WEBROOT_PATH="$2"
            shift 2
            ;;
        --standalone-port)
            STANDALONE_PORT="$2"
            shift 2
            ;;
        --domains)
            DOMAINS="$2"
            shift 2
            ;;
        --expand)
            EXPAND_CERTIFICATE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
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
            # If no command specified yet, treat as domain for backwards compatibility
            if [[ -z "$COMMAND" ]] && [[ -z "$DOMAIN" ]]; then
                DOMAIN="$1"
                COMMAND="add-certificate"
            else
                log_ssl "ERROR" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Verify running as root for certificate operations
if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == "false" ]] && [[ "$COMMAND" != "list-certificates" ]] && [[ "$COMMAND" != "check-certificate" ]]; then
    log_ssl "ERROR" "This script must be run as root (use sudo)"
    exit 1
fi

# Execute main function
main

exit 0
