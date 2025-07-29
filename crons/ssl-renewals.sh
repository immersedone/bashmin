#!/bin/bash

#########################################################
#
#    File: /crons/ssl-renewals.sh
#    Author: bashmin SSL Management System
#    Last Modified: $(date '+%d/%m/%Y')
#    Description:
#
#    This file contains the BASH Script commands
#    for automated SSL certificate management and renewal.
#    Integrated with Let's Encrypt and bashmin logging.
#
#    Invoking User: `root`
#    Cron Timing: `twice-daily` (03:00 and 15:00)
#
#########################################################

set -euo pipefail

# Constants
readonly SCRIPT_NAME="ssl-renewals"
readonly LOG_DIR="/var/log/bashmin/ssl"
readonly CERT_DIR="/etc/letsencrypt/live"
readonly BACKUP_DIR="/var/backups/letsencrypt"
readonly NOTIFICATION_SCRIPT="/usr/local/bin/ssl-notify"
readonly CERTBOT_LOG="/var/log/letsencrypt/letsencrypt.log"

# Configuration
NOTIFICATION_EMAIL="${SSL_NOTIFICATION_EMAIL:-}"
SLACK_WEBHOOK="${SSL_SLACK_WEBHOOK:-}"
BACKUP_RETENTION_DAYS=30
WARNING_DAYS=30
CRITICAL_DAYS=7
ENABLE_NOTIFICATIONS=true
VERBOSE=${SSL_CRON_VERBOSE:-false}

# Logging functions
log_renewal() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure log directory exists
    mkdir -p "$LOG_DIR"
    
    # Log to renewal log
    echo "[$timestamp] [$level] $SCRIPT_NAME: $message" >> "$LOG_DIR/renewals.log"
    
    # Also log to syslog for system monitoring
    logger -t "$SCRIPT_NAME" -p daemon."${level,,}" "$message"
    
    # Verbose output to console
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$timestamp] [$level] $message"
    fi
}

