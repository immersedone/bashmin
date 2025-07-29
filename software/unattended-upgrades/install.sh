#!/bin/bash
#
# Script: software/unattended-upgrades/install.sh
# Description: Install and configure unattended-upgrades for automatic security updates
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
readonly UNATTENDED_UPGRADES_CONFIG="/etc/apt/apt.conf.d/50unattended-upgrades"
readonly PERIODIC_CONFIG="/etc/apt/apt.conf.d/20auto-upgrades"
readonly LOGROTATE_CONFIG="/etc/logrotate.d/unattended-upgrades"
readonly BASHMIN_CONFIG_SOURCE="$PROJECT_ROOT/system/etc/apt/apt.conf.d/50unattended-upgrades"
readonly SERVICE_NAME="unattended-upgrades"

# Configuration variables
ENABLE_AUTOMATIC_REBOOT=false
REBOOT_TIME="02:00"
ENABLE_EMAIL_NOTIFICATIONS=false
EMAIL_ADDRESS=""
MAIL_ONLY_ON_ERROR=true
ENABLE_KERNEL_CLEANUP=true
ENABLE_DEPENDENCY_CLEANUP=true
DOWNLOAD_LIMIT=""
ENABLE_SECURITY_ONLY=false
BLACKLIST_PACKAGES=()
CUSTOM_ORIGINS=()
UPDATE_INTERVAL="1"
UPGRADE_INTERVAL="1"
AUTOCLEAN_INTERVAL="7"
FORCE_INSTALL=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --enable-reboot)
            ENABLE_AUTOMATIC_REBOOT=true
            shift
            ;;
        --reboot-time)
            REBOOT_TIME="$2"
            ENABLE_AUTOMATIC_REBOOT=true
            shift 2
            ;;
        --email)
            EMAIL_ADDRESS="$2"
            ENABLE_EMAIL_NOTIFICATIONS=true
            shift 2
            ;;
        --mail-always)
            MAIL_ONLY_ON_ERROR=false
            shift
            ;;
        --no-kernel-cleanup)
            ENABLE_KERNEL_CLEANUP=false
            shift
            ;;
        --no-dependency-cleanup)
            ENABLE_DEPENDENCY_CLEANUP=false
            shift
            ;;
        --download-limit)
            DOWNLOAD_LIMIT="$2"
            shift 2
            ;;
        --security-only)
            ENABLE_SECURITY_ONLY=true
            shift
            ;;
        --blacklist)
            IFS=',' read -ra BLACKLIST_PACKAGES <<< "$2"
            shift 2
            ;;
        --add-origin)
            CUSTOM_ORIGINS+=("$2")
            shift 2
            ;;
        --update-interval)
            UPDATE_INTERVAL="$2"
            shift 2
            ;;
        --upgrade-interval)
            UPGRADE_INTERVAL="$2"
            shift 2
            ;;
        --autoclean-interval)
            AUTOCLEAN_INTERVAL="$2"
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

Install and configure unattended-upgrades for automatic security updates.

OPTIONS:
    --enable-reboot             Enable automatic reboot when required
    --reboot-time TIME          Set reboot time (default: $REBOOT_TIME, enables reboot)
    --email EMAIL               Enable email notifications to this address
    --mail-always               Send email for all upgrades (default: errors only)
    --no-kernel-cleanup         Disable automatic kernel package removal
    --no-dependency-cleanup     Disable automatic unused dependency removal
    --download-limit SPEED      Limit download speed (e.g., 70kb/sec)
    --security-only             Only install security updates
    --blacklist PACKAGES        Comma-separated list of packages to exclude
    --add-origin ORIGIN         Add custom update origin (can be used multiple times)
    --update-interval DAYS      Update package lists every N days (default: $UPDATE_INTERVAL)
    --upgrade-interval DAYS     Upgrade packages every N days (default: $UPGRADE_INTERVAL)
    --autoclean-interval DAYS   Clean package cache every N days (default: $AUTOCLEAN_INTERVAL)
    --force                     Force reinstall even if already configured
    --quiet                     Suppress non-essential output
    --verbose                   Enable verbose output
    --dry-run                   Show what would be configured without executing
    -h, --help                  Show this help message

SECURITY MODES:
    Default Mode:               Install security updates + regular updates from main repos
    --security-only             Only install security updates, skip regular updates

