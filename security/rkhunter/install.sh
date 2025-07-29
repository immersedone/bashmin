#!/bin/bash
#
# Script: security/rkhunter/install.sh
# Description: Install and configure rkhunter rootkit detection system
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
readonly RKHUNTER_CONFIG_FILE="/etc/rkhunter.conf"
readonly RKHUNTER_LOG_FILE="/var/log/rkhunter.log"
readonly RKHUNTER_DATA_DIR="/var/lib/rkhunter"
readonly RKHUNTER_TEMP_DIR="/var/lib/rkhunter/tmp"
readonly BASHMIN_LOGROTATE_CONF="$PROJECT_ROOT/system/etc/logrotate.d/rkhunter"
readonly RKHUNTER_CRON_DAILY="/etc/cron.daily/rkhunter"
readonly RKHUNTER_CRON_WEEKLY="/etc/cron.weekly/rkhunter"

# Configuration variables
ENABLE_DAILY_CHECKS=true
ENABLE_WEEKLY_UPDATES=true
AUTO_UPDATE_DB=true
MAIL_ON_WARNING=""
SCAN_MODE="--checkall"
SKIP_KEYPRESS=true
UPDATE_MIRRORS=true
COPY_LOG_ON_ERROR=false
USE_SYSLOG=false
DISABLE_TESTS=""
ENABLE_TESTS=""
TMPDIR="/var/lib/rkhunter/tmp"
PKGMGR="DPKG"

# CLI argument parsing
show_help() {
    cat << EOF
rkhunter Installation Script

DESCRIPTION:
    Installs and configures rkhunter rootkit detection system for enhanced server security.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --mail-on-warning EMAIL    Email address to send warnings to
    --disable-daily-checks     Disable automatic daily security checks
    --disable-weekly-updates   Disable automatic weekly database updates
    --no-auto-update-db        Disable automatic database updates
    --scan-mode MODE           Set scan mode (--checkall, --check, --cronjob)
    --disable-tests TESTS      Comma-separated list of tests to disable
    --enable-tests TESTS       Comma-separated list of tests to enable
    --use-syslog               Enable syslog logging
    --tmpdir PATH              Set temporary directory (default: /var/lib/rkhunter/tmp)
    --dry-run                  Show what would be done without making changes
    --verbose                  Enable verbose output
    --help, -h                 Show this help message

EXAMPLES:
    # Basic installation
    $0

    # Install with email notifications
    $0 --mail-on-warning admin@example.com

    # Install with custom configuration
    $0 --disable-tests "hidden_procs,deleted_files" --use-syslog

    # Dry run to preview changes
    $0 --dry-run --verbose

SECURITY FEATURES:
    - Comprehensive rootkit detection
    - Daily automated security scans
    - Weekly database updates
    - Email notification support
    - Secure log rotation
    - Customizable test configuration

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mail-on-warning)
                MAIL_ON_WARNING="$2"
                shift 2
                ;;
            --disable-daily-checks)
                ENABLE_DAILY_CHECKS=false
                shift
                ;;
            --disable-weekly-updates)
                ENABLE_WEEKLY_UPDATES=false
                shift
                ;;
            --no-auto-update-db)
                AUTO_UPDATE_DB=false
                shift
                ;;
            --scan-mode)
                SCAN_MODE="$2"
                shift 2
                ;;
            --disable-tests)
                DISABLE_TESTS="$2"
                shift 2
                ;;
            --enable-tests)
                ENABLE_TESTS="$2"
                shift 2
                ;;
            --use-syslog)
                USE_SYSLOG=true
                shift
                ;;
            --tmpdir)
                TMPDIR="$2"
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

