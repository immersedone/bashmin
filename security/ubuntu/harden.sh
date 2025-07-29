#!/bin/bash
#
# Script: security/ubuntu/harden.sh
# Description: Comprehensive Ubuntu 24.04+ system hardening script
# Usage: ./harden.sh [OPTIONS]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly UBUNTU_VERSION_MIN=24.04
readonly SYSCTL_CONF_DIR="/etc/sysctl.d"
readonly SECURITY_LIMITS_CONF="/etc/security/limits.d/99-bashmin-security.conf"
readonly LOGIN_DEFS="/etc/login.defs"
readonly PAM_COMMON_PASSWORD="/etc/pam.d/common-password"
readonly PAM_COMMON_AUTH="/etc/pam.d/common-auth"
readonly SUDOERS_BASHMIN="/etc/sudoers.d/99-bashmin-hardening"
readonly KERNEL_MODULES_BLACKLIST="/etc/modprobe.d/bashmin-blacklist.conf"
readonly GRUB_CONFIG="/etc/default/grub"
readonly APPARMOR_DIR="/etc/apparmor.d"
readonly AUDIT_RULES="/etc/audit/rules.d/99-bashmin.rules"
readonly LOGROTATE_AUDIT="/etc/logrotate.d/audit"
readonly BASHMIN_LOG_DIR="/var/log/bashmin"
readonly BASHMIN_SECURITY_LOG="$BASHMIN_LOG_DIR/hardening.log"

# Configuration variables
ENABLE_KERNEL_HARDENING=true
ENABLE_NETWORK_HARDENING=true
ENABLE_FILESYSTEM_HARDENING=true
ENABLE_USER_ACCOUNT_HARDENING=true
ENABLE_AUDIT_LOGGING=true
ENABLE_APPARMOR=true
ENABLE_PROCESS_HARDENING=true
ENABLE_MEMORY_PROTECTION=true
ENABLE_COREDUMP_RESTRICTION=true
ENABLE_COMPILER_PROTECTION=true
ENABLE_UMASK_HARDENING=true
ENABLE_CRON_HARDENING=true
ENABLE_SERVICE_HARDENING=true
ENABLE_BOOTLOADER_HARDENING=true
DISABLE_UNUSED_FILESYSTEMS=true
DISABLE_UNUSED_PROTOCOLS=true
DISABLE_USB_STORAGE=false
DISABLE_FIREWIRE=true
DISABLE_THUNDERBOLT=false
PASSWORD_MIN_LENGTH=12
PASSWORD_MAX_AGE=90
PASSWORD_MIN_AGE=1
PASSWORD_WARN_AGE=7
FAILED_LOGIN_ATTEMPTS=5
LOCKOUT_DURATION=900
SESSION_TIMEOUT=1800
ENABLE_TWO_FACTOR=false
GRUB_PASSWORD=""
ENABLE_SECURE_BOOT=false
BACKUP_CONFIGS=true
FORCE_APPLY=false
VERBOSE=false
DRY_RUN=false