EMAIL NOTIFICATIONS:
    --email user@domain.com     Enable email notifications (requires working mail setup)
    --mail-always               Send emails for all upgrades (default: errors only)

AUTOMATIC REBOOT:
    --enable-reboot             Allow automatic reboot when kernel updates require it
    --reboot-time 02:00         Set specific reboot time (24-hour format)

EXAMPLES:
    # Basic security-only setup
    $0 --security-only

    # Full automation with notifications
    $0 --email admin@example.com --enable-reboot --reboot-time 03:00

    # Conservative setup with manual reboots
    $0 --email ops@company.com --no-kernel-cleanup

    # Custom blacklist and bandwidth limiting
    $0 --blacklist nginx,apache2,mysql-server --download-limit 100

    # Development server (security only, no reboots)
    $0 --security-only --blacklist nginx,php --no-dependency-cleanup

NOTES:
    - Requires sudo privileges
    - Installs and configures unattended-upgrades package
    - Creates proper log rotation configuration
    - Excludes web servers (nginx, apache2) from automatic updates by default
    - Email notifications require a working mail system (postfix, sendmail, etc.)
    - Automatic reboots should be used carefully on production systems

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
        DISTRO_CODENAME=$VERSION_CODENAME
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    # Check if Ubuntu/Debian
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_error "This script only supports Ubuntu and Debian systems"
        exit 1
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Detected: $OS $VER ($DISTRO_CODENAME)"
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
    
    # Check if already configured and not forcing
    if [[ -f "$UNATTENDED_UPGRADES_CONFIG" && "$FORCE_INSTALL" == false ]]; then
        print_error "Unattended-upgrades appears to be already configured"
        print_info "Use --force to reconfigure"
        exit 1
    fi
    
    # Validate email address if provided
    if [[ -n "$EMAIL_ADDRESS" && ! "$EMAIL_ADDRESS" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        print_error "Invalid email address: $EMAIL_ADDRESS"
        exit 1
    fi
    
    # Validate reboot time format
    if [[ ! "$REBOOT_TIME" =~ ^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        print_error "Invalid reboot time format: $REBOOT_TIME (use HH:MM format)"
        exit 1
    fi
    
    # Validate intervals
    for interval in "$UPDATE_INTERVAL" "$UPGRADE_INTERVAL" "$AUTOCLEAN_INTERVAL"; do
        if [[ ! "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]]; then
            print_error "Invalid interval value: $interval (must be positive integer)"
            exit 1
        fi
    done
}

# Function to install unattended-upgrades package
install_package() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install unattended-upgrades package"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installing unattended-upgrades package..."
    fi
    
    # Update package cache
    sudo apt-get update -qq
    
    # Install unattended-upgrades
    sudo apt-get install -y unattended-upgrades
    
    # Install mail packages if email notifications enabled
    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then
        sudo apt-get install -y mailutils || {
            print_warning "Could not install mail utilities. Email notifications may not work."
        }
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Unattended-upgrades package installed"
    fi
}

# Function to configure unattended-upgrades
configure_unattended_upgrades() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure unattended-upgrades settings"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring unattended-upgrades..."
    fi
    
    # Backup existing configuration
    if [[ -f "$UNATTENDED_UPGRADES_CONFIG" ]]; then
        sudo cp "$UNATTENDED_UPGRADES_CONFIG" "$UNATTENDED_UPGRADES_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Start with bashmin template if available, otherwise create from scratch
    if [[ -f "$BASHMIN_CONFIG_SOURCE" ]]; then
        sudo cp "$BASHMIN_CONFIG_SOURCE" "$UNATTENDED_UPGRADES_CONFIG"
    else
        create_base_config
    fi
    
    # Configure email settings
    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then
        sudo sed -i "s/\${USER_EMAIL}/$EMAIL_ADDRESS/g" "$UNATTENDED_UPGRADES_CONFIG"
        sudo sed -i "s|//Unattended-Upgrade::Mail|Unattended-Upgrade::Mail|g" "$UNATTENDED_UPGRADES_CONFIG"
        
        if [[ "$MAIL_ONLY_ON_ERROR" == true ]]; then
            sudo sed -i 's|Unattended-Upgrade::MailOnlyOnError ".*"|Unattended-Upgrade::MailOnlyOnError "true"|' "$UNATTENDED_UPGRADES_CONFIG"
        else
            sudo sed -i 's|Unattended-Upgrade::MailOnlyOnError ".*"|Unattended-Upgrade::MailOnlyOnError "false"|' "$UNATTENDED_UPGRADES_CONFIG"
        fi
    else
        # Remove email configuration
        sudo sed -i '/Unattended-Upgrade::Mail/d' "$UNATTENDED_UPGRADES_CONFIG"
    fi
    
    # Configure automatic reboot
    if [[ "$ENABLE_AUTOMATIC_REBOOT" == true ]]; then
        sudo sed -i "s|//Unattended-Upgrade::Automatic-Reboot.*|Unattended-Upgrade::Automatic-Reboot \"true\";|" "$UNATTENDED_UPGRADES_CONFIG"
        sudo sed -i "s|//Unattended-Upgrade::Automatic-Reboot-Time.*|Unattended-Upgrade::Automatic-Reboot-Time \"$REBOOT_TIME\";|" "$UNATTENDED_UPGRADES_CONFIG"
    else
        sudo sed -i "s|//Unattended-Upgrade::Automatic-Reboot.*|Unattended-Upgrade::Automatic-Reboot \"false\";|" "$UNATTENDED_UPGRADES_CONFIG"
    fi
    
    # Configure kernel cleanup
    if [[ "$ENABLE_KERNEL_CLEANUP" == true ]]; then
        sudo sed -i 's|Unattended-Upgrade::Remove-Unused-Kernel-Packages ".*"|Unattended-Upgrade::Remove-Unused-Kernel-Packages "true"|' "$UNATTENDED_UPGRADES_CONFIG"
    else
        sudo sed -i 's|Unattended-Upgrade::Remove-Unused-Kernel-Packages ".*"|Unattended-Upgrade::Remove-Unused-Kernel-Packages "false"|' "$UNATTENDED_UPGRADES_CONFIG"
    fi
    
    # Configure dependency cleanup
    if [[ "$ENABLE_DEPENDENCY_CLEANUP" == true ]]; then
        sudo sed -i 's|Unattended-Upgrade::Remove-Unused-Dependencies ".*"|Unattended-Upgrade::Remove-Unused-Dependencies "true"|' "$UNATTENDED_UPGRADES_CONFIG"
    else
        sudo sed -i 's|Unattended-Upgrade::Remove-Unused-Dependencies ".*"|Unattended-Upgrade::Remove-Unused-Dependencies "false"|' "$UNATTENDED_UPGRADES_CONFIG"
    fi
    
    # Configure download limit
    if [[ -n "$DOWNLOAD_LIMIT" ]]; then
        echo "Acquire::http::Dl-Limit \"$DOWNLOAD_LIMIT\";" | sudo tee -a "$UNATTENDED_UPGRADES_CONFIG" >/dev/null
    fi
    
    # Configure security-only mode
    configure_update_origins
    
    # Add custom blacklisted packages
    add_blacklisted_packages
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Unattended-upgrades configuration created"
    fi
}

# Function to create base configuration if template doesn't exist
create_base_config() {
    cat << EOF | sudo tee "$UNATTENDED_UPGRADES_CONFIG" >/dev/null
// Automatically upgrade packages from these (origin:archive) pairs
Unattended-Upgrade::Allowed-Origins {
        "\${distro_id}:\${distro_codename}";
        "\${distro_id}:\${distro_codename}-security";
        "\${distro_id}ESM:\${distro_codename}";
        "\${distro_id}:\${distro_codename}-updates";
};

// List of packages to not update (regexp are supported)
Unattended-Upgrade::Package-Blacklist {
        "nginx";
        "varnish";
        "apache2";
};

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::MailOnlyOnError "true";
EOF
}

# Function to configure update origins
configure_update_origins() {
    if [[ "$ENABLE_SECURITY_ONLY" == true ]]; then
        # Create security-only configuration
        sudo sed -i '/Unattended-Upgrade::Allowed-Origins/,/};/c\
Unattended-Upgrade::Allowed-Origins {\
        "${distro_id}:${distro_codename}-security";\
        "${distro_id}ESM:${distro_codename}";\
};' "$UNATTENDED_UPGRADES_CONFIG"
    fi
    
    # Add custom origins
    for origin in "${CUSTOM_ORIGINS[@]}"; do
        sudo sed -i "/Unattended-Upgrade::Allowed-Origins {/a\\        \"$origin\";" "$UNATTENDED_UPGRADES_CONFIG"
    done
}

# Function to add blacklisted packages
add_blacklisted_packages() {
    for package in "${BLACKLIST_PACKAGES[@]}"; do
        # Add to blacklist section
        sudo sed -i "/Unattended-Upgrade::Package-Blacklist {/a\\        \"$package\";" "$UNATTENDED_UPGRADES_CONFIG"
    done
}

# Function to configure automatic updates
configure_periodic_updates() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure periodic update settings"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring periodic update settings..."
    fi
    
    # Create or update periodic configuration
    cat << EOF | sudo tee "$PERIODIC_CONFIG" >/dev/null
// Enable the update/upgrade script
APT::Periodic::Enable "1";

// Update package lists every $UPDATE_INTERVAL day(s)
APT::Periodic::Update-Package-Lists "$UPDATE_INTERVAL";

// Download and install upgrades every $UPGRADE_INTERVAL day(s)
APT::Periodic::Unattended-Upgrade "$UPGRADE_INTERVAL";

// Clean downloaded packages every $AUTOCLEAN_INTERVAL day(s)
APT::Periodic::AutocleanInterval "$AUTOCLEAN_INTERVAL";

// Automatically download upgrades
APT::Periodic::Download-Upgradeable-Packages "1";

// Enable verbose logging for debugging
APT::Periodic::Verbose "2";
EOF
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Periodic update configuration created"
    fi
}

# Function to setup log rotation
setup_log_rotation() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would setup log rotation for unattended-upgrades"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Setting up log rotation..."
    fi
    
    # Check if bashmin logrotate config exists
    local bashmin_logrotate="$PROJECT_ROOT/system/etc/logrotate.d/unattended-upgrades"
    
    if [[ -f "$bashmin_logrotate" ]]; then
        sudo cp "$bashmin_logrotate" "$LOGROTATE_CONFIG"
    else
        # Create log rotation configuration
        cat << EOF | sudo tee "$LOGROTATE_CONFIG" >/dev/null
/var/log/unattended-upgrades/unattended-upgrades.log
/var/log/unattended-upgrades/unattended-upgrades-dpkg.log
/var/log/unattended-upgrades/unattended-upgrades-shutdown.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 root root
    postrotate
        systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Log rotation configured"
    fi
}

# Function to enable and start service
enable_service() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would enable and start unattended-upgrades service"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Enabling unattended-upgrades service..."
    fi
    
    # Enable and start the service
    sudo systemctl enable unattended-upgrades
    sudo systemctl start unattended-upgrades
    
    # Verify service is running
    if ! systemctl is-active --quiet unattended-upgrades; then
        print_warning "Unattended-upgrades service is not running"
        print_info "Check status: sudo systemctl status unattended-upgrades"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Unattended-upgrades service enabled and started"
    fi
}