# Validate email address format
validate_email() {
    local email="$1"
    if [[ -n "$email" ]] && [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        print_error "Invalid email address format: $email"
        exit 1
    fi
}

# Install rkhunter package
install_rkhunter() {
    print_info "Installing rkhunter rootkit detection system..."
    
    # Update package lists
    update_system
    
    # Install rkhunter and dependencies
    local packages="rkhunter"
    
    if [[ -n "$MAIL_ON_WARNING" ]]; then
        packages="$packages mailutils"
    fi
    
    install_prerequisites "$packages"
    
    print_success "rkhunter installed successfully"
}

# Configure rkhunter main configuration
configure_rkhunter() {
    print_info "Configuring rkhunter..."
    
    # Backup original config
    if [[ -f "$RKHUNTER_CONFIG_FILE" ]] && [[ ! -f "${RKHUNTER_CONFIG_FILE}.backup" ]]; then
        execute_command "sudo cp '$RKHUNTER_CONFIG_FILE' '${RKHUNTER_CONFIG_FILE}.backup'" \
            "Backing up original rkhunter configuration"
    fi
    
    # Create main configuration
    local config_content="# rkhunter configuration - managed by bashmin
# Generated on $(date)

# Update and check options
UPDATE_MIRRORS=$([[ "$UPDATE_MIRRORS" == true ]] && echo "1" || echo "0")
MIRRORS_MODE=0
WEB_CMD=\"\"

# Automatic database update
AUTO_X_DETECT=1

# Mail configuration"
    
    if [[ -n "$MAIL_ON_WARNING" ]]; then
        config_content="$config_content
MAIL-ON-WARNING=\"$MAIL_ON_WARNING\"
MAIL_CMD=mail -s \"[rkhunter] Warnings found for \${HOST_NAME}\"
"
    else
        config_content="$config_content
#MAIL-ON-WARNING=\"\"
#MAIL_CMD=mail -s \"[rkhunter] Warnings found for \${HOST_NAME}\"
"
    fi
    
    config_content="$config_content

# Logging configuration
LOGFILE=\"$RKHUNTER_LOG_FILE\"
APPEND_LOG=1
COPY_LOG_ON_ERROR=$([[ "$COPY_LOG_ON_ERROR" == true ]] && echo "1" || echo "0")
USE_SYSLOG=$([[ "$USE_SYSLOG" == true ]] && echo "1" || echo "0")

# Temporary directory
TMPDIR=\"$TMPDIR\"

# Package manager
PKGMGR=\"$PKGMGR\"

# Hash function
HASH_FUNC=SHA256

# Hash database location
HASH_FLD_DISKS_THRESHOLD=90

# File properties checks
SCRIPTWHITELIST=\"/usr/bin/egrep\"
SCRIPTWHITELIST=\"/usr/bin/fgrep\"
SCRIPTWHITELIST=\"/usr/bin/which\"
SCRIPTWHITELIST=\"/usr/bin/ldd\"
SCRIPTWHITELIST=\"/usr/sbin/adduser\"

# Allow hidden directories
ALLOWHIDDENDIR=\"/etc/.java\"
ALLOWHIDDENDIR=\"/dev/.static\"
ALLOWHIDDENDIR=\"/dev/.udev\"
ALLOWHIDDENDIR=\"/dev/.mount\"

# Allow hidden files
ALLOWHIDDENFILE=\"/etc/.pwd.lock\"
ALLOWHIDDENFILE=\"/etc/.init\"

# Directory whitelist
RTKT_DIR_WHITELIST=\"/usr/bin\"
RTKT_DIR_WHITELIST=\"/usr/sbin\"

# Process whitelist
RTKT_PROCESS_WHITELIST=\"\"

# Port whitelist
PORT_WHITELIST=\"\"

# Network interface whitelist
INETD_ALLOWED_SVC=\"\"

# SSH configuration checks
ALLOW_SSH_ROOT_USER=no
ALLOW_SSH_PROT_V1=0

# System checks to disable/enable"
    
    if [[ -n "$DISABLE_TESTS" ]]; then
        IFS=',' read -ra DISABLED_TESTS <<< "$DISABLE_TESTS"
        for test in "${DISABLED_TESTS[@]}"; do
            config_content="$config_content
DISABLE_TESTS=\"$test\""
        done
    fi
    
    if [[ -n "$ENABLE_TESTS" ]]; then
        IFS=',' read -ra ENABLED_TESTS <<< "$ENABLE_TESTS"
        for test in "${ENABLED_TESTS[@]}"; do
            config_content="$config_content
ENABLE_TESTS=\"$test\""
        done
    fi
    
    config_content="$config_content

# Scan mode configuration
SCAN_MODE_DEV=THOROUGH

# Update check
PKGMGR_NO_VRFY=\"\"

# OS version lock
OS_VERSION_FILE=\"/etc/os-release\"

# Startup file checks
STARTUP_PATHS=\"/etc/rc.local /etc/initd\"

# Password file checks
PASSWD_FILE=\"/etc/passwd\"
GROUP_FILE=\"/etc/group\"

# System command locations
BINDIR=\"/bin /usr/bin /usr/local/bin\"
"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would write rkhunter configuration to $RKHUNTER_CONFIG_FILE"
        echo "Configuration preview:"
        echo "$config_content" | head -20
        echo "... (truncated)"
    else
        echo "$config_content" | sudo tee "$RKHUNTER_CONFIG_FILE" > /dev/null
        print_success "rkhunter configuration updated"
    fi
}

# Setup rkhunter database
setup_database() {
    print_info "Setting up rkhunter database..."
    
    # Create temporary directory
    execute_command "sudo mkdir -p '$TMPDIR'" "Creating temporary directory"
    execute_command "sudo chown root:root '$TMPDIR'" "Setting temporary directory ownership"
    execute_command "sudo chmod 700 '$TMPDIR'" "Setting temporary directory permissions"
    
    # Update file properties database
    execute_command "sudo rkhunter --update" "Updating rkhunter database"
    
    # Initialize file properties database
    execute_command "sudo rkhunter --propupd" "Initializing file properties database"
    
    print_success "rkhunter database setup completed"
}

# Setup log rotation
setup_logrotate() {
    print_info "Setting up log rotation..."
    
    if [[ -f "$BASHMIN_LOGROTATE_CONF" ]]; then
        execute_command "sudo cp '$BASHMIN_LOGROTATE_CONF' /etc/logrotate.d/rkhunter" \
            "Installing rkhunter logrotate configuration"
        print_success "Log rotation configured"
    else
        print_warning "Logrotate configuration file not found at $BASHMIN_LOGROTATE_CONF"
        
        # Create basic logrotate config
        local logrotate_content="/var/log/rkhunter.log {
    rotate 30
    dateext
    dateformat -%Y-%m-%d
    daily
    missingok
    compress
    delaycompress
    notifempty
    create 640 root adm
}"
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would create logrotate configuration"
        else
            echo "$logrotate_content" | sudo tee /etc/logrotate.d/rkhunter > /dev/null
            print_success "Basic log rotation configured"
        fi
    fi
}