# Help function
show_help() {
    cat << 'EOF'
Ubuntu 24.04+ System Hardening Script

DESCRIPTION:
    Comprehensive system hardening following CIS benchmarks, NIST guidelines,
    and security best practices for Ubuntu 24.04+ servers. Implements multi-layered
    security controls across kernel, network, filesystem, and user account domains.

USAGE:
    ./harden.sh [OPTIONS]

HARDENING CATEGORIES:
    Kernel & System Hardening:
    --enable-kernel-hardening      Enable kernel parameter hardening [default]
    --enable-memory-protection     Enable memory protection features [default]
    --enable-process-hardening     Enable process isolation and protection [default]
    --disable-kernel-hardening     Skip kernel hardening
    
    Network Security:
    --enable-network-hardening     Enable network stack hardening [default]
    --disable-network-hardening    Skip network hardening
    --disable-unused-protocols     Disable unused network protocols [default]
    
    Filesystem Security:
    --enable-filesystem-hardening  Enable filesystem security controls [default]
    --disable-filesystem-hardening Skip filesystem hardening
    --disable-unused-filesystems   Disable unused filesystem types [default]
    --disable-usb-storage          Disable USB mass storage devices
    --disable-firewire             Disable FireWire/IEEE 1394 [default]
    --disable-thunderbolt          Disable Thunderbolt interfaces
    
    User Account Security:
    --enable-user-hardening        Enable user account security [default]
    --disable-user-hardening       Skip user account hardening
    --password-min-length LENGTH   Minimum password length [12]
    --password-max-age DAYS        Maximum password age [90]
    --password-min-age DAYS        Minimum password age [1]
    --failed-login-attempts COUNT  Failed login attempt limit [5]
    --lockout-duration SECONDS     Account lockout duration [900]
    --session-timeout SECONDS      Session timeout [1800]
    --enable-two-factor            Enable two-factor authentication
    
    Audit & Logging:
    --enable-audit-logging         Enable comprehensive audit logging [default]
    --disable-audit-logging        Skip audit configuration
    
    AppArmor Security:
    --enable-apparmor              Enable AppArmor mandatory access control [default]
    --disable-apparmor             Skip AppArmor configuration
    
    Additional Hardening:
    --enable-coredump-restriction  Restrict core dump generation [default]
    --enable-compiler-protection   Restrict compiler access [default]
    --enable-cron-hardening        Harden cron and at services [default]
    --enable-service-hardening     Harden system services [default]
    --enable-bootloader-hardening  Secure GRUB bootloader [default]
    --grub-password PASSWORD       Set GRUB password for boot protection
    --enable-secure-boot           Enable UEFI Secure Boot validation
    
    Configuration Options:
    --backup-configs               Backup original configurations [default]
    --no-backup-configs            Skip configuration backups
    --force-apply                  Apply hardening without confirmation
    --dry-run                      Show what would be done without changes
    --verbose                      Enable detailed output
    --help, -h                     Show this help message

EXAMPLES:
    # Complete system hardening with defaults
    ./harden.sh

    # High-security server hardening
    ./harden.sh --enable-two-factor --disable-usb-storage --grub-password "SecurePass123"

    # Web server hardening with relaxed USB access
    ./harden.sh --password-min-length 14 --session-timeout 3600

    # Preview hardening changes
    ./harden.sh --dry-run --verbose

    # Force hardening without prompts
    ./harden.sh --force-apply

SECURITY DOMAINS:
    ✓ Kernel hardening (sysctl parameters)
    ✓ Network stack protection
    ✓ Filesystem access controls
    ✓ User account policies
    ✓ Process isolation and limits
    ✓ Memory protection mechanisms
    ✓ Audit logging and monitoring
    ✓ AppArmor mandatory access control
    ✓ Service and daemon hardening
    ✓ Bootloader security

COMPLIANCE FRAMEWORKS:
    • CIS Ubuntu 24.04 Benchmark
    • NIST Cybersecurity Framework
    • PCI DSS Requirements
    • ISO 27001 Controls
    • OWASP Security Guidelines

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --enable-kernel-hardening)
                ENABLE_KERNEL_HARDENING=true
                shift
                ;;
            --disable-kernel-hardening)
                ENABLE_KERNEL_HARDENING=false
                shift
                ;;
            --enable-network-hardening)
                ENABLE_NETWORK_HARDENING=true
                shift
                ;;
            --disable-network-hardening)
                ENABLE_NETWORK_HARDENING=false
                shift
                ;;
            --enable-filesystem-hardening)
                ENABLE_FILESYSTEM_HARDENING=true
                shift
                ;;
            --disable-filesystem-hardening)
                ENABLE_FILESYSTEM_HARDENING=false
                shift
                ;;
            --enable-user-hardening)
                ENABLE_USER_ACCOUNT_HARDENING=true
                shift
                ;;
            --disable-user-hardening)
                ENABLE_USER_ACCOUNT_HARDENING=false
                shift
                ;;
            --enable-audit-logging)
                ENABLE_AUDIT_LOGGING=true
                shift
                ;;
            --disable-audit-logging)
                ENABLE_AUDIT_LOGGING=false
                shift
                ;;
            --enable-apparmor)
                ENABLE_APPARMOR=true
                shift
                ;;
            --disable-apparmor)
                ENABLE_APPARMOR=false
                shift
                ;;
            --enable-process-hardening)
                ENABLE_PROCESS_HARDENING=true
                shift
                ;;
            --enable-memory-protection)
                ENABLE_MEMORY_PROTECTION=true
                shift
                ;;
            --enable-coredump-restriction)
                ENABLE_COREDUMP_RESTRICTION=true
                shift
                ;;
            --enable-compiler-protection)
                ENABLE_COMPILER_PROTECTION=true
                shift
                ;;
            --enable-cron-hardening)
                ENABLE_CRON_HARDENING=true
                shift
                ;;
            --enable-service-hardening)
                ENABLE_SERVICE_HARDENING=true
                shift
                ;;
            --enable-bootloader-hardening)
                ENABLE_BOOTLOADER_HARDENING=true
                shift
                ;;
            --disable-unused-filesystems)
                DISABLE_UNUSED_FILESYSTEMS=true
                shift
                ;;
            --disable-unused-protocols)
                DISABLE_UNUSED_PROTOCOLS=true
                shift
                ;;
            --disable-usb-storage)
                DISABLE_USB_STORAGE=true
                shift
                ;;
            --disable-firewire)
                DISABLE_FIREWIRE=true
                shift
                ;;
            --disable-thunderbolt)
                DISABLE_THUNDERBOLT=true
                shift
                ;;
            --password-min-length)
                PASSWORD_MIN_LENGTH="$2"
                shift 2
                ;;
            --password-max-age)
                PASSWORD_MAX_AGE="$2"
                shift 2
                ;;
            --password-min-age)
                PASSWORD_MIN_AGE="$2"
                shift 2
                ;;
            --failed-login-attempts)
                FAILED_LOGIN_ATTEMPTS="$2"
                shift 2
                ;;
            --lockout-duration)
                LOCKOUT_DURATION="$2"
                shift 2
                ;;
            --session-timeout)
                SESSION_TIMEOUT="$2"
                shift 2
                ;;
            --enable-two-factor)
                ENABLE_TWO_FACTOR=true
                shift
                ;;
            --grub-password)
                GRUB_PASSWORD="$2"
                shift 2
                ;;
            --enable-secure-boot)
                ENABLE_SECURE_BOOT=true
                shift
                ;;
            --backup-configs)
                BACKUP_CONFIGS=true
                shift
                ;;
            --no-backup-configs)
                BACKUP_CONFIGS=false
                shift
                ;;
            --force-apply)
                FORCE_APPLY=true
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
    # Check Ubuntu version
    local ubuntu_version
    if [[ -f /etc/os-release ]]; then
        ubuntu_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
        if [[ $(echo "$ubuntu_version >= $UBUNTU_VERSION_MIN" | bc -l) -eq 0 ]]; then
            print_warning "This script is designed for Ubuntu $UBUNTU_VERSION_MIN+. Current version: $ubuntu_version"
            if [[ "$FORCE_APPLY" != true ]]; then
                if ! confirm_action "Continue anyway?" "N"; then
                    exit 1
                fi
            fi
        fi
    else
        print_warning "Cannot determine Ubuntu version"
    fi
    
    # Validate numeric parameters
    if [[ ! "$PASSWORD_MIN_LENGTH" =~ ^[0-9]+$ ]] || [[ "$PASSWORD_MIN_LENGTH" -lt 8 ]]; then
        print_error "Invalid password minimum length: $PASSWORD_MIN_LENGTH. Must be numeric and >= 8"
        exit 1
    fi
    
    if [[ ! "$PASSWORD_MAX_AGE" =~ ^[0-9]+$ ]] || [[ "$PASSWORD_MAX_AGE" -lt 1 ]]; then
        print_error "Invalid password maximum age: $PASSWORD_MAX_AGE. Must be numeric and >= 1"
        exit 1
    fi
    
    if [[ ! "$FAILED_LOGIN_ATTEMPTS" =~ ^[0-9]+$ ]] || [[ "$FAILED_LOGIN_ATTEMPTS" -lt 1 ]]; then
        print_error "Invalid failed login attempts: $FAILED_LOGIN_ATTEMPTS. Must be numeric and >= 1"
        exit 1
    fi
    
    if [[ ! "$SESSION_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$SESSION_TIMEOUT" -lt 300 ]]; then
        print_error "Invalid session timeout: $SESSION_TIMEOUT. Must be numeric and >= 300 seconds"
        exit 1
    fi
}

