#!/bin/bash
#
# Script: security/lynis/install.sh
# Description: Install and configure Lynis security auditing system
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
readonly LYNIS_USER="lynis"
readonly LYNIS_GROUP="lynis"
readonly LYNIS_HOME="/opt/lynis"
readonly LYNIS_CONFIG_DIR="/etc/lynis"
readonly BASHMIN_LOG_DIR="/var/log/bashmin"
readonly BASHMIN_LYNIS_DIR="/var/log/bashmin/security/lynis"
readonly LYNIS_DATA_DIR="/var/lib/lynis"
readonly LYNIS_REPORTS_DIR="$BASHMIN_LYNIS_DIR/reports"
readonly LYNIS_REPO="https://github.com/CISOfy/lynis.git"
readonly LYNIS_VERSION="main"

# Configuration variables
INSTALL_METHOD="git"
ENABLE_CRON=true
CRON_SCHEDULE="weekly"
AUDIT_FREQUENCY="daily"
AUTO_UPDATE=true
ENABLE_REPORTING=true
ENABLE_NOTIFICATIONS=true
NOTIFICATION_EMAIL=""
SLACK_WEBHOOK=""
ENABLE_COMPLIANCE_SCANNING=true
CUSTOM_PROFILE=""
AUDIT_CATEGORIES="all"
REPORT_FORMAT="html"
HARDENING_INDEX_THRESHOLD=75
PENTEST_MODE=false
DEVELOPER_MODE=false
UPLOAD_SERVER=""
LICENSE_KEY=""
FORCE=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Help function
show_help() {
    cat << 'EOF'
Lynis Security Auditing System Installation

DESCRIPTION:
    Comprehensive installation and configuration of Lynis security auditing framework.
    Provides automated security scanning, compliance checking, and vulnerability assessment
    with integrated reporting and notifications.

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    Installation Configuration:
    --install-method METHOD     Installation method: git, package, manual [git]
    --lynis-version VERSION     Lynis version/branch to install [main]
    --custom-profile PATH       Path to custom Lynis profile configuration
    --license-key KEY           Commercial license key for Lynis Enterprise
    
    Audit Configuration:
    --audit-categories CATS     Audit categories: all, system, network, crypto, etc [all]
    --audit-frequency FREQ      Audit frequency: daily, weekly, monthly [daily]
    --hardening-index-threshold NUM  Minimum hardening index threshold [75]
    --enable-compliance         Enable compliance scanning (PCI-DSS, HIPAA, etc) [default]
    --disable-compliance        Disable compliance scanning
    --pentest-mode             Enable penetration testing mode
    --developer-mode           Enable developer mode for custom tests
    
    Scheduling & Automation:
    --enable-cron              Enable automated scheduling [default]
    --disable-cron             Disable automated scheduling
    --cron-schedule SCHEDULE   Cron schedule: daily, weekly, monthly [weekly]
    --auto-update              Enable automatic Lynis updates [default]
    --disable-auto-update      Disable automatic updates
    
    Reporting & Output:
    --enable-reporting         Enable comprehensive reporting [default]
    --disable-reporting        Disable reporting features
    --report-format FORMAT     Report format: html, json, xml, text [html]
    --reports-retention DAYS   Report retention period in days [90]
    
    Notifications:
    --enable-notifications     Enable audit notifications [default]
    --disable-notifications    Disable notifications
    --notification-email EMAIL Email for audit notifications
    --slack-webhook URL        Slack webhook for notifications
    --upload-server URL        Upload server for centralized reporting
    
    Security Features:
    --dedicated-user           Create dedicated lynis user account [default]
    --secure-permissions       Set restrictive file permissions
    --audit-logging           Enable comprehensive audit logging
    --encrypted-reports       Enable report encryption
    
    Control Options:
    --force                    Force reinstallation of Lynis
    --dry-run                  Show what would be done without making changes
    --verbose                  Enable verbose output
    --quiet                    Suppress non-essential output
    --help                     Show this help message

EXAMPLES:
    Basic Installation:
    ./install.sh

    Enterprise Setup:
    ./install.sh --license-key XXXX-XXXX-XXXX-XXXX \\
        --notification-email security@company.com \\
        --enable-compliance --audit-frequency daily

    High-Security Configuration:
    ./install.sh --pentest-mode --hardening-index-threshold 90 \\
        --audit-categories "system,network,crypto,malware" \\
        --secure-permissions --encrypted-reports

    Development Environment:
    ./install.sh --developer-mode --custom-profile /path/to/profile \\
        --disable-cron --audit-frequency manual

    Compliance Focused:
    ./install.sh --enable-compliance --report-format json \\
        --upload-server https://compliance.company.com \\
        --notification-email compliance@company.com

AUDIT CATEGORIES:
    • system        - System configuration and hardening
    • network       - Network configuration and security
    • crypto        - Cryptographic implementations
    • authentication - Authentication mechanisms
    • authorization - Authorization and access control
    • accounting    - Logging and auditing
    • storage       - Storage security
    • malware       - Malware detection capabilities
    • firewall      - Firewall configuration
    • webserver     - Web server security
    • database      - Database security
    • ssh           - SSH configuration
    • containers    - Container security (Docker, etc.)
    • virtualization - Virtualization security

COMPLIANCE FRAMEWORKS:
    • PCI-DSS       - Payment Card Industry Data Security Standard
    • HIPAA         - Health Insurance Portability and Accountability Act
    • SOX           - Sarbanes-Oxley Act
    • ISO27001      - Information Security Management
    • NIST          - National Institute of Standards and Technology
    • CIS           - Center for Internet Security
    • GDPR          - General Data Protection Regulation

SECURITY FEATURES:
    • Comprehensive system security scanning
    • Vulnerability assessment and reporting
    • Compliance framework validation
    • Security hardening recommendations
    • Automated security monitoring
    • Customizable audit profiles
    • Integration with SIEM systems
    • Encrypted reporting and data protection

INTEGRATION:
    • bashmin Security Suite: UFW, fail2ban, ClamAV, SSL management
    • System Monitoring: Integration with system health monitoring
    • Log Management: Structured logging with automatic rotation
    • Notification Systems: Email, Slack, and custom webhook support

FILES CREATED:
    /opt/lynis/                 - Lynis installation directory
    /etc/lynis/                 - Configuration files
    /var/lib/lynis/             - Lynis data and state files
    /var/log/bashmin/security/lynis/ - Audit reports and logs
    /usr/local/bin/lynis-manage - Lynis management utility

DEPENDENCIES:
    • git (for git installation method)
    • curl or wget
    • openssl
    • awk, sed, grep
    • systemd (for service management)

For more information about bashmin security auditing:
    /var/www/vhosts/bashmin/security/lynis/README.md

EOF
}