# Setup automated checks
setup_automation() {
    print_info "Setting up automated security checks..."
    
    if [[ "$ENABLE_DAILY_CHECKS" == true ]]; then
        local daily_script="#!/bin/bash
#
# Daily rkhunter security check
# Generated by bashmin on $(date)
#

# Run rkhunter check
/usr/bin/rkhunter $SCAN_MODE --nocolors --skip-keypress"

        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would create daily cron script at $RKHUNTER_CRON_DAILY"
        else
            echo "$daily_script" | sudo tee "$RKHUNTER_CRON_DAILY" > /dev/null
            sudo chmod +x "$RKHUNTER_CRON_DAILY"
            print_success "Daily security checks configured"
        fi
    fi
    
    if [[ "$ENABLE_WEEKLY_UPDATES" == true ]]; then
        local weekly_script="#!/bin/bash
#
# Weekly rkhunter database update
# Generated by bashmin on $(date)
#

# Update rkhunter database
/usr/bin/rkhunter --update --nocolors

# Update file properties
/usr/bin/rkhunter --propupd --nocolors"

        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would create weekly cron script at $RKHUNTER_CRON_WEEKLY"
        else
            echo "$weekly_script" | sudo tee "$RKHUNTER_CRON_WEEKLY" > /dev/null
            sudo chmod +x "$RKHUNTER_CRON_WEEKLY"
            print_success "Weekly database updates configured"
        fi
    fi
}