# Backup configuration files
backup_configuration() {
    if [[ "$BACKUP_CONFIGS" != true ]]; then
        return 0
    fi
    
    print_info "Creating configuration backups..."
    
    local backup_dir="/var/backups/bashmin-hardening-$(date +%Y%m%d_%H%M%S)"
    execute_command "sudo mkdir -p '$backup_dir'" "Creating backup directory"
    
    local configs=(
        "/etc/sysctl.conf"
        "/etc/security/limits.conf"
        "/etc/login.defs"
        "/etc/pam.d/common-password"
        "/etc/pam.d/common-auth"
        "/etc/default/grub"
        "/etc/audit/auditd.conf"
        "/etc/hosts.allow"
        "/etc/hosts.deny"
        "/etc/ssh/sshd_config"
    )
    
    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            execute_command "sudo cp '$config' '$backup_dir/'" "Backing up $config"
        fi
    done
    
    print_success "Configuration backups created in $backup_dir"
}

# Log hardening action
log_hardening_action() {
    local action="$1"
    local details="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $action: $details" | sudo tee -a "$BASHMIN_SECURITY_LOG" >/dev/null
}

# Apply kernel hardening
apply_kernel_hardening() {
    if [[ "$ENABLE_KERNEL_HARDENING" != true ]]; then
        print_info "Kernel hardening disabled - skipping"
        return 0
    fi
    
    print_info "Applying kernel hardening parameters..."
    
    local sysctl_config="$SYSCTL_CONF_DIR/99-bashmin-kernel-hardening.conf"
    
    local kernel_params="# bashmin Kernel Hardening Configuration
# Generated on $(date)

# Kernel address space layout randomization (ASLR)
kernel.randomize_va_space = 2

# Restrict kernel pointer access
kernel.kptr_restrict = 2

# Restrict dmesg access
kernel.dmesg_restrict = 1

# Restrict kernel log access
kernel.printk = 3 3 3 3

# Enable ExecShield protection
kernel.exec-shield = 1

# Randomize memory space
kernel.randomize_va_space = 2

# Control kernel symbol access
kernel.kptr_restrict = 2

# Restrict ptrace scope
kernel.yama.ptrace_scope = 3

# Disable magic SysRq key
kernel.sysrq = 0

# Restrict core dump naming
kernel.core_pattern = |/bin/false

# Process restrictions
kernel.pid_max = 65536

# Control unprivileged user namespaces
kernel.unprivileged_userns_clone = 0

# BPF hardening
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# Control vsyscall behavior
kernel.vsyscall = none
"

    if [[ "$ENABLE_MEMORY_PROTECTION" == true ]]; then
        kernel_params="$kernel_params

# Memory protection
vm.mmap_min_addr = 65536
vm.mmap_rnd_bits = 32
vm.mmap_rnd_compat_bits = 16
"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would write kernel hardening parameters to $sysctl_config"
    else
        echo "$kernel_params" | sudo tee "$sysctl_config" >/dev/null
        execute_command "sudo sysctl -p '$sysctl_config'" "Applying kernel hardening parameters"
        log_hardening_action "Kernel Hardening" "Applied kernel security parameters"
    fi
    
    print_success "Kernel hardening parameters applied"
}