# Notification functions
send_notification() {
    local subject="$1"
    local message="$2"
    local level="${3:-INFO}"
    
    log_renewal "$level" "Sending notification: $subject"
    
    # Email notification
    if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        {
            echo "SSL Certificate Notification"
            echo "=========================="
            echo ""
            echo "Server: $(hostname)"
            echo "Date: $(date)"
            echo "Level: $level"
            echo ""
            echo "$message"
            echo ""
            echo "---"
            echo "bashmin SSL Management System"
        } | mail -s "$subject - $(hostname)" "$NOTIFICATION_EMAIL"
        
        log_renewal "DEBUG" "Email notification sent to $NOTIFICATION_EMAIL"
    fi
    
    # Slack notification
    if [[ -n "$SLACK_WEBHOOK" ]] && command -v curl >/dev/null 2>&1; then
        local color="good"
        local emoji="🔐"
        
        case "$level" in
            ERROR|CRITICAL)
                color="danger"
                emoji="🚨"
                ;;
            WARN|WARNING)
                color="warning"
                emoji="⚠️"
                ;;
            INFO)
                color="good"
                emoji="✅"
                ;;
        esac
        
        local payload=$(cat << EOF
{
    "text": "$emoji $subject",
    "attachments": [
        {
            "color": "$color",
            "fields": [
                {
                    "title": "Server",
                    "value": "$(hostname)",
                    "short": true
                },
                {
                    "title": "Level",
                    "value": "$level",
                    "short": true
                },
                {
                    "title": "Timestamp",
                    "value": "$(date)",
                    "short": false
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
        
        if curl -X POST -H 'Content-type: application/json' \
            --data "$payload" "$SLACK_WEBHOOK" >/dev/null 2>&1; then
            log_renewal "DEBUG" "Slack notification sent successfully"
        else
            log_renewal "WARN" "Failed to send Slack notification"
        fi
    fi
}

# Certificate management functions
check_certificate_expiry() {
    local domain="$1"
    local cert_file="$CERT_DIR/$domain/cert.pem"
    
    if [[ ! -f "$cert_file" ]]; then
        log_renewal "ERROR" "Certificate file not found for $domain: $cert_file"
        return 1
    fi
    
    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log_renewal "DEBUG" "Certificate for $domain expires in $days_until_expiry days"
    
    if [[ $days_until_expiry -le $CRITICAL_DAYS ]]; then
        log_renewal "CRITICAL" "Certificate for $domain expires in $days_until_expiry days (CRITICAL)"
        if [[ "$ENABLE_NOTIFICATIONS" == "true" ]]; then
            send_notification "CRITICAL: SSL Certificate Expiring Soon" \
                "Certificate for $domain expires in $days_until_expiry days. Immediate attention required." \
                "CRITICAL"
        fi
        return 2
    elif [[ $days_until_expiry -le $WARNING_DAYS ]]; then
        log_renewal "WARN" "Certificate for $domain expires in $days_until_expiry days (WARNING)"
        if [[ "$ENABLE_NOTIFICATIONS" == "true" ]]; then
            send_notification "WARNING: SSL Certificate Expiring" \
                "Certificate for $domain expires in $days_until_expiry days. Please review renewal status." \
                "WARN"
        fi
        return 1
    fi
    
    log_renewal "INFO" "Certificate for $domain is valid for $days_until_expiry days"
    return 0
}

backup_certificates() {
    log_renewal "INFO" "Creating certificate backup"
    
    local backup_date=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/auto_$backup_date"
    
    if [[ ! -d "/etc/letsencrypt" ]]; then
        log_renewal "WARN" "No Let's Encrypt directory found, skipping backup"
        return 0
    fi
    
    mkdir -p "$backup_path"
    
    # Copy Let's Encrypt configuration and certificates
    cp -r /etc/letsencrypt "$backup_path/"
    
    # Create backup manifest
    cat > "$backup_path/manifest.txt" << EOF
Automatic SSL Backup
==================
Backup Date: $(date)
Server: $(hostname)
Certbot Version: $(certbot --version 2>&1 || echo "Not available")
Backup Type: Automatic (cron)

Certificates Included:
$(find "$CERT_DIR" -name "cert.pem" -exec dirname {} \; 2>/dev/null | sed 's|.*/||' | sort || echo "None found")

System Information:
OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo "Unknown")
Uptime: $(uptime)
EOF
    
    # Compress backup
    if tar -czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "auto_$backup_date" 2>/dev/null; then
        rm -rf "$backup_path"
        log_renewal "INFO" "Certificate backup created: $backup_path.tar.gz"
        
        # Get backup size
        local backup_size=$(du -h "$backup_path.tar.gz" | cut -f1)
        log_renewal "DEBUG" "Backup size: $backup_size"
    else
        log_renewal "ERROR" "Failed to create certificate backup"
        rm -rf "$backup_path"
        return 1
    fi
}

cleanup_old_backups() {
    log_renewal "INFO" "Cleaning up old certificate backups (older than $BACKUP_RETENTION_DAYS days)"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_renewal "DEBUG" "Backup directory doesn't exist, nothing to clean"
        return 0
    fi
    
    local deleted_count=0
    
    # Find and remove old backups
    while IFS= read -r -d '' backup_file; do
        rm -f "$backup_file"
        ((deleted_count++))
        log_renewal "DEBUG" "Deleted old backup: $(basename "$backup_file")"
    done < <(find "$BACKUP_DIR" -name "auto_*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -print0 2>/dev/null)
    
    if [[ $deleted_count -gt 0 ]]; then
        log_renewal "INFO" "Cleaned up $deleted_count old backup(s)"
    else
        log_renewal "DEBUG" "No old backups to clean up"
    fi
}

renew_certificates() {
    log_renewal "INFO" "Starting automatic certificate renewal process"
    
    # Check if certbot is available
    if ! command -v certbot >/dev/null 2>&1; then
        log_renewal "ERROR" "Certbot not found, cannot perform renewals"
        if [[ "$ENABLE_NOTIFICATIONS" == "true" ]]; then
            send_notification "ERROR: Certbot Not Found" \
                "Certbot command not found on $(hostname). SSL certificate renewal cannot proceed." \
                "ERROR"
        fi
        return 1
    fi
    
    # Perform renewal
    local renewal_output
    local renewal_status=0
    
    # Capture both stdout and stderr
    renewal_output=$(certbot renew --quiet --no-self-upgrade 2>&1) || renewal_status=$?
    
    if [[ $renewal_status -eq 0 ]]; then
        log_renewal "INFO" "Certificate renewal completed successfully"
        
        # Check if any certificates were actually renewed
        if echo "$renewal_output" | grep -q "renewed"; then
            log_renewal "INFO" "Certificates were renewed"
            
            # Reload web services
            reload_web_services
            
            # Send success notification
            if [[ "$ENABLE_NOTIFICATIONS" == "true" ]]; then
                local renewed_certs=$(echo "$renewal_output" | grep -o "Renewed.*" | head -5)
                send_notification "SSL Certificates Renewed Successfully" \
                    "Certificate renewal completed on $(hostname). Services have been reloaded.\n\nRenewal details:\n$renewed_certs" \
                    "INFO"
            fi
        else
            log_renewal "INFO" "No certificates needed renewal"
        fi
    else
        log_renewal "ERROR" "Certificate renewal failed with status $renewal_status"
        log_renewal "ERROR" "Renewal output: $renewal_output"
        
        # Send failure notification
        if [[ "$ENABLE_NOTIFICATIONS" == "true" ]]; then
            send_notification "ERROR: SSL Certificate Renewal Failed" \
                "Certificate renewal failed on $(hostname) with status $renewal_status.\n\nError details:\n$renewal_output" \
                "ERROR"
        fi
        
        return $renewal_status
    fi
}

reload_web_services() {
    log_renewal "INFO" "Reloading web services after certificate renewal"
    
    local services_reloaded=0
    
    # Reload Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        if systemctl reload nginx 2>/dev/null; then
            log_renewal "INFO" "Nginx reloaded successfully"
            ((services_reloaded++))
        else
            log_renewal "ERROR" "Failed to reload Nginx"
        fi
    fi
    
    # Reload Apache
    if systemctl is-active --quiet apache2 2>/dev/null; then
        if systemctl reload apache2 2>/dev/null; then
            log_renewal "INFO" "Apache reloaded successfully"
            ((services_reloaded++))
        else
            log_renewal "ERROR" "Failed to reload Apache"
        fi
    fi
    
    # Reload other web servers
    for service in httpd lighttpd caddy; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            if systemctl reload "$service" 2>/dev/null; then
                log_renewal "INFO" "$service reloaded successfully"
                ((services_reloaded++))
            else
                log_renewal "ERROR" "Failed to reload $service"
            fi
        fi
    done
    
    log_renewal "INFO" "Reloaded $services_reloaded web service(s)"
}

check_all_certificates() {
    log_renewal "INFO" "Checking all certificate expiry dates"
    
    if [[ ! -d "$CERT_DIR" ]]; then
        log_renewal "WARN" "No certificates directory found"
        return 0
    fi
    
    local total_certs=0
    local warning_certs=0
    local critical_certs=0
    
    for cert_dir in "$CERT_DIR"/*/; do
        if [[ -d "$cert_dir" ]]; then
            local domain=$(basename "$cert_dir")
            ((total_certs++))
            
            check_certificate_expiry "$domain"
            local check_result=$?
            
            case $check_result in
                1)
                    ((warning_certs++))
                    ;;
                2)
                    ((critical_certs++))
                    ;;
            esac
        fi
    done
    
    log_renewal "INFO" "Certificate check complete: $total_certs total, $warning_certs warnings, $critical_certs critical"
    
    # Send summary notification if there are issues
    if [[ $critical_certs -gt 0 ]] || [[ $warning_certs -gt 0 ]]; then
        local summary="Certificate Status Summary:\n"
        summary+="• Total certificates: $total_certs\n"
        summary+="• Warning (expires in $WARNING_DAYS days): $warning_certs\n"
        summary+="• Critical (expires in $CRITICAL_DAYS days): $critical_certs"
        
        local level="WARN"
        [[ $critical_certs -gt 0 ]] && level="CRITICAL"
        
        if [[ "$ENABLE_NOTIFICATIONS" == "true" ]]; then
            send_notification "SSL Certificate Status Alert" "$summary" "$level"
        fi
    fi
}

generate_report() {
    log_renewal "INFO" "Generating SSL management report"
    
    local report_file="$LOG_DIR/weekly_report_$(date +%Y%m%d).txt"
    
    cat > "$report_file" << EOF
SSL Certificate Management Report
================================
Generated: $(date)
Server: $(hostname)

Certificate Status:
EOF
    
    if [[ -d "$CERT_DIR" ]]; then
        printf "%-30s %-15s %-25s %-10s\n" "DOMAIN" "STATUS" "EXPIRES" "DAYS LEFT" >> "$report_file"
        printf "%s\n" "$(printf '=%.0s' {1..80})" >> "$report_file"
        
        for cert_dir in "$CERT_DIR"/*/; do
            if [[ -d "$cert_dir" ]]; then
                local domain=$(basename "$cert_dir")
                local cert_file="$cert_dir/cert.pem"
                
                if [[ -f "$cert_file" ]]; then
                    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
                    local expiry_epoch=$(date -d "$expiry_date" +%s)
                    local current_epoch=$(date +%s)
                    local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
                    local status="Valid"
                    
                    if [[ $days_left -lt 0 ]]; then
                        status="Expired"
                    elif [[ $days_left -lt $CRITICAL_DAYS ]]; then
                        status="Critical"
                    elif [[ $days_left -lt $WARNING_DAYS ]]; then
                        status="Warning"
                    fi
                    
                    printf "%-30s %-15s %-25s %-10s\n" \
                        "$domain" "$status" "$expiry_date" "$days_left" >> "$report_file"
                fi
            fi
        done
    else
        echo "No certificates found" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

Recent Activity:
$(tail -20 "$LOG_DIR/renewals.log" 2>/dev/null || echo "No recent activity")

System Information:
- Certbot Version: $(certbot --version 2>&1 || echo "Not available")
- Disk Usage (certificates): $(du -sh /etc/letsencrypt 2>/dev/null || echo "N/A")
- Backup Space: $(du -sh "$BACKUP_DIR" 2>/dev/null || echo "N/A")

Next Scheduled Renewal: $(systemctl list-timers certbot-renewal.timer --no-pager 2>/dev/null | grep -A1 "NEXT" | tail -1 || echo "Not scheduled")
EOF
    
    log_renewal "INFO" "Report generated: $report_file"
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    log_renewal "INFO" "Starting SSL renewal cron job"
    
    # Check certificate expiry dates
    check_all_certificates
    
    # Create backup before renewal
    backup_certificates
    
    # Perform certificate renewals
    renew_certificates
    
    # Clean up old backups
    cleanup_old_backups
    
    # Generate weekly report (only on Sundays)
    if [[ $(date +%u) -eq 7 ]]; then
        generate_report
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_renewal "INFO" "SSL renewal cron job completed in ${duration} seconds"
}

# Error handling
trap 'log_renewal "ERROR" "SSL renewal cron job failed with error"; exit 1' ERR

# Load configuration from environment or config file
if [[ -f /etc/bashmin/ssl.conf ]]; then
    source /etc/bashmin/ssl.conf
fi

# Execute main function
main "$@"

exit 0