# Run initial security scan
run_initial_scan() {
    print_info "Running initial security scan..."
    
    if confirm_action "Run an initial rkhunter security scan now?" "Y"; then
        execute_command "sudo rkhunter --check --nocolors --skip-keypress" \
            "Performing initial security scan"
        
        print_info "Scan completed. Check $RKHUNTER_LOG_FILE for detailed results"
        
        if [[ -f "$RKHUNTER_LOG_FILE" ]]; then
            echo ""
            print_info "Recent scan summary:"
            sudo tail -20 "$RKHUNTER_LOG_FILE" | grep -E "(Warning|FAILED|OK)" || true
        fi
    else
        print_info "Skipping initial scan - you can run it manually with: sudo rkhunter --check"
    fi
}

# Show status and usage information
show_status() {
    echo ""
    print_success "rkhunter installation and configuration completed!"
    echo ""
    echo "Configuration Summary:"
    echo "  • Configuration file: $RKHUNTER_CONFIG_FILE"
    echo "  • Log file: $RKHUNTER_LOG_FILE"
    echo "  • Data directory: $RKHUNTER_DATA_DIR"
    echo "  • Temporary directory: $TMPDIR"
    echo "  • Daily checks: $([[ "$ENABLE_DAILY_CHECKS" == true ]] && echo "Enabled" || echo "Disabled")"
    echo "  • Weekly updates: $([[ "$ENABLE_WEEKLY_UPDATES" == true ]] && echo "Enabled" || echo "Disabled")"
    
    if [[ -n "$MAIL_ON_WARNING" ]]; then
        echo "  • Email notifications: $MAIL_ON_WARNING"
    else
        echo "  • Email notifications: Disabled"
    fi
    
    echo ""
    echo "Usage Commands:"
    echo "  • Manual scan:          sudo rkhunter --check"
    echo "  • Update database:      sudo rkhunter --update"
    echo "  • Update file props:    sudo rkhunter --propupd"
    echo "  • View configuration:   sudo rkhunter --config-check"
    echo "  • View log:             sudo tail -f $RKHUNTER_LOG_FILE"
    echo ""
    echo "Security Tips:"
    echo "  • Review scan results regularly in $RKHUNTER_LOG_FILE"
    echo "  • Update the database after system changes: sudo rkhunter --propupd"
    echo "  • Investigate any warnings thoroughly"
    echo "  • Consider additional security measures like fail2ban and ufw"
    echo ""
}

# Main function
main() {
    print_info "Starting rkhunter installation and configuration..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate inputs
    if [[ -n "$MAIL_ON_WARNING" ]]; then
        validate_email "$MAIL_ON_WARNING"
    fi
    
    # Check system compatibility
    check_ubuntu_system
    
    # Show configuration summary
    if [[ "$DRY_RUN" != true ]]; then
        echo ""
        echo "Installation Configuration:"
        echo "  • Daily checks: $([[ "$ENABLE_DAILY_CHECKS" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Weekly updates: $([[ "$ENABLE_WEEKLY_UPDATES" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Auto update DB: $([[ "$AUTO_UPDATE_DB" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Scan mode: $SCAN_MODE"
        echo "  • Temporary directory: $TMPDIR"
        
        if [[ -n "$MAIL_ON_WARNING" ]]; then
            echo "  • Email notifications: $MAIL_ON_WARNING"
        fi
        
        if [[ -n "$DISABLE_TESTS" ]]; then
            echo "  • Disabled tests: $DISABLE_TESTS"
        fi
        
        if [[ -n "$ENABLE_TESTS" ]]; then
            echo "  • Enabled tests: $ENABLE_TESTS"
        fi
        
        echo ""
        
        if ! confirm_action "Proceed with rkhunter installation?" "Y"; then
            print_info "Installation cancelled by user"
            exit 0
        fi
    fi
    
    # Installation steps
    install_rkhunter
    configure_rkhunter
    setup_database
    setup_logrotate
    setup_automation
    
    if [[ "$DRY_RUN" != true ]]; then
        run_initial_scan
        show_status
    else
        print_info "Dry run completed - no changes were made"
    fi
}

# Run main function with all arguments
main "$@"