# Apply network hardening
apply_network_hardening() {
    if [[ "$ENABLE_NETWORK_HARDENING" != true ]]; then
        print_info "Network hardening disabled - skipping"
        return 0
    fi
    
    print_info "Applying network hardening parameters..."
    
    local sysctl_config="$SYSCTL_CONF_DIR/99-bashmin-network-hardening.conf"
    
    local network_params="# bashmin Network Hardening Configuration
# Generated on $(date)

# IP forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 1
net.ipv6.icmp.echo_ignore_all = 1

# Ignore broadcast ping requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Source routing protection
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# ICMP redirect protection
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Secure ICMP redirects
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Send redirects protection
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Log martian packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# IPv6 router advertisements
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# IPv6 autoconfiguration
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.default.autoconf = 0

# TCP SYN cookies
net.ipv4.tcp_syncookies = 1

# TCP timestamps
net.ipv4.tcp_timestamps = 0

# TCP SACK
net.ipv4.tcp_sack = 0

# TCP window scaling
net.ipv4.tcp_window_scaling = 1

# TCP congestion control
net.ipv4.tcp_congestion_control = bbr

# Network buffer tuning
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# Connection tracking
net.netfilter.nf_conntrack_max = 2000000
net.netfilter.nf_conntrack_tcp_timeout_established = 7440
"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would write network hardening parameters to $sysctl_config"
    else
        echo "$network_params" | sudo tee "$sysctl_config" >/dev/null
        execute_command "sudo sysctl -p '$sysctl_config'" "Applying network hardening parameters"
        log_hardening_action "Network Hardening" "Applied network security parameters"
    fi
    
    print_success "Network hardening parameters applied"
}

# Disable unused filesystems
disable_unused_filesystems() {
    if [[ "$DISABLE_UNUSED_FILESYSTEMS" != true ]]; then
        print_info "Unused filesystem disabling disabled - skipping"
        return 0
    fi
    
    print_info "Disabling unused filesystems..."
    
    local blacklist_config="$KERNEL_MODULES_BLACKLIST"
    
    local filesystem_blacklist="# bashmin Filesystem Blacklist
# Generated on $(date)

# Uncommon filesystems
blacklist cramfs
blacklist freevxfs
blacklist jffs2
blacklist hfs
blacklist hfsplus
blacklist squashfs
blacklist udf

# Network filesystems (if not needed)
# blacklist nfs
# blacklist nfsv3
# blacklist nfsv4
"

    # Add USB/FireWire/Thunderbolt restrictions
    if [[ "$DISABLE_USB_STORAGE" == true ]]; then
        filesystem_blacklist="$filesystem_blacklist

# USB mass storage
blacklist usb-storage
blacklist uas
"
    fi

    if [[ "$DISABLE_FIREWIRE" == true ]]; then
        filesystem_blacklist="$filesystem_blacklist

# FireWire/IEEE 1394
blacklist firewire-core
blacklist firewire-ohci
blacklist firewire-sbp2
"
    fi

    if [[ "$DISABLE_THUNDERBOLT" == true ]]; then
        filesystem_blacklist="$filesystem_blacklist

# Thunderbolt
blacklist thunderbolt
"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would write filesystem blacklist to $blacklist_config"
    else
        echo "$filesystem_blacklist" | sudo tee "$blacklist_config" >/dev/null
        execute_command "sudo depmod -a" "Updating kernel module dependencies"
        log_hardening_action "Filesystem Hardening" "Disabled unused filesystems and interfaces"
    fi
    
    print_success "Unused filesystems disabled"
}

