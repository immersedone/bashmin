#!/bin/bash
#
# Script: security/nikto/install.sh
# Description: Install and configure Nikto web vulnerability scanner
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
readonly NIKTO_CONFIG_DIR="/etc/nikto"
readonly NIKTO_CONFIG_FILE="$NIKTO_CONFIG_DIR/config.txt"
readonly NIKTO_PLUGINS_DIR="/usr/share/nikto/plugins"
readonly NIKTO_DATABASES_DIR="/usr/share/nikto/databases"
readonly NIKTO_TEMPLATES_DIR="/usr/share/nikto/templates"
readonly BASHMIN_LOG_DIR="/var/log/bashmin"
readonly BASHMIN_NIKTO_DIR="/var/log/bashmin/security/nikto"
readonly NIKTO_REPORTS_DIR="$BASHMIN_NIKTO_DIR/reports"
readonly NIKTO_SCAN_LOG="$BASHMIN_NIKTO_DIR/nikto.log"
readonly NIKTO_ERROR_LOG="$BASHMIN_NIKTO_DIR/nikto-error.log"
readonly NIKTO_CRON_SCRIPT="/usr/local/bin/nikto-scan"
readonly BASHMIN_LOGROTATE_CONF="$PROJECT_ROOT/system/etc/logrotate.d/nikto"

# Configuration variables
INSTALL_METHOD="package"
ENABLE_CRON=false
CRON_SCHEDULE="weekly"
AUTO_UPDATE_DB=true
ENABLE_REPORTING=true
NOTIFICATION_EMAIL=""
SLACK_WEBHOOK=""
OUTPUT_FORMAT="html"
SCAN_TARGETS=""
DEFAULT_SCAN_OPTIONS="-h"
AGGRESSIVE_SCAN=false
STEALTH_MODE=false
FOLLOW_REDIRECTS=true
CHECK_OUTDATED=true
CUSTOM_PLUGINS=""
EXCLUDED_PLUGINS=""
MAX_SCAN_TIME="3600"
THREAD_COUNT="5"
USER_AGENT="Nikto/bashmin-security"
PROXY_SERVER=""
PROXY_AUTH=""
SSL_VERIFY=true
REPORT_RETENTION_DAYS=90
VERBOSE=false
DRY_RUN=false