# Function to test configuration
test_configuration() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test unattended-upgrades configuration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Testing configuration..."
    fi
    
    # Test unattended-upgrades configuration
    if sudo unattended-upgrades --dry-run >/dev/null 2>&1; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Configuration test passed"
        fi
    else
        print_warning "Configuration test failed"
        print_info "Run manually: sudo unattended-upgrades --dry-run"
    fi
    
    # Check if apt update works
    if sudo apt-get update -qq >/dev/null 2>&1; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Package list update successful"
        fi
    else
        print_warning "Package list update failed"
    fi
}

# Function to show completion summary
show_completion_summary() {
    if [[ "$QUIET" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo
    print_success "Unattended-upgrades installation completed successfully! 🚀"
    echo
    print_info "=== Configuration Summary ==="
    cat << EOF
Security Updates:    Enabled
Regular Updates:     $(if [[ "$ENABLE_SECURITY_ONLY" == true ]]; then echo "Disabled (security-only mode)"; else echo "Enabled"; fi)
Automatic Reboot:    $(if [[ "$ENABLE_AUTOMATIC_REBOOT" == true ]]; then echo "Enabled (at $REBOOT_TIME)"; else echo "Disabled"; fi)
Email Notifications: $(if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then echo "Enabled ($EMAIL_ADDRESS)"; else echo "Disabled"; fi)
Kernel Cleanup:      $(if [[ "$ENABLE_KERNEL_CLEANUP" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
Dependency Cleanup:  $(if [[ "$ENABLE_DEPENDENCY_CLEANUP" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
Update Interval:     Every $UPDATE_INTERVAL day(s)
Upgrade Interval:    Every $UPGRADE_INTERVAL day(s)
AutoClean Interval:  Every $AUTOCLEAN_INTERVAL day(s)

EOF

    print_info "=== Service Information ==="
    cat << EOF
Status:              $(systemctl is-active unattended-upgrades)
Enabled:             $(systemctl is-enabled unattended-upgrades)
Config File:         $UNATTENDED_UPGRADES_CONFIG
Periodic Config:     $PERIODIC_CONFIG
Log Directory:       /var/log/unattended-upgrades/

EOF

    print_info "=== Protected Packages ==="
    echo "The following packages are excluded from automatic updates:"
    if [[ -f "$UNATTENDED_UPGRADES_CONFIG" ]]; then
        grep -A 10 "Package-Blacklist" "$UNATTENDED_UPGRADES_CONFIG" | grep '"' | sed 's/.*"\([^"]*\)".*/  - \1/' || echo "  - nginx, apache2, varnish (default)"
    fi
    echo

    if [[ ${#BLACKLIST_PACKAGES[@]} -gt 0 ]]; then
        echo "Custom blacklisted packages:"
        for pkg in "${BLACKLIST_PACKAGES[@]}"; do
            echo "  - $pkg"
        done
        echo
    fi

    print_info "=== Management Commands ==="
    cat << EOF
View status:         sudo systemctl status unattended-upgrades
View logs:           sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log
Test run:            sudo unattended-upgrades --dry-run
Force run:           sudo unattended-upgrades --debug
Edit config:         sudo nano $UNATTENDED_UPGRADES_CONFIG

EOF

    print_info "=== Monitoring ==="
    cat << EOF
Check last run:      ls -la /var/log/unattended-upgrades/
View upgrade history: cat /var/log/unattended-upgrades/unattended-upgrades.log
Check pending:       apt list --upgradable
Manual update:       sudo apt update && sudo apt list --upgradable

EOF

    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then
        print_info "=== Email Notifications ==="
        cat << EOF
Email Address:       $EMAIL_ADDRESS
Notification Mode:   $(if [[ "$MAIL_ONLY_ON_ERROR" == true ]]; then echo "Errors only"; else echo "All upgrades"; fi)
Test Email:          echo "Test" | mail -s "Unattended-upgrades test" $EMAIL_ADDRESS

EOF
    fi

    print_info "=== Security Notes ==="
    cat << EOF
• Automatic updates are enabled for security patches
• Web servers (nginx, apache2) are excluded by default to prevent service disruption
• Kernel updates will require manual reboot unless --enable-reboot was used
• Monitor logs regularly to ensure updates are applied successfully
• Consider testing updates on staging environment first for critical systems

EOF
    
    print_info "🔒 Your system will now automatically receive security updates!"
}

# Main function
main() {
    # Detect system
    detect_system
    
    if [[ "$QUIET" == false ]]; then
        show_script_header "Unattended-Upgrades Installation"
        print_info "Configuring automatic security updates for $OS $VER"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show configuration plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuration plan:"
        print_info "  Security Updates: Enabled"
        print_info "  Regular Updates: $(if [[ "$ENABLE_SECURITY_ONLY" == true ]]; then echo "Disabled"; else echo "Enabled"; fi)"
        print_info "  Automatic Reboot: $(if [[ "$ENABLE_AUTOMATIC_REBOOT" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
        print_info "  Email Notifications: $(if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
        print_info "  Update Interval: $UPDATE_INTERVAL day(s)"
        print_info "  Upgrade Interval: $UPGRADE_INTERVAL day(s)"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with configuration?" "Y"; then
            print_info "Configuration cancelled"
            exit 0
        fi
    fi
    
    # Execute installation steps
    install_package
    configure_unattended_upgrades
    configure_periodic_updates
    setup_log_rotation
    enable_service
    test_configuration
    
    # Show completion summary
    show_completion_summary
}

# Run main function
main "$@"