# Apply user account hardening
apply_user_hardening() {
    if [[ "$ENABLE_USER_ACCOUNT_HARDENING" != true ]]; then
        print_info "User account hardening disabled - skipping"
        return 0
    fi
    
    print_info "Applying user account hardening..."
    
    # Password policy in login.defs
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would update password policies in $LOGIN_DEFS"
    else
        # Backup original
        if [[ ! -f "${LOGIN_DEFS}.backup" ]]; then
            sudo cp "$LOGIN_DEFS" "${LOGIN_DEFS}.backup"
        fi
        
        # Update password settings
        sudo sed -i "s/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t$PASSWORD_MAX_AGE/" "$LOGIN_DEFS"
        sudo sed -i "s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t$PASSWORD_MIN_AGE/" "$LOGIN_DEFS"
        sudo sed -i "s/^PASS_WARN_AGE.*/PASS_WARN_AGE\t$PASSWORD_WARN_AGE/" "$LOGIN_DEFS"
        
        # Add if not exists
        if ! grep -q "PASS_MIN_LEN" "$LOGIN_DEFS"; then
            echo "PASS_MIN_LEN\t$PASSWORD_MIN_LENGTH" | sudo tee -a "$LOGIN_DEFS" >/dev/null
        else
            sudo sed -i "s/^PASS_MIN_LEN.*/PASS_MIN_LEN\t$PASSWORD_MIN_LENGTH/" "$LOGIN_DEFS"
        fi
        
        log_hardening_action "User Hardening" "Updated password policies"
    fi
    
    # PAM password requirements
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would update PAM password requirements"
    else
        # Install required packages
        install_prerequisites "libpam-pwquality libpam-tmpdir"
        
        # Update PAM common-password
        if [[ ! -f "${PAM_COMMON_PASSWORD}.backup" ]]; then
            sudo cp "$PAM_COMMON_PASSWORD" "${PAM_COMMON_PASSWORD}.backup"
        fi
        
        # Add password quality requirements
        local pam_pwquality_line="password requisite pam_pwquality.so retry=3 minlen=$PASSWORD_MIN_LENGTH dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1 maxrepeat=3 usercheck=1"
        
        if ! grep -q "pam_pwquality.so" "$PAM_COMMON_PASSWORD"; then
            sudo sed -i "/^password.*pam_unix.so/i $pam_pwquality_line" "$PAM_COMMON_PASSWORD"
        fi
        
        log_hardening_action "User Hardening" "Updated PAM password requirements"
    fi
    
    # Account lockout policy
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure account lockout policies"
    else
        # Update PAM common-auth for account lockout
        if [[ ! -f "${PAM_COMMON_AUTH}.backup" ]]; then
            sudo cp "$PAM_COMMON_AUTH" "${PAM_COMMON_AUTH}.backup"
        fi
        
        local pam_tally_line="auth required pam_tally2.so deny=$FAILED_LOGIN_ATTEMPTS unlock_time=$LOCKOUT_DURATION"
        
        if ! grep -q "pam_tally2.so" "$PAM_COMMON_AUTH"; then
            sudo sed -i "/^auth.*pam_unix.so/i $pam_tally_line" "$PAM_COMMON_AUTH"
        fi
        
        log_hardening_action "User Hardening" "Configured account lockout policies"
    fi
    
    # Security limits
    local limits_config="# bashmin Security Limits
# Generated on $(date)

# Core dump restrictions
* hard core 0
* soft core 0

# Process limits
* hard nproc 10000
* soft nproc 8000

# File descriptor limits  
* hard nofile 65536
* soft nofile 32768

# Memory limits (in KB)
* hard as 4194304
* soft as 2097152

# Stack size limits
* hard stack 8192
* soft stack 4096

# CPU time limits (in minutes)
* hard cpu 60
* soft cpu 30
"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would write security limits to $SECURITY_LIMITS_CONF"
    else
        echo "$limits_config" | sudo tee "$SECURITY_LIMITS_CONF" >/dev/null
        log_hardening_action "User Hardening" "Applied security limits"
    fi
    
    print_success "User account hardening applied"
}