# Help function
show_help() {
    cat << 'EOF'
Nikto Web Vulnerability Scanner Installation

DESCRIPTION:
    Comprehensive installation and configuration of Nikto web vulnerability scanner.
    Provides automated web application security testing with integrated reporting
    and scheduling capabilities.

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    Installation Configuration:
    --install-method METHOD     Installation method: package, git [package]
    --auto-update-db           Enable automatic database updates [default]
    --disable-auto-update-db   Disable automatic database updates
    
    Scan Configuration:
    --scan-targets TARGETS     Default scan targets (comma-separated URLs)
    --aggressive-scan          Enable aggressive scanning mode
    --stealth-mode             Enable stealth scanning (slower, less detectable)
    --no-follow-redirects      Disable following HTTP redirects
    --disable-outdated-check   Skip outdated software detection
    --max-scan-time SECONDS    Maximum scan time per target [3600]
    --thread-count COUNT       Number of concurrent threads [5]
    --user-agent STRING        Custom User-Agent string
    
    Plugin Management:
    --custom-plugins LIST      Comma-separated list of custom plugins to enable
    --excluded-plugins LIST    Comma-separated list of plugins to exclude
    --check-outdated           Check for outdated software [default]
    
    Network & Proxy:
    --proxy-server URL         HTTP proxy server (http://proxy:port)
    --proxy-auth USER:PASS     Proxy authentication credentials
    --no-ssl-verify            Disable SSL certificate verification
    
    Scheduling & Automation:
    --enable-cron              Enable automated scanning
    --disable-cron             Disable automated scanning [default]
    --cron-schedule SCHEDULE   Cron schedule: daily, weekly, monthly [weekly]
    
    Reporting & Output:
    --enable-reporting         Enable comprehensive reporting [default]
    --disable-reporting        Disable reporting features
    --output-format FORMAT     Report format: html, xml, csv, txt [html]
    --report-retention DAYS    Report retention period in days [90]
    
    Notifications:
    --notification-email EMAIL Email for scan notifications
    --slack-webhook URL        Slack webhook for notifications
    
    General Options:
    --dry-run                  Show what would be done without making changes
    --verbose                  Enable verbose output
    --help, -h                 Show this help message

EXAMPLES:
    # Basic installation
    ./install.sh

    # Install with automated scanning
    ./install.sh --enable-cron --scan-targets "https://example.com,https://test.com"

    # Install with stealth scanning and proxy
    ./install.sh --stealth-mode --proxy-server "http://proxy:8080"

    # Custom configuration with notifications
    ./install.sh --aggressive-scan --notification-email admin@example.com

    # Dry run to preview changes
    ./install.sh --dry-run --verbose

SECURITY FEATURES:
    - Comprehensive web vulnerability detection
    - SSL/TLS security testing
    - Outdated software identification
    - Plugin-based extensible architecture
    - Stealth scanning capabilities
    - Automated scheduling and reporting

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install-method)
                INSTALL_METHOD="$2"
                shift 2
                ;;
            --auto-update-db)
                AUTO_UPDATE_DB=true
                shift
                ;;
            --disable-auto-update-db)
                AUTO_UPDATE_DB=false
                shift
                ;;
            --scan-targets)
                SCAN_TARGETS="$2"
                shift 2
                ;;
            --aggressive-scan)
                AGGRESSIVE_SCAN=true
                shift
                ;;
            --stealth-mode)
                STEALTH_MODE=true
                shift
                ;;
            --no-follow-redirects)
                FOLLOW_REDIRECTS=false
                shift
                ;;
            --disable-outdated-check)
                CHECK_OUTDATED=false
                shift
                ;;
            --max-scan-time)
                MAX_SCAN_TIME="$2"
                shift 2
                ;;
            --thread-count)
                THREAD_COUNT="$2"
                shift 2
                ;;
            --user-agent)
                USER_AGENT="$2"
                shift 2
                ;;
            --custom-plugins)
                CUSTOM_PLUGINS="$2"
                shift 2
                ;;
            --excluded-plugins)
                EXCLUDED_PLUGINS="$2"
                shift 2
                ;;
            --proxy-server)
                PROXY_SERVER="$2"
                shift 2
                ;;
            --proxy-auth)
                PROXY_AUTH="$2"
                shift 2
                ;;
            --no-ssl-verify)
                SSL_VERIFY=false
                shift
                ;;
            --enable-cron)
                ENABLE_CRON=true
                shift
                ;;
            --disable-cron)
                ENABLE_CRON=false
                shift
                ;;
            --cron-schedule)
                CRON_SCHEDULE="$2"
                shift 2
                ;;
            --enable-reporting)
                ENABLE_REPORTING=true
                shift
                ;;
            --disable-reporting)
                ENABLE_REPORTING=false
                shift
                ;;
            --output-format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --report-retention)
                REPORT_RETENTION_DAYS="$2"
                shift 2
                ;;
            --notification-email)
                NOTIFICATION_EMAIL="$2"
                shift 2
                ;;
            --slack-webhook)
                SLACK_WEBHOOK="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Validate configuration
