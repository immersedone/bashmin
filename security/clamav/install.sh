#!/bin/bash
#
# Script: security/clamav/install.sh
# Description: Install and configure ClamAV antivirus with automated scanning and updates
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
readonly CLAMAV_CONFIG_DIR="/etc/clamav"
readonly CLAMD_CONFIG="$CLAMAV_CONFIG_DIR/clamd.conf"
readonly FRESHCLAM_CONFIG="$CLAMAV_CONFIG_DIR/freshclam.conf"
readonly CLAMAV_LOG_DIR="/var/log/clamav"
readonly FRESHCLAM_LOG="$CLAMAV_LOG_DIR/freshclam.log"
readonly CLAMAV_SCAN_LOG="$CLAMAV_LOG_DIR/clamav.log"
readonly CLAMAV_DB_DIR="/var/lib/clamav"
readonly CLAMAV_RUN_DIR="/var/run/clamav"
readonly CLAMAV_SOCKET="/var/run/clamav/clamd.ctl"
readonly BASHMIN_LOGROTATE_CONF="$PROJECT_ROOT/system/etc/logrotate.d/clamav-freshclam"
readonly BASHMIN_SYSTEMD_SERVICE="$PROJECT_ROOT/system/etc/systemd/system/clamav-freshclam.service"
readonly NOTIFICATION_SCRIPT="/usr/share/scripts/notify-service-crash"