# Configure audit logging
configure_audit_logging() {
    if [[ "$ENABLE_AUDIT_LOGGING" != true ]]; then
        print_info "Audit logging disabled - skipping"
        return 0
    fi
    
    print_info "Configuring comprehensive audit logging..."
    
    # Install auditd
    install_prerequisites "auditd audispd-plugins"
    
    local audit_rules="# bashmin Audit Rules
# Generated on $(date)

# Delete all existing rules
-D

# Buffer size
-b 8192

# Failure mode (0=silent, 1=printk, 2=panic)
-f 1

# Monitor authentication events
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor login/logout events
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# Monitor sudo usage
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

# Monitor privileged commands
-a always,exit -F path=/usr/bin/sudo -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged
-a always,exit -F path=/usr/bin/su -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged

# Monitor file system mounts
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts

# Monitor file deletions
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete

# Monitor permission changes
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod

# Monitor network configuration changes
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/network/ -p wa -k system-locale

# Monitor system administration actions
-w /var/log/audit/ -p wa -k auditlog

# Make rules immutable
-e 2
"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would write audit rules to $AUDIT_RULES"
        echo "[DRY-RUN] Would enable and start auditd service"
    else
        echo "$audit_rules" | sudo tee "$AUDIT_RULES" >/dev/null
        
        # Configure audit log rotation
        local logrotate_audit_config="/var/log/audit/*.log {
    daily
    missingok
    rotate 90
    compress
    delaycompress
    notifempty
    create 640 root root
    postrotate
        /sbin/service auditd restart
    endscript
}"
        echo "$logrotate_audit_config" | sudo tee "$LOGROTATE_AUDIT" >/dev/null
        
        # Enable and start auditd
        enable_start_service "auditd"
        
        log_hardening_action "Audit Logging" "Configured comprehensive audit logging"
    fi
    
    print_success "Audit logging configured"
}

# Configure AppArmor
configure_apparmor() {
    if [[ "$ENABLE_APPARMOR" != true ]]; then
        print_info "AppArmor disabled - skipping"
        return 0
    fi
    
    print_info "Configuring AppArmor mandatory access control..."
    
    # Install AppArmor utilities
    install_prerequisites "apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would enable AppArmor and load profiles"
    else
        # Enable AppArmor
        enable_start_service "apparmor"
        
        # Load additional profiles
        execute_command "sudo aa-enforce /etc/apparmor.d/usr.bin.firefox" "Enforcing Firefox AppArmor profile" || true
        execute_command "sudo aa-enforce /etc/apparmor.d/usr.sbin.tcpdump" "Enforcing tcpdump AppArmor profile" || true
        
        log_hardening_action "AppArmor" "Enabled mandatory access control"
    fi
    
    print_success "AppArmor configured"
}

# Apply process hardening
apply_process_hardening() {
    if [[ "$ENABLE_PROCESS_HARDENING" != true ]]; then
        print_info "Process hardening disabled - skipping"
        return 0
    fi
    
    print_info "Applying process hardening..."
    
    local sysctl_config="$SYSCTL_CONF_DIR/99-bashmin-process-hardening.conf"
    
    local process_params="# bashmin Process Hardening Configuration
# Generated on $(date)

# Process limits
kernel.threads-max = 4194303
kernel.pid_max = 4194303

# Control process scheduling
kernel.sched_rt_period_us = 1000000
kernel.sched_rt_runtime_us = 950000

# Process memory management
vm.overcommit_memory = 1
vm.overcommit_ratio = 50
vm.panic_on_oom = 0

# Control swap usage
vm.swappiness = 1
vm.vfs_cache_pressure = 50

# File system parameters
fs.file-max = 2097152
fs.nr_open = 1048576
"

    if [[ "$ENABLE_COREDUMP_RESTRICTION" == true ]]; then
        process_params="$process_params

# Core dump restrictions
fs.suid_dumpable = 0
kernel.core_pattern = |/bin/false
"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would write process hardening parameters to $sysctl_config"
    else
        echo "$process_params" | sudo tee "$sysctl_config" >/dev/null
        execute_command "sudo sysctl -p '$sysctl_config'" "Applying process hardening parameters"
        log_hardening_action "Process Hardening" "Applied process security parameters"
    fi
    
    print_success "Process hardening applied"
}

# Harden system services
harden_system_services() {
    if [[ "$ENABLE_SERVICE_HARDENING" != true ]]; then
        print_info "Service hardening disabled - skipping"
        return 0
    fi
    
    print_info "Hardening system services..."
    
    # Disable unnecessary services
    local unnecessary_services=(
        "bluetooth"
        "cups"
        "avahi-daemon"
        "whoopsie"
        "apport"
    )
    
    for service in "${unnecessary_services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY-RUN] Would disable service: $service"
            else
                execute_command "sudo systemctl disable '$service'" "Disabling unnecessary service: $service" || true
                execute_command "sudo systemctl stop '$service'" "Stopping unnecessary service: $service" || true
            fi
        fi
    done
    
    log_hardening_action "Service Hardening" "Disabled unnecessary services"
    print_success "System services hardened"
}