validate_configuration() {
    # Validate install method
    if [[ ! "$INSTALL_METHOD" =~ ^(package|git)$ ]]; then
        print_error "Invalid install method: $INSTALL_METHOD. Must be 'package' or 'git'"
        exit 1
    fi
    
    # Validate output format
    if [[ ! "$OUTPUT_FORMAT" =~ ^(html|xml|csv|txt)$ ]]; then
        print_error "Invalid output format: $OUTPUT_FORMAT. Must be html, xml, csv, or txt"
        exit 1
    fi
    
    # Validate cron schedule
    if [[ ! "$CRON_SCHEDULE" =~ ^(daily|weekly|monthly)$ ]]; then
        print_error "Invalid cron schedule: $CRON_SCHEDULE. Must be daily, weekly, or monthly"
        exit 1
    fi
    
    # Validate email format
    if [[ -n "$NOTIFICATION_EMAIL" ]] && [[ ! "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        print_error "Invalid email address format: $NOTIFICATION_EMAIL"
        exit 1
    fi
    
    # Validate numeric values
    if [[ ! "$MAX_SCAN_TIME" =~ ^[0-9]+$ ]] || [[ "$MAX_SCAN_TIME" -lt 60 ]]; then
        print_error "Invalid max scan time: $MAX_SCAN_TIME. Must be numeric and >= 60 seconds"
        exit 1
    fi
    
    if [[ ! "$THREAD_COUNT" =~ ^[0-9]+$ ]] || [[ "$THREAD_COUNT" -lt 1 ]] || [[ "$THREAD_COUNT" -gt 50 ]]; then
        print_error "Invalid thread count: $THREAD_COUNT. Must be numeric between 1-50"
        exit 1
    fi
    
    if [[ ! "$REPORT_RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$REPORT_RETENTION_DAYS" -lt 1 ]]; then
        print_error "Invalid report retention days: $REPORT_RETENTION_DAYS. Must be numeric and >= 1"
        exit 1
    fi
}

# Install Nikto
install_nikto() {
    print_info "Installing Nikto web vulnerability scanner..."
    
    # Update package lists
    update_system
    
    case "$INSTALL_METHOD" in
        package)
            print_info "Installing Nikto from package repository..."
            install_prerequisites "nikto"
            ;;
        git)
            print_info "Installing Nikto from Git repository..."
            install_prerequisites "git perl libnet-ssleay-perl libcrypt-ssleay-perl libio-socket-ssl-perl"
            
            # Clone or update Nikto repository
            if [[ -d "/opt/nikto" ]]; then
                execute_command "cd /opt/nikto && sudo git pull" "Updating Nikto from Git"
            else
                execute_command "sudo git clone https://github.com/sullo/nikto.git /opt/nikto" "Cloning Nikto repository"
            fi
            
            # Create symlink
            execute_command "sudo ln -sf /opt/nikto/program/nikto.pl /usr/local/bin/nikto" "Creating Nikto symlink"
            execute_command "sudo chmod +x /usr/local/bin/nikto" "Making Nikto executable"
            ;;
    esac
    
    print_success "Nikto installed successfully"
}

# Create directory structure
create_directories() {
    print_info "Creating directory structure..."
    
    local directories=(
        "$NIKTO_CONFIG_DIR"
        "$BASHMIN_LOG_DIR"
        "$BASHMIN_NIKTO_DIR"
        "$NIKTO_REPORTS_DIR"
    )
    
    for dir in "${directories[@]}"; do
        execute_command "sudo mkdir -p '$dir'" "Creating directory: $dir"
    done
    
    # Set proper permissions
    execute_command "sudo chown -R root:root '$NIKTO_CONFIG_DIR'" "Setting config directory ownership"
    execute_command "sudo chmod 755 '$NIKTO_CONFIG_DIR'" "Setting config directory permissions"
    execute_command "sudo chmod 755 '$BASHMIN_NIKTO_DIR'" "Setting log directory permissions"
    execute_command "sudo chmod 755 '$NIKTO_REPORTS_DIR'" "Setting reports directory permissions"
    
    print_success "Directory structure created"
}