# Configuration variables
ENABLE_DAEMON=true
ENABLE_ON_ACCESS_SCANNING=false
ENABLE_SCHEDULED_SCANS=true
DAILY_SCAN_TIME="02:00"
SCAN_DIRECTORIES=("/home" "/var/www" "/opt")
QUARANTINE_DIR="/var/quarantine/clamav"
EXCLUDE_PATTERNS=("*.tmp" "*.log" "*.cache" "node_modules/*" ".git/*")
MAX_FILE_SIZE="100M"
MAX_RECURSION_LEVEL="15"
MAX_SCAN_TIME="120"
ENABLE_ARCHIVE_SCAN=true
ENABLE_PDF_SCAN=true
ENABLE_OFFICE_SCAN=true
ENABLE_PE_SCAN=true
ENABLE_ELF_SCAN=true
ENABLE_MAIL_SCAN=true
ENABLE_PHISHING_DETECTION=true
ENABLE_BYTECODE=true
ENABLE_STATS=true
UPDATE_FREQUENCY="24"  # Hours
UPDATE_MIRROR="db.local.clamav.net"
NOTIFICATION_EMAIL=""
ENABLE_EMAIL_NOTIFICATIONS=false
ENABLE_SYSLOG=true
LOG_LEVEL="INFO"
TCP_SOCKET=false
TCP_PORT="3310"
TCP_ADDR="127.0.0.1"
ENABLE_SYSTEMD_SOCKET=true
FORCE_INSTALL=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Function to show help and exit
show_help_and_exit() {
    cat << EOF
Usage: $0 [OPTIONS]

Install and configure ClamAV antivirus with automated scanning and updates.

DAEMON OPTIONS:
    --disable-daemon            Don't run ClamAV as daemon (command-line only)
    --enable-on-access          Enable real-time on-access scanning
    --tcp-socket                Enable TCP socket instead of Unix socket
    --tcp-port PORT             TCP port for daemon (default: 3310)
    --tcp-addr ADDRESS          TCP bind address (default: 127.0.0.1)
    --disable-systemd-socket    Disable systemd socket activation

SCANNING OPTIONS:
    --disable-scheduled-scans   Don't create scheduled daily scans
    --scan-time TIME            Daily scan time in HH:MM format (default: 02:00)
    --scan-dirs DIRS            Comma-separated directories to scan (default: /home,/var/www,/opt)
    --quarantine-dir DIR        Directory for quarantined files (default: /var/quarantine/clamav)
    --exclude-patterns PATTERNS Comma-separated file patterns to exclude
    --max-file-size SIZE        Maximum file size to scan (default: 100M)
    --max-recursion LEVEL       Maximum directory recursion level (default: 15)
    --max-scan-time SECONDS     Maximum time per file scan (default: 120)

DETECTION OPTIONS:
    --disable-archive-scan      Don't scan archives (zip, tar, etc.)
    --disable-pdf-scan          Don't scan PDF files
    --disable-office-scan       Don't scan office documents
    --disable-pe-scan           Don't scan PE/executable files
    --disable-elf-scan          Don't scan ELF binaries
    --disable-mail-scan         Don't scan email files
    --disable-phishing          Don't detect phishing attempts
    --disable-bytecode          Don't use bytecode signatures

UPDATE OPTIONS:
    --update-frequency HOURS    Database update frequency in hours (default: 24)
    --update-mirror MIRROR      Database mirror to use (default: db.local.clamav.net)

LOGGING OPTIONS:
    --log-level LEVEL           Log level: DEBUG, INFO, WARNING, ERROR (default: INFO)
    --disable-syslog            Don't log to syslog
    --disable-stats             Don't enable scanning statistics

NOTIFICATION OPTIONS:
    --email EMAIL               Email address for notifications
    --enable-email-notifications Send email alerts for threats and errors

SETUP OPTIONS:
    --force                     Force reinstall even if ClamAV is configured
    --quiet                     Suppress non-essential output
    --verbose                   Enable verbose output
    --dry-run                   Show what would be configured without executing
    -h, --help                  Show this help message

SECURITY MODES:
    Basic Protection:           Default settings with daily scans
    Web Server:                 Add --scan-dirs /var/www,/home --enable-on-access
    Mail Server:                Add --enable-mail-scan --enable-phishing
    File Server:                Add --enable-on-access --scan-dirs /home,/srv
    High Security:              Add --enable-on-access --log-level DEBUG

EXAMPLES:
    # Basic antivirus protection
    $0

    # Web server with real-time scanning
    $0 --enable-on-access --scan-dirs /var/www,/home,/opt

    # Mail server configuration
    $0 --enable-mail-scan --enable-phishing --email admin@example.com

    # High-security file server
    $0 --enable-on-access --scan-dirs /home,/srv,/var/www \
       --log-level DEBUG --quarantine-dir /secure/quarantine

    # Development server (lighter scanning)
    $0 --disable-archive-scan --max-file-size 50M \
       --exclude-patterns "*.tmp,*.log,node_modules/*,.git/*"

    # Custom TCP daemon setup
    $0 --tcp-socket --tcp-port 3310 --tcp-addr 0.0.0.0

NOTES:
    - Requires sudo privileges
    - Automatically configures virus database updates
    - Creates scheduled daily scans by default
    - Integrates with systemd for service management
    - Supports email notifications for threats
    - Uses existing bashmin log rotation configuration

SECURITY FEATURES:
    - Real-time on-access scanning (optional)
    - Quarantine infected files automatically
    - Comprehensive threat detection (malware, phishing, etc.)
    - Regular signature database updates
    - Integration with system logs and notifications

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --disable-daemon)
            ENABLE_DAEMON=false
            shift
            ;;
        --enable-on-access)
            ENABLE_ON_ACCESS_SCANNING=true
            shift
            ;;
        --disable-scheduled-scans)
            ENABLE_SCHEDULED_SCANS=false
            shift
            ;;
        --scan-time)
            DAILY_SCAN_TIME="$2"
            shift 2
            ;;
        --scan-dirs)
            IFS=',' read -ra SCAN_DIRECTORIES <<< "$2"
            shift 2
            ;;
        --quarantine-dir)
            QUARANTINE_DIR="$2"
            shift 2
            ;;
        --exclude-patterns)
            IFS=',' read -ra EXCLUDE_PATTERNS <<< "$2"
            shift 2
            ;;
        --max-file-size)
            MAX_FILE_SIZE="$2"
            shift 2
            ;;
        --max-recursion)
            MAX_RECURSION_LEVEL="$2"
            shift 2
            ;;
        --max-scan-time)
            MAX_SCAN_TIME="$2"
            shift 2
            ;;
        --disable-archive-scan)
            ENABLE_ARCHIVE_SCAN=false
            shift
            ;;
        --disable-pdf-scan)
            ENABLE_PDF_SCAN=false
            shift
            ;;
        --disable-office-scan)
            ENABLE_OFFICE_SCAN=false
            shift
            ;;
        --disable-pe-scan)
            ENABLE_PE_SCAN=false
            shift
            ;;
        --disable-elf-scan)
            ENABLE_ELF_SCAN=false
            shift
            ;;
        --disable-mail-scan)
            ENABLE_MAIL_SCAN=false
            shift
            ;;
        --disable-phishing)
            ENABLE_PHISHING_DETECTION=false
            shift
            ;;
        --disable-bytecode)
            ENABLE_BYTECODE=false
            shift
            ;;
        --update-frequency)
            UPDATE_FREQUENCY="$2"
            shift 2
            ;;
        --update-mirror)
            UPDATE_MIRROR="$2"
            shift 2
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --disable-syslog)
            ENABLE_SYSLOG=false
            shift
            ;;
        --disable-stats)
            ENABLE_STATS=false
            shift
            ;;
        --email)
            NOTIFICATION_EMAIL="$2"
            ENABLE_EMAIL_NOTIFICATIONS=true
            shift 2
            ;;
        --enable-email-notifications)
            ENABLE_EMAIL_NOTIFICATIONS=true
            shift
            ;;
        --tcp-socket)
            TCP_SOCKET=true
            shift
            ;;
        --tcp-port)
            TCP_PORT="$2"
            shift 2
            ;;
        --tcp-addr)
            TCP_ADDR="$2"
            shift 2
            ;;
        --disable-systemd-socket)
            ENABLE_SYSTEMD_SOCKET=false
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
    
    # Check if Ubuntu/Debian
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_warning "ClamAV installation may differ on $OS"
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
    
    # Check if ClamAV is already configured and force is not set
    if [[ -f "$CLAMD_CONFIG" && "$FORCE_INSTALL" == false ]]; then
        if grep -q "^Example" "$CLAMD_CONFIG" 2>/dev/null; then
            print_info "ClamAV configuration template found, proceeding with configuration"
        else
            print_error "ClamAV is already configured"
            print_info "Use --force to reconfigure"
            exit 1
        fi
    fi
    
    # Validate scan time format
    if [[ ! "$DAILY_SCAN_TIME" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
        print_error "Invalid scan time format: $DAILY_SCAN_TIME (use HH:MM format)"
        exit 1
    fi
    
    # Validate log level
    case "$LOG_LEVEL" in
        DEBUG|INFO|WARNING|ERROR) ;;
        *)
            print_error "Invalid log level: $LOG_LEVEL (use: DEBUG, INFO, WARNING, ERROR)"
            exit 1
            ;;
    esac
    
    # Validate update frequency
    if [[ ! "$UPDATE_FREQUENCY" =~ ^[0-9]+$ ]] || [[ "$UPDATE_FREQUENCY" -lt 1 ]] || [[ "$UPDATE_FREQUENCY" -gt 168 ]]; then
        print_error "Invalid update frequency: $UPDATE_FREQUENCY (1-168 hours)"
        exit 1
    fi
    
    # Validate TCP port
    if [[ "$TCP_SOCKET" == true ]]; then
        if [[ ! "$TCP_PORT" =~ ^[0-9]+$ ]] || [[ "$TCP_PORT" -lt 1 ]] || [[ "$TCP_PORT" -gt 65535 ]]; then
            print_error "Invalid TCP port: $TCP_PORT"
            exit 1
        fi
    fi
    
    # Validate email format if provided
    if [[ -n "$NOTIFICATION_EMAIL" ]]; then
        if [[ ! "$NOTIFICATION_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "Invalid email format: $NOTIFICATION_EMAIL"
            exit 1
        fi
    fi
    
    # Check if scan directories exist
    for dir in "${SCAN_DIRECTORIES[@]}"; do
        if [[ ! -d "$dir" ]]; then
            print_warning "Scan directory does not exist: $dir"
        fi
    done
}

# Function to install ClamAV packages
install_clamav() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install ClamAV packages"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installing ClamAV packages..."
    fi
    
    # Update package cache
    sudo apt-get update -qq
    
    # Install ClamAV packages
    local packages=("clamav" "clamav-daemon" "clamav-freshclam")
    
    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then
        packages+=("mailutils")
    fi
    
    sudo apt-get install -y "${packages[@]}"
    
    # Verify installation
    if ! command -v clamscan >/dev/null 2>&1; then
        print_error "ClamAV installation failed"
        exit 1
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "ClamAV packages installed successfully"
    fi
}