# Logging functions
log_lynis() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure log directory exists
    mkdir -p "$BASHMIN_LYNIS_DIR"
    
    # Log to bashmin Lynis log
    echo "[$timestamp] [$level] $message" >> "$BASHMIN_LYNIS_DIR/install.log"
    
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
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}

detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Validation functions
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_lynis "ERROR" "Invalid email address: $email"
        return 1
    fi
    return 0
}

validate_webhook_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https://hooks\.slack\.com/services/ ]]; then
        log_lynis "ERROR" "Invalid Slack webhook URL format"
        return 1
    fi
    return 0
}

validate_audit_categories() {
    local categories="$1"
    local valid_cats="all system network crypto authentication authorization accounting storage malware firewall webserver database ssh containers virtualization"
    
    IFS=',' read -ra CAT_ARRAY <<< "$categories"
    for cat in "${CAT_ARRAY[@]}"; do
        cat=$(echo "$cat" | xargs)  # trim whitespace
        if [[ "$cat" == "all" ]]; then
            continue
        fi
        if ! echo "$valid_cats" | grep -q "\b$cat\b"; then
            log_lynis "ERROR" "Invalid audit category: $cat"
            log_lynis "INFO" "Valid categories: $valid_cats"
            return 1
        fi
    done
    return 0
}

# User management functions
create_lynis_user() {
    log_lynis "INFO" "Creating dedicated Lynis user account"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_lynis "INFO" "[DRY RUN] Would create user: $LYNIS_USER"
        return 0
    fi
    
    # Create group if it doesn't exist
    if ! getent group "$LYNIS_GROUP" >/dev/null 2>&1; then
        groupadd --system "$LYNIS_GROUP"
        log_lynis "INFO" "Created group: $LYNIS_GROUP"
    fi
    
    # Create user if it doesn't exist
    if ! getent passwd "$LYNIS_USER" >/dev/null 2>&1; then
        useradd --system \
                --gid "$LYNIS_GROUP" \
                --home-dir "$LYNIS_HOME" \
                --shell /bin/bash \
                --comment "Lynis Security Auditing" \
                "$LYNIS_USER"
        
        log_lynis "INFO" "Created user: $LYNIS_USER"
    else
        log_lynis "INFO" "User $LYNIS_USER already exists"
    fi
    
    # Create home directory
    mkdir -p "$LYNIS_HOME"
    chown "$LYNIS_USER:$LYNIS_GROUP" "$LYNIS_HOME"
    chmod 750 "$LYNIS_HOME"
}