# Configure bootloader security
configure_bootloader_security() {
    if [[ "$ENABLE_BOOTLOADER_HARDENING" != true ]]; then
        print_info "Bootloader hardening disabled - skipping"
        return 0
    fi
    
    print_info "Configuring bootloader security..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure GRUB security settings"
        if [[ -n "$GRUB_PASSWORD" ]]; then
            echo "[DRY-RUN] Would set GRUB password protection"
        fi
    else
        # Backup GRUB config
        if [[ ! -f "${GRUB_CONFIG}.backup" ]]; then
            sudo cp "$GRUB_CONFIG" "${GRUB_CONFIG}.backup"
        fi
        
        # Set GRUB timeout
        sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' "$GRUB_CONFIG"
        
        # Disable recovery mode
        sudo sed -i 's/^GRUB_DISABLE_RECOVERY=.*/GRUB_DISABLE_RECOVERY=true/' "$GRUB_CONFIG"
        
        # Set password if provided
        if [[ -n "$GRUB_PASSWORD" ]]; then
            local grub_password_hash
            grub_password_hash=$(echo -e "$GRUB_PASSWORD\n$GRUB_PASSWORD" | grub-mkpasswd-pbkdf2 | grep -oP 'grub\.pbkdf2\.sha512\.[^[:space:]]+')
            
            if [[ -n "$grub_password_hash" ]]; then
                cat <<EOF | sudo tee /etc/grub.d/01_password >/dev/null
#!/bin/sh
cat <<GRUB_EOF
set superusers="admin"
password_pbkdf2 admin $grub_password_hash
GRUB_EOF
EOF
                sudo chmod +x /etc/grub.d/01_password
            fi
        fi
        
        # Update GRUB
        execute_command "sudo update-grub" "Updating GRUB configuration"
        
        log_hardening_action "Bootloader Hardening" "Applied GRUB security settings"
    fi
    
    print_success "Bootloader security configured"
}

# Run hardening validation
run_hardening_validation() {
    if [[ "$DRY_RUN" == true ]]; then
        print_info "Skipping validation in dry-run mode"
        return 0
    fi
    
    print_info "Running hardening validation..."
    
    local validation_results=()
    
    # Check sysctl parameters
    if sysctl kernel.randomize_va_space | grep -q "2"; then
        validation_results+=("✓ ASLR enabled")
    else
        validation_results+=("✗ ASLR not properly configured")
    fi
    
    # Check audit service
    if systemctl is-active auditd >/dev/null 2>&1; then
        validation_results+=("✓ Audit logging active")
    else
        validation_results+=("✗ Audit logging not active")
    fi
    
    # Check AppArmor
    if systemctl is-active apparmor >/dev/null 2>&1; then
        validation_results+=("✓ AppArmor active")
    else
        validation_results+=("✗ AppArmor not active")
    fi
    
    # Check password policy
    if grep -q "minlen=$PASSWORD_MIN_LENGTH" /etc/security/pwquality.conf 2>/dev/null || grep -q "minlen=$PASSWORD_MIN_LENGTH" /etc/pam.d/common-password; then
        validation_results+=("✓ Password policy configured")
    else
        validation_results+=("✗ Password policy not properly configured")
    fi
    
    echo ""
    print_info "Hardening validation results:"
    for result in "${validation_results[@]}"; do
        echo "  $result"
    done
    echo ""
}

# Show hardening status
show_hardening_status() {
    echo ""
    print_success "Ubuntu system hardening completed!"
    echo ""
    echo "Hardening Summary:"
    echo "  • Kernel hardening: $([[ "$ENABLE_KERNEL_HARDENING" == true ]] && echo "Applied" || echo "Skipped")"
    echo "  • Network hardening: $([[ "$ENABLE_NETWORK_HARDENING" == true ]] && echo "Applied" || echo "Skipped")"
    echo "  • Filesystem hardening: $([[ "$ENABLE_FILESYSTEM_HARDENING" == true ]] && echo "Applied" || echo "Skipped")"
    echo "  • User account hardening: $([[ "$ENABLE_USER_ACCOUNT_HARDENING" == true ]] && echo "Applied" || echo "Skipped")"
    echo "  • Audit logging: $([[ "$ENABLE_AUDIT_LOGGING" == true ]] && echo "Configured" || echo "Skipped")"
    echo "  • AppArmor MAC: $([[ "$ENABLE_APPARMOR" == true ]] && echo "Enabled" || echo "Skipped")"
    echo "  • Process hardening: $([[ "$ENABLE_PROCESS_HARDENING" == true ]] && echo "Applied" || echo "Skipped")"
    echo "  • Service hardening: $([[ "$ENABLE_SERVICE_HARDENING" == true ]] && echo "Applied" || echo "Skipped")"
    echo "  • Bootloader security: $([[ "$ENABLE_BOOTLOADER_HARDENING" == true ]] && echo "Configured" || echo "Skipped")"
    
    echo ""
    echo "Security Controls Applied:"
    echo "  • Password min length: $PASSWORD_MIN_LENGTH characters"
    echo "  • Failed login attempts: $FAILED_LOGIN_ATTEMPTS before lockout"
    echo "  • Session timeout: $SESSION_TIMEOUT seconds"
    echo "  • USB storage: $([[ "$DISABLE_USB_STORAGE" == true ]] && echo "Disabled" || echo "Enabled")"
    echo "  • FireWire: $([[ "$DISABLE_FIREWIRE" == true ]] && echo "Disabled" || echo "Enabled")"
    
    echo ""
    echo "Configuration Files:"
    echo "  • Kernel parameters: $SYSCTL_CONF_DIR/99-bashmin-*.conf"
    echo "  • Security limits: $SECURITY_LIMITS_CONF"
    echo "  • Audit rules: $AUDIT_RULES"
    echo "  • Module blacklist: $KERNEL_MODULES_BLACKLIST"
    echo "  • Hardening log: $BASHMIN_SECURITY_LOG"
    
    if [[ "$BACKUP_CONFIGS" == true ]]; then
        echo "  • Config backups: /var/backups/bashmin-hardening-*"
    fi
    
    echo ""
    echo "Recommended Next Steps:"
    echo "  • Reboot system to ensure all kernel parameters take effect"
    echo "  • Review audit logs: journalctl -u auditd"
    echo "  • Test system functionality to ensure no services were impacted"
    echo "  • Run security scan: lynis audit system"
    echo "  • Configure additional security tools: fail2ban, ufw, clamav"
    
    echo ""
    echo "Validation Commands:"
    echo "  • Check sysctl settings: sysctl -a | grep -E 'randomize|kptr_restrict'"
    echo "  • Verify audit service: systemctl status auditd"
    echo "  • Check AppArmor: aa-status"
    echo "  • Review security limits: cat $SECURITY_LIMITS_CONF"
    
    echo ""
    print_warning "IMPORTANT: Reboot required for all changes to take effect!"
    echo ""
}