# Function to create required directories
create_directories() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create ClamAV directories"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Creating ClamAV directories..."
    fi
    
    # Create directories with proper permissions
    sudo mkdir -p "$CLAMAV_LOG_DIR"
    sudo mkdir -p "$CLAMAV_RUN_DIR"
    sudo mkdir -p "$QUARANTINE_DIR"
    
    # Set ownership and permissions
    sudo chown clamav:clamav "$CLAMAV_LOG_DIR"
    sudo chown clamav:clamav "$CLAMAV_RUN_DIR"
    sudo chown clamav:clamav "$QUARANTINE_DIR"
    
    sudo chmod 755 "$CLAMAV_LOG_DIR"
    sudo chmod 755 "$CLAMAV_RUN_DIR"
    sudo chmod 755 "$QUARANTINE_DIR"
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "ClamAV directories created"
    fi
}

# Function to backup existing configuration
backup_existing_config() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would backup existing ClamAV configuration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Backing up existing ClamAV configuration..."
    fi
    
    local backup_dir="/etc/clamav/backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -d "$CLAMAV_CONFIG_DIR" ]]; then
        sudo mkdir -p "$backup_dir"
        sudo cp -r "$CLAMAV_CONFIG_DIR"/* "$backup_dir"/ 2>/dev/null || true
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Configuration backed up to: $backup_dir"
        fi
    fi
}

# Function to configure clamd
configure_clamd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure ClamAV daemon"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring ClamAV daemon..."
    fi
    
    # Create clamd configuration
    cat << EOF | sudo tee "$CLAMD_CONFIG" >/dev/null
# ClamAV Daemon Configuration
# Generated by bashmin on $(date)

# Remove or comment out the Example line
# Example

# Log settings
LogFile $CLAMAV_SCAN_LOG
LogFileMaxSize 10M
LogTime yes
LogSyslog $(bool_to_yes_no $ENABLE_SYSLOG)
LogVerbose $(bool_to_yes_no $VERBOSE)
LogRotate yes
LogClean yes

# Database settings
DatabaseDirectory $CLAMAV_DB_DIR
OfficialDatabaseOnly no

# Scanning settings
LocalSocket $CLAMAV_SOCKET
LocalSocketGroup clamav
LocalSocketMode 666
FixStaleSocket yes

# TCP socket settings
EOF

    if [[ "$TCP_SOCKET" == true ]]; then
        cat << EOF | sudo tee -a "$CLAMD_CONFIG" >/dev/null
TCPSocket $TCP_PORT
TCPAddr $TCP_ADDR
EOF
    else
        cat << EOF | sudo tee -a "$CLAMD_CONFIG" >/dev/null
# TCPSocket disabled
EOF
    fi

    cat << EOF | sudo tee -a "$CLAMD_CONFIG" >/dev/null

# Process settings
MaxConnectionQueueLength 15
MaxThreads 20
ReadTimeout 300
CommandReadTimeout 30
SendBufTimeout 200
MaxQueue 100
IdleTimeout 30

# Scanning limits
MaxFileSize $(convert_size_to_bytes "$MAX_FILE_SIZE")
MaxRecursion $MAX_RECURSION_LEVEL
MaxScanTime $MAX_SCAN_TIME
MaxDirectoryRecursion 25

# Archive scanning
ScanArchive $(bool_to_yes_no $ENABLE_ARCHIVE_SCAN)
ScanPDF $(bool_to_yes_no $ENABLE_PDF_SCAN)
ScanOLE2 $(bool_to_yes_no $ENABLE_OFFICE_SCAN)
ScanPE $(bool_to_yes_no $ENABLE_PE_SCAN)
ScanELF $(bool_to_yes_no $ENABLE_ELF_SCAN)
ScanMail $(bool_to_yes_no $ENABLE_MAIL_SCAN)

# Detection features
DetectPUA yes
DetectBrokenExecutables yes
AlgorithmicDetection yes
Bytecode $(bool_to_yes_no $ENABLE_BYTECODE)
BytecodeSecurity TrustSigned

# Phishing detection
PhishingSignatures $(bool_to_yes_no $ENABLE_PHISHING_DETECTION)
PhishingScanURLs $(bool_to_yes_no $ENABLE_PHISHING_DETECTION)

# On-access scanning
ScanOnAccess $(bool_to_yes_no $ENABLE_ON_ACCESS_SCANNING)
EOF

    if [[ "$ENABLE_ON_ACCESS_SCANNING" == true ]]; then
        cat << EOF | sudo tee -a "$CLAMD_CONFIG" >/dev/null
OnAccessMountPath /
OnAccessIncludePath /home
OnAccessIncludePath /var/www
OnAccessExcludePath /proc
OnAccessExcludePath /sys
OnAccessExcludePath /dev
OnAccessMaxFileSize $(convert_size_to_bytes "$MAX_FILE_SIZE")
OnAccessPrevention yes
OnAccessExtraScanning yes
EOF
    fi

    cat << EOF | sudo tee -a "$CLAMD_CONFIG" >/dev/null

# Statistics
StatsEnabled $(bool_to_yes_no $ENABLE_STATS)
StatsPEDisabled no
StatsHostID auto
StatsTimeout 10

# Process settings
User clamav
AllowAllMatchScan yes
ForegroundTimeout 300
PidFile /var/run/clamav/clamd.pid
TemporaryDirectory /tmp
DatabaseDirectory $CLAMAV_DB_DIR
EOF
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "ClamAV daemon configured"
    fi
}

# Function to configure freshclam
configure_freshclam() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure freshclam (database updater)"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring freshclam (database updater)..."
    fi
    
    # Create freshclam configuration
    cat << EOF | sudo tee "$FRESHCLAM_CONFIG" >/dev/null
# Freshclam Configuration
# Generated by bashmin on $(date)

# Remove or comment out the Example line
# Example

# Database settings
DatabaseDirectory $CLAMAV_DB_DIR
UpdateLogFile $FRESHCLAM_LOG
LogVerbose $(bool_to_yes_no $VERBOSE)
LogSyslog $(bool_to_yes_no $ENABLE_SYSLOG)
LogTime yes
LogRotate yes

# Update settings
DatabaseMirror $UPDATE_MIRROR
DNSDatabaseInfo current.cvd.clamav.net
ConnectTimeout 60
ReceiveTimeout 60
MaxAttempts 5
CompressLocalDatabase no

# Frequency settings (handled by systemd timer)
Checks $UPDATE_FREQUENCY

# Process settings
DatabaseOwner clamav
NotifyClamd $CLAMD_CONFIG
ScriptedUpdates yes
SafeBrowsing yes
Bytecode $(bool_to_yes_no $ENABLE_BYTECODE)

# Proxy settings (if needed)
# HTTPProxyServer myproxy.com
# HTTPProxyPort 1234
# HTTPProxyUsername myusername
# HTTPProxyPassword mypass

# Disable automatic daemon start from cron
# (We use systemd instead)
# Foreground yes
EOF
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Freshclam configured"
    fi
}

# Function to configure log rotation
configure_log_rotation() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure ClamAV log rotation"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring ClamAV log rotation..."
    fi
    
    # Use bashmin logrotate configuration if available
    if [[ -f "$BASHMIN_LOGROTATE_CONF" ]]; then
        sudo cp "$BASHMIN_LOGROTATE_CONF" /etc/logrotate.d/clamav-freshclam
    else
        create_logrotate_config
    fi
    
    # Create logrotate config for main ClamAV log
    cat << 'EOF' | sudo tee /etc/logrotate.d/clamav >/dev/null
/var/log/clamav/clamav.log {
    rotate 30
    daily
    dateext
    compress
    delaycompress
    missingok
    create 640 clamav adm
    postrotate
    if [ -d /run/systemd/system ]; then
        systemctl -q is-active clamav-daemon && systemctl kill --signal=SIGHUP clamav-daemon || true
    else
        invoke-rc.d clamav-daemon reload-log > /dev/null || true
    fi
    endscript
}
EOF
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Log rotation configured"
    fi
}

# Function to create logrotate configuration
create_logrotate_config() {
    cat << 'EOF' | sudo tee /etc/logrotate.d/clamav-freshclam >/dev/null
/var/log/clamav/freshclam.log {
     rotate 30
     daily
     dateext
     compress
     delaycompress
     missingok
     create 640  clamav adm
     postrotate
     if [ -d /run/systemd/system ]; then
         systemctl -q is-active clamav-freshclam && systemctl kill --signal=SIGHUP clamav-freshclam || true
     else
         invoke-rc.d clamav-freshclam reload-log > /dev/null || true
     fi
     endscript
}
EOF
}

# Function to configure systemd services
configure_systemd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure systemd services"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring systemd services..."
    fi
    
    # Use bashmin systemd service if available
    if [[ -f "$BASHMIN_SYSTEMD_SERVICE" ]]; then
        sudo cp "$BASHMIN_SYSTEMD_SERVICE" /etc/systemd/system/clamav-freshclam.service
    fi
    
    # Configure clamd service
    if [[ "$ENABLE_DAEMON" == true ]]; then
        sudo systemctl enable clamav-daemon
        
        if [[ "$ENABLE_SYSTEMD_SOCKET" == true ]]; then
            sudo systemctl enable clamav-daemon.socket
        fi
    fi
    
    # Configure freshclam service
    sudo systemctl enable clamav-freshclam
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Systemd services configured"
    fi
}

# Function to create scan scripts
create_scan_scripts() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create scan scripts"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Creating scan scripts..."
    fi
    
    # Create scan script directory
    sudo mkdir -p /usr/local/bin/clamav
    
    # Create daily scan script
    cat << EOF | sudo tee /usr/local/bin/clamav/daily-scan.sh >/dev/null
#!/bin/bash
#
# ClamAV Daily Scan Script
# Generated by bashmin on $(date)
#

set -euo pipefail

# Configuration
SCAN_DIRS=($(printf '"%s" ' "${SCAN_DIRECTORIES[@]}"))
QUARANTINE_DIR="$QUARANTINE_DIR"
LOG_FILE="$CLAMAV_SCAN_LOG"
NOTIFICATION_EMAIL="$NOTIFICATION_EMAIL"
ENABLE_EMAIL_NOTIFICATIONS=$ENABLE_EMAIL_NOTIFICATIONS

# Exclude patterns
EXCLUDE_ARGS=()
EOF

    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        echo "EXCLUDE_ARGS+=(\"--exclude=$pattern\")" | sudo tee -a /usr/local/bin/clamav/daily-scan.sh >/dev/null
    done

    cat << 'EOF' | sudo tee -a /usr/local/bin/clamav/daily-scan.sh >/dev/null

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Email notification function
send_notification() {
    local subject="$1"
    local message="$2"
    
    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true && -n "$NOTIFICATION_EMAIL" ]]; then
        echo "$message" | mail -s "$subject" "$NOTIFICATION_EMAIL" 2>/dev/null || true
    fi
}

# Start scan
log_message "Starting daily ClamAV scan"
START_TIME=$(date +%s)

# Initialize counters
TOTAL_FILES=0
INFECTED_FILES=0
QUARANTINED_FILES=0

# Create quarantine directory if it doesn't exist
mkdir -p "$QUARANTINE_DIR"

# Scan each directory
for scan_dir in "${SCAN_DIRS[@]}"; do
    if [[ ! -d "$scan_dir" ]]; then
        log_message "Warning: Directory $scan_dir does not exist, skipping"
        continue
    fi
    
    log_message "Scanning directory: $scan_dir"
    
    # Run ClamAV scan
    SCAN_OUTPUT=$(clamscan \
        --recursive \
        --infected \
        --move="$QUARANTINE_DIR" \
        --log="$LOG_FILE" \
        "${EXCLUDE_ARGS[@]}" \
        "$scan_dir" 2>&1 || true)
    
    # Parse scan results
    if echo "$SCAN_OUTPUT" | grep -q "Infected files:"; then
        INFECTED_COUNT=$(echo "$SCAN_OUTPUT" | grep "Infected files:" | awk '{print $3}')
        INFECTED_FILES=$((INFECTED_FILES + INFECTED_COUNT))
    fi
    
    if echo "$SCAN_OUTPUT" | grep -q "Scanned files:"; then
        SCANNED_COUNT=$(echo "$SCAN_OUTPUT" | grep "Scanned files:" | awk '{print $3}')
        TOTAL_FILES=$((TOTAL_FILES + SCANNED_COUNT))
    fi
done

# Calculate scan duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Generate summary
SUMMARY="ClamAV Daily Scan Completed
Scan Duration: ${DURATION} seconds
Total Files Scanned: $TOTAL_FILES
Infected Files Found: $INFECTED_FILES
Files Quarantined: $INFECTED_FILES
Quarantine Directory: $QUARANTINE_DIR"

log_message "$SUMMARY"

# Send notifications if needed
if [[ $INFECTED_FILES -gt 0 ]]; then
    send_notification "ClamAV Alert: $INFECTED_FILES infected files found" "$SUMMARY"
    log_message "Alert: $INFECTED_FILES infected files found and quarantined"
elif [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then
    send_notification "ClamAV Daily Scan: Clean" "$SUMMARY"
fi

log_message "Daily scan completed successfully"
EOF
    
    # Make script executable
    sudo chmod +x /usr/local/bin/clamav/daily-scan.sh
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Scan scripts created"
    fi
}

# Function to setup scheduled scans
setup_scheduled_scans() {
    if [[ "$ENABLE_SCHEDULED_SCANS" == false || "$DRY_RUN" == true ]]; then
        if [[ "$DRY_RUN" == true && "$ENABLE_SCHEDULED_SCANS" == true ]]; then
            echo "[DRY-RUN] Would setup scheduled scans"
        fi
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Setting up scheduled scans..."
    fi
    
    # Create systemd timer for daily scans
    cat << EOF | sudo tee /etc/systemd/system/clamav-daily-scan.service >/dev/null
[Unit]
Description=ClamAV Daily Scan
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/clamav/daily-scan.sh
User=root
StandardOutput=journal
StandardError=journal
EOF
    
    cat << EOF | sudo tee /etc/systemd/system/clamav-daily-scan.timer >/dev/null
[Unit]
Description=Run ClamAV Daily Scan
Requires=clamav-daily-scan.service

[Timer]
OnCalendar=daily
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF
    
    # Enable and start timer
    sudo systemctl daemon-reload
    sudo systemctl enable clamav-daily-scan.timer
    sudo systemctl start clamav-daily-scan.timer
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Scheduled scans configured"
    fi
}

# Function to update virus database
update_virus_database() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would update virus database"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Updating virus database..."
    fi
    
    # Stop freshclam service to avoid conflicts
    sudo systemctl stop clamav-freshclam 2>/dev/null || true
    
    # Run initial database update
    sudo freshclam --verbose 2>/dev/null || {
        print_warning "Initial database update failed, will retry via service"
    }
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Virus database update initiated"
    fi
}

# Function to start services
start_services() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would start ClamAV services"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Starting ClamAV services..."
    fi
    
    # Start freshclam service
    sudo systemctl start clamav-freshclam
    
    # Start daemon if enabled
    if [[ "$ENABLE_DAEMON" == true ]]; then
        if [[ "$ENABLE_SYSTEMD_SOCKET" == true ]]; then
            sudo systemctl start clamav-daemon.socket
        fi
        sudo systemctl start clamav-daemon
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "ClamAV services started"
    fi
}

# Function to test configuration
test_configuration() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test ClamAV configuration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Testing ClamAV configuration..."
    fi
    
    # Test clamd configuration
    if [[ "$ENABLE_DAEMON" == true ]]; then
        if sudo clamd -c "$CLAMD_CONFIG" --config-check 2>/dev/null; then
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_success "ClamAV daemon configuration valid"
            fi
        else
            print_warning "ClamAV daemon configuration may have issues"
        fi
    fi
    
    # Test freshclam configuration
    if sudo freshclam --config-file="$FRESHCLAM_CONFIG" --version >/dev/null 2>&1; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Freshclam configuration valid"
        fi
    else
        print_warning "Freshclam configuration may have issues"
    fi
    
    # Test basic scanning
    local test_file="/tmp/clamav_test_$$"
    echo "Test file for ClamAV" > "$test_file"
    
    if clamscan "$test_file" >/dev/null 2>&1; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "ClamAV scanning test passed"
        fi
    else
        print_warning "ClamAV scanning test failed"
    fi
    
    rm -f "$test_file"
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Configuration testing completed"
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

# Helper function to convert size to bytes
convert_size_to_bytes() {
    local size="$1"
    local number="${size%?}"
    local unit="${size: -1}"
    
    case "${unit^^}" in
        K) echo $((number * 1024)) ;;
        M) echo $((number * 1024 * 1024)) ;;
        G) echo $((number * 1024 * 1024 * 1024)) ;;
        *) echo "$size" ;;
    esac
}

# Function to show completion summary
show_completion_summary() {
    if [[ "$QUIET" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo
    print_success "ClamAV installation and configuration completed successfully! 🛡️"
    echo
    print_info "=== ClamAV Configuration Summary ==="
    cat << EOF
Installation Mode:
  Daemon Mode:           $(bool_to_yes_no $ENABLE_DAEMON)
  On-Access Scanning:    $(bool_to_yes_no $ENABLE_ON_ACCESS_SCANNING)
  Scheduled Scans:       $(bool_to_yes_no $ENABLE_SCHEDULED_SCANS)
  TCP Socket:            $(bool_to_yes_no $TCP_SOCKET)

Scan Configuration:
  Daily Scan Time:       $DAILY_SCAN_TIME
  Max File Size:         $MAX_FILE_SIZE
  Max Scan Time:         ${MAX_SCAN_TIME}s
  Max Recursion:         $MAX_RECURSION_LEVEL

EOF

    print_info "=== Scan Directories ==="
    for dir in "${SCAN_DIRECTORIES[@]}"; do
        echo "  $dir"
    done
    echo

    print_info "=== Detection Features ==="
    cat << EOF
Archive Scanning:      $(bool_to_yes_no $ENABLE_ARCHIVE_SCAN)
PDF Scanning:          $(bool_to_yes_no $ENABLE_PDF_SCAN)
Office Document Scan:  $(bool_to_yes_no $ENABLE_OFFICE_SCAN)
Executable Scanning:   $(bool_to_yes_no $ENABLE_PE_SCAN)
Mail Scanning:         $(bool_to_yes_no $ENABLE_MAIL_SCAN)
Phishing Detection:    $(bool_to_yes_no $ENABLE_PHISHING_DETECTION)
Bytecode Signatures:   $(bool_to_yes_no $ENABLE_BYTECODE)

EOF

    print_info "=== File Locations ==="
    cat << EOF
Configuration:         $CLAMAV_CONFIG_DIR
Log Files:             $CLAMAV_LOG_DIR
Virus Database:        $CLAMAV_DB_DIR
Quarantine Directory:  $QUARANTINE_DIR
Socket File:           $CLAMAV_SOCKET

EOF

    if [[ "$TCP_SOCKET" == true ]]; then
        print_info "=== TCP Configuration ==="
        cat << EOF
TCP Port:              $TCP_PORT
TCP Address:           $TCP_ADDR

EOF
    fi

    print_info "=== Service Status ==="
    if [[ "$ENABLE_DAEMON" == true ]]; then
        sudo systemctl is-active clamav-daemon 2>/dev/null || echo "ClamAV Daemon: inactive"
        sudo systemctl is-enabled clamav-daemon 2>/dev/null || echo "ClamAV Daemon: disabled"
    else
        echo "ClamAV Daemon: disabled by configuration"
    fi
    
    sudo systemctl is-active clamav-freshclam 2>/dev/null || echo "Freshclam: inactive"
    sudo systemctl is-enabled clamav-freshclam 2>/dev/null || echo "Freshclam: disabled"
    
    if [[ "$ENABLE_SCHEDULED_SCANS" == true ]]; then
        sudo systemctl is-active clamav-daily-scan.timer 2>/dev/null || echo "Daily Scan Timer: inactive"
        sudo systemctl is-enabled clamav-daily-scan.timer 2>/dev/null || echo "Daily Scan Timer: disabled"
    fi
    echo

    print_info "=== Management Commands ==="
    cat << EOF
Check virus database:  sudo freshclam --version
Manual scan:           sudo clamscan [options] [files/directories]
Daemon status:         sudo systemctl status clamav-daemon
Update database:       sudo systemctl restart clamav-freshclam
View logs:             sudo tail -f $CLAMAV_SCAN_LOG
Daily scan logs:       sudo journalctl -u clamav-daily-scan

EOF

    print_info "=== Scanning Commands ==="
    cat << EOF
Quick scan:            sudo clamscan /home
Recursive scan:        sudo clamscan -r /var/www
Infected files only:   sudo clamscan -i /path/to/scan
Move infected files:   sudo clamscan --move=/quarantine /path/to/scan
Detailed scan:         sudo clamscan -v -r /path/to/scan

EOF

    print_info "=== Socket Commands ==="
    if [[ "$ENABLE_DAEMON" == true ]]; then
        if [[ "$TCP_SOCKET" == true ]]; then
            cat << EOF
Test daemon:           echo "PING" | nc $TCP_ADDR $TCP_PORT
Scan via daemon:       clamdscan /path/to/file

EOF
        else
            cat << EOF
Test daemon:           echo "PING" | socat - UNIX-CONNECT:$CLAMAV_SOCKET
Scan via daemon:       clamdscan /path/to/file

EOF
        fi
    fi

    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == true ]]; then
        print_info "=== Email Notifications ==="
        cat << EOF
Notification Email:    $NOTIFICATION_EMAIL
Test email:            echo "Test message" | mail -s "ClamAV Test" $NOTIFICATION_EMAIL

EOF
    fi

    print_info "=== Security Notes ==="
    cat << EOF
• Monitor logs regularly for detected threats
• Keep virus signatures updated (automated via freshclam)
• Review quarantined files periodically
• Test scanning performance on large directories
• Consider excluding development files (node_modules, .git) for performance

EOF

    if [[ "$ENABLE_ON_ACCESS_SCANNING" == true ]]; then
        print_warning "On-access scanning is enabled - monitor system performance"
    fi
    
    print_info "🦠 Your system is now protected by ClamAV antivirus!"
}

# Main function
main() {
    # Detect system
    detect_system
    
    if [[ "$QUIET" == false ]]; then
        show_script_header "ClamAV Antivirus Installation"
        print_info "Installing and configuring ClamAV with automated scanning"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show configuration plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuration plan:"
        print_info "  Daemon Mode: $ENABLE_DAEMON"
        print_info "  On-Access Scanning: $ENABLE_ON_ACCESS_SCANNING"
        print_info "  Scheduled Scans: $ENABLE_SCHEDULED_SCANS"
        print_info "  Daily Scan Time: $DAILY_SCAN_TIME"
        print_info "  Scan Directories: ${SCAN_DIRECTORIES[*]}"
        print_info "  Quarantine Directory: $QUARANTINE_DIR"
        print_info "  Email Notifications: $ENABLE_EMAIL_NOTIFICATIONS"
        [[ -n "$NOTIFICATION_EMAIL" ]] && print_info "  Notification Email: $NOTIFICATION_EMAIL"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with ClamAV configuration?" "Y"; then
            print_info "ClamAV configuration cancelled"
            exit 0
        fi
    fi
    
    # Execute installation steps
    install_clamav
    create_directories
    backup_existing_config
    configure_clamd
    configure_freshclam
    configure_log_rotation
    configure_systemd
    create_scan_scripts
    setup_scheduled_scans
    update_virus_database
    start_services
    
    # Test and verify configuration
    if test_configuration; then
        show_completion_summary
    else
        print_error "ClamAV configuration test failed"
        print_info "Check configuration manually: sudo clamd --config-check"
        exit 1
    fi
}

# Run main function
main "$@"