# Installation functions
install_dependencies() {
    local os_id=$(detect_os)
    local pkg_mgr=$(detect_package_manager)
    
    log_lynis "INFO" "Installing dependencies for $os_id using $pkg_mgr"
    
    local packages=""
    
    case "$pkg_mgr" in
        apt)
            packages="git curl wget openssl awk sed grep coreutils util-linux procps"
            if [[ "$DRY_RUN" == "false" ]]; then
                apt-get update
                apt-get install -y $packages
            else
                log_lynis "INFO" "[DRY RUN] Would install packages: $packages"
            fi
            ;;
        yum|dnf)
            packages="git curl wget openssl gawk sed grep coreutils util-linux procps-ng"
            if [[ "$DRY_RUN" == "false" ]]; then
                $pkg_mgr install -y $packages
            else
                log_lynis "INFO" "[DRY RUN] Would install packages: $packages"
            fi
            ;;
        *)
            log_lynis "WARN" "Unknown package manager: $pkg_mgr"
            log_lynis "INFO" "Please install dependencies manually: git, curl, wget, openssl"
            ;;
    esac
}

install_lynis_git() {
    log_lynis "INFO" "Installing Lynis from Git repository"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_lynis "INFO" "[DRY RUN] Would clone Lynis repository to $LYNIS_HOME"
        return 0
    fi
    
    # Remove existing installation if force is enabled
    if [[ "$FORCE" == "true" ]] && [[ -d "$LYNIS_HOME" ]]; then
        log_lynis "INFO" "Removing existing Lynis installation"
        rm -rf "$LYNIS_HOME"
    fi
    
    # Create parent directory
    mkdir -p "$(dirname "$LYNIS_HOME")"
    
    # Clone repository
    if [[ ! -d "$LYNIS_HOME/.git" ]]; then
        git clone "$LYNIS_REPO" "$LYNIS_HOME"
        cd "$LYNIS_HOME"
        git checkout "$LYNIS_VERSION"
        log_lynis "INFO" "Lynis cloned successfully"
    else
        log_lynis "INFO" "Lynis repository already exists"
        if [[ "$AUTO_UPDATE" == "true" ]]; then
            cd "$LYNIS_HOME"
            git pull origin "$LYNIS_VERSION"
            log_lynis "INFO" "Lynis updated to latest version"
        fi
    fi
    
    # Set ownership and permissions
    chown -R "$LYNIS_USER:$LYNIS_GROUP" "$LYNIS_HOME"
    chmod -R 750 "$LYNIS_HOME"
    chmod +x "$LYNIS_HOME/lynis"
}

install_lynis_package() {
    local pkg_mgr=$(detect_package_manager)
    
    log_lynis "INFO" "Installing Lynis from package repository"
    
    case "$pkg_mgr" in
        apt)
            if [[ "$DRY_RUN" == "false" ]]; then
                # Add CISOfy repository
                curl -fsSL https://packages.cisofy.com/keys/cisofy-software-public.key | apt-key add -
                echo "deb https://packages.cisofy.com/community/lynis/deb/ stable main" > /etc/apt/sources.list.d/cisofy-lynis.list
                apt-get update
                apt-get install -y lynis
            else
                log_lynis "INFO" "[DRY RUN] Would install Lynis package via apt"
            fi
            ;;
        yum|dnf)
            if [[ "$DRY_RUN" == "false" ]]; then
                # Add CISOfy repository
                cat > /etc/yum.repos.d/cisofy-lynis.repo << 'EOF'
[lynis]
name=CISOfy Software - Lynis package
baseurl=https://packages.cisofy.com/community/lynis/rpm/
enabled=1
gpgkey=https://packages.cisofy.com/keys/cisofy-software-public.key
gpgcheck=1
EOF
                $pkg_mgr install -y lynis
            else
                log_lynis "INFO" "[DRY RUN] Would install Lynis package via $pkg_mgr"
            fi
            ;;
        *)
            log_lynis "ERROR" "Package installation not supported for $pkg_mgr"
            return 1
            ;;
    esac
}