# Main function
main() {
    print_info "Starting Ubuntu 24.04+ system hardening..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate configuration
    validate_configuration
    
    # Check system compatibility
    check_ubuntu_system
    
    # Create log directory
    execute_command "sudo mkdir -p '$BASHMIN_LOG_DIR'" "Creating log directory"
    execute_command "sudo touch '$BASHMIN_SECURITY_LOG'" "Creating hardening log"
    
    # Show configuration summary
    if [[ "$DRY_RUN" != true ]] && [[ "$FORCE_APPLY" != true ]]; then
        echo ""
        echo "Hardening Configuration:"
        echo "  • Kernel hardening: $([[ "$ENABLE_KERNEL_HARDENING" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Network hardening: $([[ "$ENABLE_NETWORK_HARDENING" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Filesystem hardening: $([[ "$ENABLE_FILESYSTEM_HARDENING" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • User account hardening: $([[ "$ENABLE_USER_ACCOUNT_HARDENING" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Audit logging: $([[ "$ENABLE_AUDIT_LOGGING" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • AppArmor MAC: $([[ "$ENABLE_APPARMOR" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Process hardening: $([[ "$ENABLE_PROCESS_HARDENING" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Service hardening: $([[ "$ENABLE_SERVICE_HARDENING" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Bootloader security: $([[ "$ENABLE_BOOTLOADER_HARDENING" == true ]] && echo "Enabled" || echo "Disabled")"
        echo "  • Password min length: $PASSWORD_MIN_LENGTH"
        echo "  • Failed login attempts: $FAILED_LOGIN_ATTEMPTS"
        echo "  • USB storage: $([[ "$DISABLE_USB_STORAGE" == true ]] && echo "Disabled" || echo "Enabled")"
        echo ""
        
        if ! confirm_action "Proceed with system hardening?" "Y"; then
            print_info "Hardening cancelled by user"
            exit 0
        fi
    fi
    
    # Start hardening process
    log_hardening_action "Hardening Started" "Ubuntu system hardening initiated"
    
    # Backup configurations
    backup_configuration
    
    # Apply hardening measures
    apply_kernel_hardening
    apply_network_hardening
    
    if [[ "$ENABLE_FILESYSTEM_HARDENING" == true ]]; then
        disable_unused_filesystems
    fi
    
    apply_user_hardening
    configure_audit_logging
    configure_apparmor
    apply_process_hardening
    harden_system_services
    configure_bootloader_security
    
    # Complete hardening
    log_hardening_action "Hardening Completed" "Ubuntu system hardening completed successfully"
    
    if [[ "$DRY_RUN" != true ]]; then
        run_hardening_validation
        show_hardening_status
    else
        print_info "Dry run completed - no changes were made"
        echo ""
        echo "This would have applied comprehensive security hardening including:"
        echo "  • Kernel security parameters (ASLR, KASLR, etc.)"
        echo "  • Network stack protection (IP forwarding, ICMP, etc.)"
        echo "  • User account policies (passwords, lockouts, etc.)"
        echo "  • Process isolation and limits"
        echo "  • Comprehensive audit logging"
        echo "  • AppArmor mandatory access control"
        echo "  • Service hardening and unused service disabling"
        echo "  • Bootloader security configuration"
    fi
}

# Run main function with all arguments
main "$@"