# Configure Nikto
configure_nikto() {
    print_info "Configuring Nikto..."
    
    # Create main configuration
    local config_content="# Nikto configuration - managed by bashmin
# Generated on $(date)

# Database configuration
UPDATES=yes
DBCHECK=yes
AUTOUPDATE=$([[ "$AUTO_UPDATE_DB" == true ]] && echo "yes" || echo "no")

# Scan configuration
USERAGENT=$USER_AGENT
MAXTIME=$MAX_SCAN_TIME
THREADS=$THREAD_COUNT

# Output configuration
CLIOPTS=-Format $OUTPUT_FORMAT
"

    if [[ "$FOLLOW_REDIRECTS" == true ]]; then
        config_content="$config_content
FOLLOWREDIRECTS=yes
"
    else
        config_content="$config_content
FOLLOWREDIRECTS=no
"
    fi

    if [[ "$SSL_VERIFY" == false ]]; then
        config_content="$config_content
NOLOOKUP=yes
SKIPSPIDER=yes
"
    fi

    if [[ -n "$PROXY_SERVER" ]]; then
        config_content="$config_content
PROXYHOST=$PROXY_SERVER
"
        if [[ -n "$PROXY_AUTH" ]]; then
            config_content="$config_content
PROXYUSER=$PROXY_AUTH
"
        fi
    fi

    # Plugin configuration
    if [[ -n "$EXCLUDED_PLUGINS" ]]; then
        config_content="$config_content
SKIPTEST=$EXCLUDED_PLUGINS
"
    fi

    if [[ -n "$CUSTOM_PLUGINS" ]]; then
        config_content="$config_content
INCLUDE=$CUSTOM_PLUGINS
"
    fi

    config_content="$config_content

# Stealth mode configuration"
    if [[ "$STEALTH_MODE" == true ]]; then
        config_content="$config_content
PAUSE=2
TIMEOUT=10
"
    fi

    config_content="$config_content

# Aggressive scan configuration"
    if [[ "$AGGRESSIVE_SCAN" == true ]]; then
        config_content="$config_content
MUTATE=all
ENUMERATE=all
"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would write Nikto configuration to $NIKTO_CONFIG_FILE"
        echo "Configuration preview:"
        echo "$config_content" | head -20
        echo "... (truncated)"
    else
        echo "$config_content" | sudo tee "$NIKTO_CONFIG_FILE" > /dev/null
        print_success "Nikto configuration updated"
    fi
}

# Update Nikto databases
update_databases() {
    print_info "Updating Nikto databases..."
    
    if [[ "$AUTO_UPDATE_DB" == true ]]; then
        execute_command "nikto -update" "Updating Nikto vulnerability databases"
        print_success "Nikto databases updated"
    else
        print_info "Database auto-update disabled - skipping update"
    fi
}

# Setup log rotation
setup_logrotate() {
    print_info "Setting up log rotation..."
    
    if [[ -f "$BASHMIN_LOGROTATE_CONF" ]]; then
        execute_command "sudo cp '$BASHMIN_LOGROTATE_CONF' /etc/logrotate.d/nikto" \
            "Installing Nikto logrotate configuration"
        print_success "Log rotation configured"
    else
        print_warning "Logrotate configuration file not found at $BASHMIN_LOGROTATE_CONF"
        
        # Create basic logrotate config
        local logrotate_content="$BASHMIN_NIKTO_DIR/*.log {
    daily
    missingok
    rotate $REPORT_RETENTION_DAYS
    compress
    delaycompress
    notifempty
    create 640 root adm
    sharedscripts
    postrotate
        # Clean up old reports
        find $NIKTO_REPORTS_DIR -name '*.html' -mtime +$REPORT_RETENTION_DAYS -delete 2>/dev/null || true
        find $NIKTO_REPORTS_DIR -name '*.xml' -mtime +$REPORT_RETENTION_DAYS -delete 2>/dev/null || true
        find $NIKTO_REPORTS_DIR -name '*.csv' -mtime +$REPORT_RETENTION_DAYS -delete 2>/dev/null || true
    endscript
}"
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would create logrotate configuration"
        else
            echo "$logrotate_content" | sudo tee /etc/logrotate.d/nikto > /dev/null
            print_success "Basic log rotation configured"
        fi
    fi
}