# Configuration functions
configure_lynis() {
    log_lynis "INFO" "Configuring Lynis settings"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_lynis "INFO" "[DRY RUN] Would configure Lynis settings"
        return 0
    fi
    
    # Create configuration directory
    mkdir -p "$LYNIS_CONFIG_DIR"
    mkdir -p "$LYNIS_DATA_DIR"
    mkdir -p "$BASHMIN_LYNIS_DIR"
    mkdir -p "$LYNIS_REPORTS_DIR"
    
    # Create main configuration file
    cat > "$LYNIS_CONFIG_DIR/default.prf" << EOF
# Lynis Configuration Profile
# Generated by bashmin Lynis installer

#################################################################################
# Basic Configuration
#################################################################################

# Skip specific tests (if needed)
# skip-test=AUTH-9208
# skip-test=FILE-6310

# Include specific tests only
# include-test=AUTH-*
# include-test=FILE-*

#################################################################################
# Auditing Options
#################################################################################

# Enable colors for output
colors=yes

# Enable logging
log-file=/var/log/bashmin/security/lynis/lynis.log

# Report file location
report-file=/var/log/bashmin/security/lynis/reports/lynis-report.dat

# Set log level (DEBUG, INFO, WARNING, ERROR)
log-level=INFO

# Compliance standards to check
compliance-standards=pci-dss,hipaa,iso27001,nist

#################################################################################
# Security Settings
#################################################################################

# Enable warnings for security issues
warnings=yes

# Show suggestions for improvement
suggestions=yes

# Enable quick scan mode (faster but less comprehensive)
# quick=yes

# Enable verbose output
# verbose=yes

#################################################################################
# Pentesting Mode
#################################################################################

# Enable pentesting mode (more aggressive testing)
EOF
    
    if [[ "$PENTEST_MODE" == "true" ]]; then
        echo "pentest=yes" >> "$LYNIS_CONFIG_DIR/default.prf"
    fi
    
    if [[ "$DEVELOPER_MODE" == "true" ]]; then
        echo "developer=yes" >> "$LYNIS_CONFIG_DIR/default.prf"
    fi
    
    cat >> "$LYNIS_CONFIG_DIR/default.prf" << EOF

#################################################################################
# Reporting Configuration
#################################################################################

# Report format
report-format=$REPORT_FORMAT

# Upload data to central server
EOF
    
    if [[ -n "$UPLOAD_SERVER" ]]; then
        echo "upload-server=$UPLOAD_SERVER" >> "$LYNIS_CONFIG_DIR/default.prf"
    fi
    
    if [[ -n "$LICENSE_KEY" ]]; then
        echo "license-key=$LICENSE_KEY" >> "$LYNIS_CONFIG_DIR/default.prf"
    fi
    
    cat >> "$LYNIS_CONFIG_DIR/default.prf" << EOF

#################################################################################
# Plugin Configuration
#################################################################################

# Enable all plugins
plugin=enabled

# Plugin directory
plugin-dir=/usr/share/lynis/plugins

#################################################################################
# Custom Configuration
#################################################################################
EOF
    
    # Copy custom profile if provided
    if [[ -n "$CUSTOM_PROFILE" ]] && [[ -f "$CUSTOM_PROFILE" ]]; then
        cat "$CUSTOM_PROFILE" >> "$LYNIS_CONFIG_DIR/default.prf"
        log_lynis "INFO" "Custom profile configuration appended"
    fi
    
    # Set ownership and permissions
    chown -R "$LYNIS_USER:$LYNIS_GROUP" "$LYNIS_CONFIG_DIR" "$LYNIS_DATA_DIR" "$BASHMIN_LYNIS_DIR"
    chmod -R 640 "$LYNIS_CONFIG_DIR"/*
    chmod 750 "$LYNIS_CONFIG_DIR" "$LYNIS_DATA_DIR" "$BASHMIN_LYNIS_DIR"
}

create_lynis_wrapper() {
    log_lynis "INFO" "Creating Lynis management wrapper"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_lynis "INFO" "[DRY RUN] Would create Lynis wrapper script"
        return 0
    fi
    
    cat > /usr/local/bin/lynis-manage << 'EOF'
#!/bin/bash
#
# Lynis Management Wrapper
# Provides easy access to Lynis functionality with bashmin integration
#

set -euo pipefail

LYNIS_HOME="/opt/lynis"
LYNIS_CONFIG="/etc/lynis/default.prf"
LYNIS_REPORTS="/var/log/bashmin/security/lynis/reports"
LYNIS_LOG="/var/log/bashmin/security/lynis"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    cat << 'HELP'
Lynis Management Utility

USAGE:
    lynis-manage [COMMAND] [OPTIONS]

COMMANDS:
    audit [categories]      Run security audit (default: system audit)
    update                  Update Lynis to latest version
    report                  Generate and display latest report
    status                  Show Lynis installation status
    config                  Show current configuration
    compliance [framework]  Run compliance check
    benchmark               Run security benchmark
    help                    Show this help message

AUDIT CATEGORIES:
    system                  System configuration and hardening
    network                 Network security configuration
    crypto                  Cryptographic implementations
    authentication          Authentication mechanisms
    all                     Run comprehensive audit (default)

COMPLIANCE FRAMEWORKS:
    pci-dss                 Payment Card Industry Data Security Standard
    hipaa                   Health Insurance Portability and Accountability Act
    iso27001               Information Security Management
    nist                   National Institute of Standards and Technology

EXAMPLES:
    lynis-manage audit                    # Full system audit
    lynis-manage audit system            # System-specific audit
    lynis-manage compliance pci-dss      # PCI-DSS compliance check
    lynis-manage report                   # View latest report
    lynis-manage update                   # Update Lynis

HELP
}

run_audit() {
    local categories="${1:-all}"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local report_file="$LYNIS_REPORTS/audit_${timestamp}.dat"
    
    echo -e "${BLUE}[INFO]${NC} Starting Lynis security audit..."
    echo -e "${BLUE}[INFO]${NC} Categories: $categories"
    echo -e "${BLUE}[INFO]${NC} Report will be saved to: $report_file"
    
    # Ensure report directory exists
    mkdir -p "$LYNIS_REPORTS"
    
    # Run Lynis audit
    cd "$LYNIS_HOME"
    
    local lynis_cmd="./lynis audit"
    
    case "$categories" in
        all|system)
            lynis_cmd+=" system"
            ;;
        network)
            lynis_cmd+=" --tests-category network"
            ;;
        crypto)
            lynis_cmd+=" --tests-category crypto"
            ;;
        authentication)
            lynis_cmd+=" --tests-category authentication"
            ;;
        *)
            lynis_cmd+=" --tests-category $categories"
            ;;
    esac
    
    lynis_cmd+=" --profile $LYNIS_CONFIG"
    lynis_cmd+=" --report-file $report_file"
    lynis_cmd+=" --log-file $LYNIS_LOG/audit_${timestamp}.log"
    
    if eval "$lynis_cmd"; then
        echo -e "${GREEN}[SUCCESS]${NC} Audit completed successfully"
        echo -e "${BLUE}[INFO]${NC} Report: $report_file"
        echo -e "${BLUE}[INFO]${NC} Log: $LYNIS_LOG/audit_${timestamp}.log"
    else
        echo -e "${RED}[ERROR]${NC} Audit failed"
        return 1
    fi
}

update_lynis() {
    echo -e "${BLUE}[INFO]${NC} Updating Lynis..."
    
    if [[ -d "$LYNIS_HOME/.git" ]]; then
        cd "$LYNIS_HOME"
        git pull origin main
        echo -e "${GREEN}[SUCCESS]${NC} Lynis updated successfully"
    else
        echo -e "${YELLOW}[WARNING]${NC} Lynis not installed via git, cannot auto-update"
        echo -e "${BLUE}[INFO]${NC} Use package manager to update: apt update && apt upgrade lynis"
    fi
}

show_report() {
    local latest_report=$(find "$LYNIS_REPORTS" -name "audit_*.dat" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [[ -n "$latest_report" ]] && [[ -f "$latest_report" ]]; then
        echo -e "${BLUE}[INFO]${NC} Latest audit report: $latest_report"
        echo -e "${BLUE}[INFO]${NC} Report summary:"
        echo
        
        # Extract key information from report
        if grep -q "hardening_index" "$latest_report"; then
            local hardening_index=$(grep "hardening_index" "$latest_report" | cut -d'=' -f2)
            echo -e "${BLUE}Hardening Index:${NC} $hardening_index%"
        fi
        
        if grep -q "warnings" "$latest_report"; then
            local warnings=$(grep -c "warning\[\]" "$latest_report" 2>/dev/null || echo "0")
            echo -e "${YELLOW}Warnings:${NC} $warnings"
        fi
        
        if grep -q "suggestions" "$latest_report"; then
            local suggestions=$(grep -c "suggestion\[\]" "$latest_report" 2>/dev/null || echo "0")
            echo -e "${BLUE}Suggestions:${NC} $suggestions"
        fi
        
        echo
        echo -e "${BLUE}[INFO]${NC} For detailed report analysis, review: $latest_report"
    else
        echo -e "${YELLOW}[WARNING]${NC} No audit reports found"
        echo -e "${BLUE}[INFO]${NC} Run 'lynis-manage audit' to generate a report"
    fi
}

show_status() {
    echo -e "${BLUE}[INFO]${NC} Lynis Installation Status"
    echo "========================="
    
    if [[ -f "$LYNIS_HOME/lynis" ]]; then
        echo -e "${GREEN}✓${NC} Lynis installed: $LYNIS_HOME"
        cd "$LYNIS_HOME"
        local version=$(./lynis show version 2>/dev/null | head -1 || echo "Unknown")
        echo -e "${BLUE}Version:${NC} $version"
    else
        echo -e "${RED}✗${NC} Lynis not found"
    fi
    
    if [[ -f "$LYNIS_CONFIG" ]]; then
        echo -e "${GREEN}✓${NC} Configuration: $LYNIS_CONFIG"
    else
        echo -e "${YELLOW}△${NC} Configuration: Default"
    fi
    
    if [[ -d "$LYNIS_REPORTS" ]]; then
        local report_count=$(find "$LYNIS_REPORTS" -name "*.dat" -type f | wc -l)
        echo -e "${BLUE}Reports:${NC} $report_count reports in $LYNIS_REPORTS"
    fi
    
    echo
    echo -e "${BLUE}[INFO]${NC} Log directory: $LYNIS_LOG"
    echo -e "${BLUE}[INFO]${NC} Data directory: /var/lib/lynis"
}

run_compliance_check() {
    local framework="${1:-}"
    
    if [[ -z "$framework" ]]; then
        echo -e "${RED}[ERROR]${NC} Please specify compliance framework"
        echo "Available: pci-dss, hipaa, iso27001, nist"
        return 1
    fi
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local report_file="$LYNIS_REPORTS/compliance_${framework}_${timestamp}.dat"
    
    echo -e "${BLUE}[INFO]${NC} Running $framework compliance check..."
    
    cd "$LYNIS_HOME"
    
    local lynis_cmd="./lynis audit system"
    lynis_cmd+=" --profile $LYNIS_CONFIG"
    lynis_cmd+=" --compliance-standards $framework"
    lynis_cmd+=" --report-file $report_file"
    lynis_cmd+=" --log-file $LYNIS_LOG/compliance_${framework}_${timestamp}.log"
    
    if eval "$lynis_cmd"; then
        echo -e "${GREEN}[SUCCESS]${NC} Compliance check completed"
        echo -e "${BLUE}[INFO]${NC} Report: $report_file"
    else
        echo -e "${RED}[ERROR]${NC} Compliance check failed"
        return 1
    fi
}

# Main command processing
case "${1:-help}" in
    audit)
        run_audit "${2:-all}"
        ;;
    update)
        update_lynis
        ;;
    report)
        show_report
        ;;
    status)
        show_status
        ;;
    config)
        if [[ -f "$LYNIS_CONFIG" ]]; then
            cat "$LYNIS_CONFIG"
        else
            echo "No custom configuration found"
        fi
        ;;
    compliance)
        run_compliance_check "${2:-}"
        ;;
    benchmark)
        run_audit "all"
        show_report
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Unknown command: ${1:-}"
        echo "Use 'lynis-manage help' for usage information"
        exit 1
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/lynis-manage
    chown root:root /usr/local/bin/lynis-manage
    
    log_lynis "INFO" "Lynis management wrapper created: /usr/local/bin/lynis-manage"
}

setup_automated_auditing() {
    log_lynis "INFO" "Setting up automated auditing"
    
    if [[ "$ENABLE_CRON" == "false" ]]; then
        log_lynis "INFO" "Automated auditing disabled by configuration"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_lynis "INFO" "[DRY RUN] Would set up cron job for $CRON_SCHEDULE auditing"
        return 0
    fi
    
    # Create audit script
    cat > /usr/local/bin/lynis-auto-audit << 'EOF'
#!/bin/bash
#
# Lynis Automated Audit Script
#

set -euo pipefail

LYNIS_HOME="/opt/lynis"
LYNIS_CONFIG="/etc/lynis/default.prf"
LYNIS_REPORTS="/var/log/bashmin/security/lynis/reports"
LYNIS_LOG="/var/log/bashmin/security/lynis"
NOTIFICATION_EMAIL="${LYNIS_NOTIFICATION_EMAIL:-}"
SLACK_WEBHOOK="${LYNIS_SLACK_WEBHOOK:-}"

# Ensure directories exist
mkdir -p "$LYNIS_REPORTS" "$LYNIS_LOG"

# Run audit
timestamp=$(date '+%Y%m%d_%H%M%S')
report_file="$LYNIS_REPORTS/auto_audit_${timestamp}.dat"
log_file="$LYNIS_LOG/auto_audit_${timestamp}.log"

echo "$(date): Starting automated Lynis audit" >> "$LYNIS_LOG/automated-audits.log"

cd "$LYNIS_HOME"
if ./lynis audit system --profile "$LYNIS_CONFIG" --report-file "$report_file" --log-file "$log_file" --quiet; then
    echo "$(date): Audit completed successfully" >> "$LYNIS_LOG/automated-audits.log"
    
    # Extract hardening index
    hardening_index=$(grep "hardening_index" "$report_file" 2>/dev/null | cut -d'=' -f2 || echo "unknown")
    warnings=$(grep -c "warning\[\]" "$report_file" 2>/dev/null || echo "0")
    suggestions=$(grep -c "suggestion\[\]" "$report_file" 2>/dev/null || echo "0")
    
    # Send notification if configured
    if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        {
            echo "Automated Lynis Security Audit Report"
            echo "====================================="
            echo ""
            echo "Server: $(hostname)"
            echo "Date: $(date)"
            echo "Hardening Index: ${hardening_index}%"
            echo "Warnings: $warnings"
            echo "Suggestions: $suggestions"
            echo ""
            echo "Full report: $report_file"
            echo "Log file: $log_file"
        } | mail -s "Lynis Security Audit - $(hostname)" "$NOTIFICATION_EMAIL"
    fi
    
    # Slack notification
    if [[ -n "$SLACK_WEBHOOK" ]] && command -v curl >/dev/null 2>&1; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🔍 Lynis Audit Complete - $(hostname)\",\"attachments\":[{\"color\":\"good\",\"fields\":[{\"title\":\"Hardening Index\",\"value\":\"${hardening_index}%\",\"short\":true},{\"title\":\"Warnings\",\"value\":\"$warnings\",\"short\":true},{\"title\":\"Report\",\"value\":\"$report_file\",\"short\":false}]}]}" \
            "$SLACK_WEBHOOK" >/dev/null 2>&1
    fi
    
else
    echo "$(date): Audit failed" >> "$LYNIS_LOG/automated-audits.log"
    
    # Send failure notification
    if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        echo "Automated Lynis audit failed on $(hostname) at $(date)" | \
            mail -s "ERROR: Lynis Audit Failed - $(hostname)" "$NOTIFICATION_EMAIL"
    fi
fi

# Cleanup old reports (keep last 90 days)
find "$LYNIS_REPORTS" -name "auto_audit_*.dat" -mtime +90 -delete 2>/dev/null || true
find "$LYNIS_LOG" -name "auto_audit_*.log" -mtime +90 -delete 2>/dev/null || true
EOF
    
    chmod +x /usr/local/bin/lynis-auto-audit
    
    # Set up cron job
    local cron_time
    case "$CRON_SCHEDULE" in
        daily)
            cron_time="0 2 * * *"
            ;;
        weekly)
            cron_time="0 2 * * 0"
            ;;
        monthly)
            cron_time="0 2 1 * *"
            ;;
        *)
            cron_time="0 2 * * 0"  # Default to weekly
            ;;
    esac
    
    cat > /etc/cron.d/lynis-audit << EOF
# Lynis Automated Security Audit
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
LYNIS_NOTIFICATION_EMAIL=$NOTIFICATION_EMAIL
LYNIS_SLACK_WEBHOOK=$SLACK_WEBHOOK

$cron_time root /usr/local/bin/lynis-auto-audit
EOF
    
    log_lynis "INFO" "Automated auditing configured: $CRON_SCHEDULE"
}

setup_log_rotation() {
    log_lynis "INFO" "Setting up log rotation"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_lynis "INFO" "[DRY RUN] Would set up log rotation"
        return 0
    fi
    
    cat > /etc/logrotate.d/bashmin-lynis << 'EOF'
/var/log/bashmin/security/lynis/*.log {
    daily
    missingok
    rotate 90
    compress
    delaycompress
    notifempty
    create 644 lynis lynis
    postrotate
        # No need to restart any service
    endscript
}

/var/log/bashmin/security/lynis/reports/*.dat {
    weekly
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 lynis lynis
}
EOF
    
    log_lynis "INFO" "Log rotation configured"
}

# Notification functions
send_notification() {
    local subject="$1"
    local message="$2"
    local level="${3:-INFO}"
    
    # Email notification
    if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        {
            echo "Lynis Security Auditing Notification"
            echo "===================================="
            echo ""
            echo "Server: $(hostname)"
            echo "Date: $(date)"
            echo "Level: $level"
            echo ""
            echo "$message"
            echo ""
            echo "---"
            echo "bashmin Security Suite"
        } | mail -s "$subject - $(hostname)" "$NOTIFICATION_EMAIL"
        
        log_lynis "DEBUG" "Email notification sent to $NOTIFICATION_EMAIL"
    fi
    
    # Slack notification
    if [[ -n "$SLACK_WEBHOOK" ]] && command -v curl >/dev/null 2>&1; then
        local color="good"
        local emoji="🔍"
        
        case "$level" in
            ERROR)
                color="danger"
                emoji="🚨"
                ;;
            WARN)
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
            log_lynis "DEBUG" "Slack notification sent successfully"
        else
            log_lynis "WARN" "Failed to send Slack notification"
        fi
    fi
}

# Main installation function
main() {
    log_lynis "INFO" "Starting Lynis security auditing installation"
    
    # Validate configuration
    if [[ -n "$NOTIFICATION_EMAIL" ]] && ! validate_email "$NOTIFICATION_EMAIL"; then
        exit 1
    fi
    
    if [[ -n "$SLACK_WEBHOOK" ]] && ! validate_webhook_url "$SLACK_WEBHOOK"; then
        exit 1
    fi
    
    if ! validate_audit_categories "$AUDIT_CATEGORIES"; then
        exit 1
    fi
    
    # Check if Lynis is already installed
    if command -v lynis >/dev/null 2>&1 && [[ "$FORCE" == "false" ]]; then
        log_lynis "INFO" "Lynis already installed, use --force to reinstall"
    else
        # Install dependencies
        install_dependencies
        
        # Create dedicated user
        create_lynis_user
        
        # Install Lynis based on method
        case "$INSTALL_METHOD" in
            git)
                install_lynis_git
                ;;
            package)
                install_lynis_package
                ;;
            *)
                log_lynis "ERROR" "Unknown installation method: $INSTALL_METHOD"
                exit 1
                ;;
        esac
    fi
    
    # Configure Lynis
    configure_lynis
    
    # Create management wrapper
    create_lynis_wrapper
    
    # Set up automated auditing
    setup_automated_auditing
    
    # Set up log rotation
    setup_log_rotation
    
    # Send installation notification
    if [[ "$ENABLE_NOTIFICATIONS" == "true" ]] && [[ "$DRY_RUN" == "false" ]]; then
        send_notification "Lynis Security Auditing Installation Complete" \
            "Lynis has been successfully installed and configured on $(hostname). Automated auditing is enabled and monitoring is active."
    fi
    
    log_lynis "INFO" "Lynis installation completed successfully"
    
    # Show next steps
    if [[ "$QUIET" == "false" ]]; then
        cat << EOF

✅ Lynis Security Auditing Installation Complete!

Next Steps:
1. Run your first audit:
   lynis-manage audit

2. Check installation status:
   lynis-manage status

3. Run compliance check:
   lynis-manage compliance pci-dss

4. View configuration:
   lynis-manage config

5. Monitor audit logs:
   tail -f /var/log/bashmin/security/lynis/automated-audits.log

Configuration Files:
• Lynis installation: $LYNIS_HOME
• Configuration: $LYNIS_CONFIG_DIR
• Reports: $LYNIS_REPORTS_DIR
• Logs: $BASHMIN_LYNIS_DIR

Management Tools:
• Lynis wrapper: lynis-manage
• Auto-audit script: /usr/local/bin/lynis-auto-audit
• Cron schedule: $CRON_SCHEDULE

For detailed usage information:
• lynis-manage help
• cat /var/www/vhosts/bashmin/security/lynis/README.md

EOF
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-method)
            INSTALL_METHOD="$2"
            shift 2
            ;;
        --lynis-version)
            LYNIS_VERSION="$2"
            shift 2
            ;;
        --custom-profile)
            CUSTOM_PROFILE="$2"
            shift 2
            ;;
        --license-key)
            LICENSE_KEY="$2"
            shift 2
            ;;
        --audit-categories)
            AUDIT_CATEGORIES="$2"
            shift 2
            ;;
        --audit-frequency)
            AUDIT_FREQUENCY="$2"
            shift 2
            ;;
        --hardening-index-threshold)
            HARDENING_INDEX_THRESHOLD="$2"
            shift 2
            ;;
        --enable-compliance)
            ENABLE_COMPLIANCE_SCANNING=true
            shift
            ;;
        --disable-compliance)
            ENABLE_COMPLIANCE_SCANNING=false
            shift
            ;;
        --pentest-mode)
            PENTEST_MODE=true
            shift
            ;;
        --developer-mode)
            DEVELOPER_MODE=true
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
        --auto-update)
            AUTO_UPDATE=true
            shift
            ;;
        --disable-auto-update)
            AUTO_UPDATE=false
            shift
            ;;
        --enable-reporting)
            ENABLE_REPORTING=true
            shift
            ;;
        --disable-reporting)
            ENABLE_REPORTING=false
            shift
            ;;
        --report-format)
            REPORT_FORMAT="$2"
            shift 2
            ;;
        --enable-notifications)
            ENABLE_NOTIFICATIONS=true
            shift
            ;;
        --disable-notifications)
            ENABLE_NOTIFICATIONS=false
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
        --upload-server)
            UPLOAD_SERVER="$2"
            shift 2
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
            log_lynis "ERROR" "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Verify running as root
if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
    log_lynis "ERROR" "This script must be run as root (use sudo)"
    exit 1
fi

# Run main function
main

exit 0