# Create scan wrapper script
create_scan_script() {
    print_info "Creating scan wrapper script..."
    
    local scan_script="#!/bin/bash
#
# Nikto automated scan script
# Generated by bashmin on $(date)
#

set -euo pipefail

# Configuration
NIKTO_BIN=\$(command -v nikto)
NIKTO_CONFIG=\"$NIKTO_CONFIG_FILE\"
REPORTS_DIR=\"$NIKTO_REPORTS_DIR\"
LOG_FILE=\"$NIKTO_SCAN_LOG\"
ERROR_LOG=\"$NIKTO_ERROR_LOG\"
OUTPUT_FORMAT=\"$OUTPUT_FORMAT\"
SCAN_TARGETS=\"$SCAN_TARGETS\"
NOTIFICATION_EMAIL=\"$NOTIFICATION_EMAIL\"
SLACK_WEBHOOK=\"$SLACK_WEBHOOK\"

# Logging function
log_message() {
    echo \"\$(date '+%Y-%m-%d %H:%M:%S') - \$1\" >> \"\$LOG_FILE\"
}

# Send notification
send_notification() {
    local message=\"\$1\"
    local severity=\"\$2\"
    
    # Email notification
    if [[ -n \"\$NOTIFICATION_EMAIL\" ]] && command -v mail >/dev/null 2>&1; then
        echo \"\$message\" | mail -s \"[Nikto] \$severity - Web Security Scan\" \"\$NOTIFICATION_EMAIL\"
    fi
    
    # Slack notification
    if [[ -n \"\$SLACK_WEBHOOK\" ]] && command -v curl >/dev/null 2>&1; then
        local payload='{\"text\":\"Nikto Security Scan - '\$severity': '\$message'\"}'
        curl -X POST -H 'Content-type: application/json' --data \"\$payload\" \"\$SLACK_WEBHOOK\" >/dev/null 2>&1 || true
    fi
}

# Run scan function
run_scan() {
    local target=\"\$1\"
    local timestamp=\$(date '+%Y%m%d_%H%M%S')
    local report_file=\"\$REPORTS_DIR/nikto_\${target//[^a-zA-Z0-9]/_}_\$timestamp.\$OUTPUT_FORMAT\"
    
    log_message \"Starting scan of \$target\"
    
    local scan_options=\"-h \$target\"
    
    # Add configuration options
    if [[ -f \"\$NIKTO_CONFIG\" ]]; then
        scan_options=\"\$scan_options -config \$NIKTO_CONFIG\"
    fi
    
    # Add output format
    scan_options=\"\$scan_options -Format \$OUTPUT_FORMAT\"
    scan_options=\"\$scan_options -output \$report_file\"
    
    # Add stealth mode if enabled
    $([[ "$STEALTH_MODE" == true ]] && echo 'scan_options="$scan_options -evasion 1"')
    
    # Add aggressive scanning if enabled
    $([[ "$AGGRESSIVE_SCAN" == true ]] && echo 'scan_options="$scan_options -mutate 1,2,3,4,5,6,7,8,9"')
    
    # Run the scan
    if timeout \$MAX_SCAN_TIME \"\$NIKTO_BIN\" \$scan_options 2>>\"\$ERROR_LOG\"; then
        log_message \"Scan completed successfully for \$target\"
        
        # Check for vulnerabilities
        if [[ -f \"\$report_file\" ]]; then
            local vuln_count=0
            if [[ \"\$OUTPUT_FORMAT\" == \"xml\" ]]; then
                vuln_count=\$(grep -c '<item' \"\$report_file\" 2>/dev/null || echo 0)
            elif [[ \"\$OUTPUT_FORMAT\" == \"csv\" ]]; then
                vuln_count=\$(wc -l < \"\$report_file\" 2>/dev/null || echo 0)
                vuln_count=\$((vuln_count - 1)) # Subtract header
            else
                vuln_count=\$(grep -c 'OSVDB' \"\$report_file\" 2>/dev/null || echo 0)
            fi
            
            if [[ \$vuln_count -gt 0 ]]; then
                local message=\"Nikto scan of \$target found \$vuln_count potential vulnerabilities. Report: \$report_file\"
                log_message \"\$message\"
                send_notification \"\$message\" \"WARNING\"
            else
                log_message \"No vulnerabilities found for \$target\"
            fi
        fi
    else
        local error_msg=\"Scan failed or timed out for \$target\"
        log_message \"\$error_msg\"
        send_notification \"\$error_msg\" \"ERROR\"
        return 1
    fi
}

# Main execution
main() {
    log_message \"Starting automated Nikto scan\"
    
    if [[ -z \"\$SCAN_TARGETS\" ]]; then
        log_message \"No scan targets configured - exiting\"
        exit 0
    fi
    
    # Split targets and scan each
    IFS=',' read -ra TARGETS <<< \"\$SCAN_TARGETS\"
    for target in \"\${TARGETS[@]}\"; do
        target=\$(echo \"\$target\" | xargs) # Trim whitespace
        if [[ -n \"\$target\" ]]; then
            run_scan \"\$target\"
        fi
    done
    
    log_message \"Automated scan completed\"
}

# Run main function
main \"\$@\"
"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create scan script at $NIKTO_CRON_SCRIPT"
    else
        echo "$scan_script" | sudo tee "$NIKTO_CRON_SCRIPT" > /dev/null
        sudo chmod +x "$NIKTO_CRON_SCRIPT"
        print_success "Scan wrapper script created"
    fi
}

# Setup automated scanning
setup_automation() {
    if [[ "$ENABLE_CRON" != true ]]; then
        print_info "Automated scanning disabled - skipping cron setup"
        return 0
    fi
    
    print_info "Setting up automated scanning..."
    
    if [[ -z "$SCAN_TARGETS" ]]; then
        print_warning "No scan targets specified - automated scanning will be inactive"
        print_info "Configure targets by editing $NIKTO_CRON_SCRIPT or re-run with --scan-targets"
    fi
    
    # Create cron job based on schedule
    local cron_schedule=""
    case "$CRON_SCHEDULE" in
        daily)
            cron_schedule="0 2 * * *"
            ;;
        weekly)
            cron_schedule="0 2 * * 0"
            ;;
        monthly)
            cron_schedule="0 2 1 * *"
            ;;
    esac
    
    local cron_job="$cron_schedule root $NIKTO_CRON_SCRIPT >/dev/null 2>&1"
    local cron_file="/etc/cron.d/nikto-scan"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create cron job: $cron_job"
    else
        echo "$cron_job" | sudo tee "$cron_file" > /dev/null
        print_success "Automated scanning configured ($CRON_SCHEDULE)"
    fi
}

# Run test scan
run_test_scan() {
    if [[ "$DRY_RUN" == true ]]; then
        print_info "Skipping test scan in dry-run mode"
        return 0
    fi
    
    print_info "Running Nikto version check..."
    
    if command -v nikto >/dev/null 2>&1; then
        echo ""
        print_info "Nikto version information:"
        nikto -Version 2>/dev/null || print_warning "Could not retrieve version information"
        
        if [[ -n "$SCAN_TARGETS" ]] && confirm_action "Run a test scan on configured targets?" "N"; then
            local first_target=$(echo "$SCAN_TARGETS" | cut -d',' -f1 | xargs)
            if [[ -n "$first_target" ]]; then
                print_info "Running test scan on: $first_target"
                echo "This may take a few minutes..."
                
                local test_report="$NIKTO_REPORTS_DIR/test_scan_$(date '+%Y%m%d_%H%M%S').$OUTPUT_FORMAT"
                
                if timeout 300 nikto -h "$first_target" -Format "$OUTPUT_FORMAT" -output "$test_report" 2>/dev/null; then
                    print_success "Test scan completed successfully"
                    print_info "Test report saved to: $test_report"
                    
                    if [[ -f "$test_report" ]]; then
                        echo ""
                        print_info "Scan summary:"
                        if [[ "$OUTPUT_FORMAT" == "txt" ]]; then
                            tail -10 "$test_report" 2>/dev/null || echo "Could not display summary"
                        else
                            echo "Report generated in $OUTPUT_FORMAT format - view with appropriate tool"
                        fi
                    fi
                else
                    print_warning "Test scan timed out or failed - this is normal for initial testing"
                fi
            fi
        fi
    else
        print_error "Nikto installation verification failed"
        return 1
    fi
}

# Show status and usage information
show_status() {
    echo ""
    print_success "Nikto installation and configuration completed!"
    echo ""
    echo "Configuration Summary:"
    echo "  • Installation method: $INSTALL_METHOD"
    echo "  • Configuration file: $NIKTO_CONFIG_FILE"
    echo "  • Reports directory: $NIKTO_REPORTS_DIR"
    echo "  • Log file: $NIKTO_SCAN_LOG"
    echo "  • Output format: $OUTPUT_FORMAT"
    echo "  • Automated scanning: $([[ "$ENABLE_CRON" == true ]] && echo "Enabled ($CRON_SCHEDULE)" || echo "Disabled")"
    echo "  • Database auto-update: $([[ "$AUTO_UPDATE_DB" == true ]] && echo "Enabled" || echo "Disabled")"
    echo "  • Stealth mode: $([[ "$STEALTH_MODE" == true ]] && echo "Enabled" || echo "Disabled")"
    echo "  • Aggressive scanning: $([[ "$AGGRESSIVE_SCAN" == true ]] && echo "Enabled" || echo "Disabled")"
    
    if [[ -n "$SCAN_TARGETS" ]]; then
        echo "  • Scan targets: $SCAN_TARGETS"
    else
        echo "  • Scan targets: Not configured"
    fi
    
    if [[ -n "$NOTIFICATION_EMAIL" ]]; then
        echo "  • Email notifications: $NOTIFICATION_EMAIL"
    else
        echo "  • Email notifications: Disabled"
    fi
    
    echo ""
    echo "Usage Commands:"
    echo "  • Manual scan:          nikto -h https://example.com"
    echo "  • Stealth scan:         nikto -h https://example.com -evasion 1"
    echo "  • Aggressive scan:      nikto -h https://example.com -mutate 1,2,3,4,5"
    echo "  • Multiple formats:     nikto -h https://example.com -Format html,xml"
    echo "  • Update databases:     nikto -update"
    echo "  • View version:         nikto -Version"
    echo "  • Automated scan:       $NIKTO_CRON_SCRIPT"
    echo ""
    echo "Report Locations:"
    echo "  • Scan reports:         $NIKTO_REPORTS_DIR"
    echo "  • Scan logs:            $NIKTO_SCAN_LOG"
    echo "  • Error logs:           $NIKTO_ERROR_LOG"
    echo ""
    echo "Security Tips:"
    echo "  • Review scan reports regularly for new vulnerabilities"
    echo "  • Use stealth mode when scanning production systems"
    echo "  • Update databases frequently: nikto -update"
    echo "  • Consider rate limiting and time restrictions for automated scans"
    echo "  • Combine with other security tools like nmap and SSL testing"
    echo ""
    echo "Integration with bashmin security suite:"
    echo "  • fail2ban: Protects against scan attempts"
    echo "  • ufw: Controls network access"
    echo "  • lynis: System security auditing"
    echo "  • rkhunter: Rootkit detection"
    echo ""
}

# Main function
main() {
    print_info "Starting Nikto web vulnerability scanner installation..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate configuration
    validate_configuration
    
    # Check system compatibility
    check_ubuntu_system
    
    # Show configuration summary
    if [[ "$DRY_RUN" != true ]]; then
        echo ""
        echo "Installation Configuration:"
        echo "  • Installation method: $INSTALL_METHOD"
        echo "  • Output format: $OUTPUT_FORMAT"
        echo "  • Max scan time: ${MAX_SCAN_TIME}s"
        echo "  • Thread count: $THREAD_COUNT"
        echo "  • Stealth mode: $([[ "$STEALTH_MODE" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Aggressive scanning: $([[ "$AGGRESSIVE_SCAN" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Automated scanning: $([[ "$ENABLE_CRON" == true ]] && echo "Enabled ($CRON_SCHEDULE)" || echo "Disabled")"
        echo "  • Auto-update databases: $([[ "$AUTO_UPDATE_DB" == true ]] && echo "Enabled" || echo "Disabled")"
        
        if [[ -n "$SCAN_TARGETS" ]]; then
            echo "  • Scan targets: $SCAN_TARGETS"
        fi
        
        if [[ -n "$NOTIFICATION_EMAIL" ]]; then
            echo "  • Email notifications: $NOTIFICATION_EMAIL"
        fi
        
        if [[ -n "$PROXY_SERVER" ]]; then
            echo "  • Proxy server: $PROXY_SERVER"
        fi
        
        echo ""
        
        if ! confirm_action "Proceed with Nikto installation?" "Y"; then
            print_info "Installation cancelled by user"
            exit 0
        fi
    fi
    
    # Installation steps
    install_nikto
    create_directories
    configure_nikto
    update_databases
    setup_logrotate
    create_scan_script
    setup_automation
    
    if [[ "$DRY_RUN" != true ]]; then
        run_test_scan
        show_status
    else
        print_info "Dry run completed - no changes were made"
    fi
}

# Run main function with all arguments
main "$@"