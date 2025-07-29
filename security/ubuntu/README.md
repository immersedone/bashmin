# Ubuntu 24.04+ System Hardening

A comprehensive system hardening script implementing CIS benchmarks, NIST guidelines, and security best practices for Ubuntu 24.04+ servers.

## Overview

This hardening script applies multi-layered security controls across eight critical security domains:

- **Kernel Security**: ASLR, KASLR, memory protection, and kernel parameter hardening
- **Network Protection**: IP forwarding control, ICMP protection, and network stack hardening
- **Filesystem Security**: Unused filesystem disabling and interface restrictions
- **User Account Security**: Password policies, account lockouts, and session controls
- **Process Isolation**: Process limits, memory controls, and core dump restrictions
- **Audit Logging**: Comprehensive system activity monitoring and logging
- **AppArmor MAC**: Mandatory access control for enhanced application isolation
- **Service Hardening**: Unnecessary service disabling and security configuration

## Installation

### Quick Start

```bash
# Basic system hardening with all defaults
sudo ./harden.sh

# High-security server configuration
sudo ./harden.sh --enable-two-factor --disable-usb-storage --grub-password "SecurePass123"

# Preview all changes without applying
sudo ./harden.sh --dry-run --verbose
```

### Hardening Options

| Category | Option | Description | Default |
|----------|--------|-------------|---------|
| **Kernel** | `--enable-kernel-hardening` | Enable kernel security parameters | Enabled |
| | `--enable-memory-protection` | Enable memory protection features | Enabled |
| | `--enable-process-hardening` | Enable process isolation | Enabled |
| **Network** | `--enable-network-hardening` | Enable network stack hardening | Enabled |
| | `--disable-unused-protocols` | Disable unused network protocols | Enabled |
| **Filesystem** | `--enable-filesystem-hardening` | Enable filesystem security | Enabled |
| | `--disable-unused-filesystems` | Disable unused filesystem types | Enabled |
| | `--disable-usb-storage` | Disable USB mass storage | Disabled |
| | `--disable-firewire` | Disable FireWire/IEEE 1394 | Enabled |
| | `--disable-thunderbolt` | Disable Thunderbolt interfaces | Disabled |
| **Users** | `--enable-user-hardening` | Enable user account security | Enabled |
| | `--password-min-length LENGTH` | Minimum password length | 12 |
| | `--password-max-age DAYS` | Maximum password age | 90 |
| | `--failed-login-attempts COUNT` | Failed login limit | 5 |
| | `--lockout-duration SECONDS` | Account lockout duration | 900 |
| | `--session-timeout SECONDS` | Session timeout | 1800 |
| | `--enable-two-factor` | Enable 2FA authentication | Disabled |
| **Audit** | `--enable-audit-logging` | Enable comprehensive auditing | Enabled |
| **AppArmor** | `--enable-apparmor` | Enable mandatory access control | Enabled |
| **Services** | `--enable-service-hardening` | Harden system services | Enabled |
| **Boot** | `--enable-bootloader-hardening` | Secure GRUB bootloader | Enabled |
| | `--grub-password PASSWORD` | Set GRUB password protection | None |
| | `--enable-secure-boot` | Enable UEFI Secure Boot | Disabled |

## Security Domains

### 🛡️ Kernel Security Hardening

Implements critical kernel-level security controls:

```bash
# Applied kernel parameters
kernel.randomize_va_space = 2          # Enable ASLR
kernel.kptr_restrict = 2               # Restrict kernel pointers
kernel.dmesg_restrict = 1              # Restrict dmesg access
kernel.yama.ptrace_scope = 3           # Restrict ptrace scope
kernel.sysrq = 0                       # Disable magic SysRq
kernel.unprivileged_userns_clone = 0   # Disable user namespaces
kernel.unprivileged_bpf_disabled = 1   # Disable unprivileged BPF
```

**Security Benefits:**
- Address Space Layout Randomization (ASLR)
- Kernel Address Space Layout Randomization (KASLR)
- Memory corruption exploitation prevention
- Privilege escalation mitigation

### 🌐 Network Stack Protection

Comprehensive network security hardening:

```bash
# Network security parameters
net.ipv4.ip_forward = 0                # Disable IP forwarding
net.ipv4.icmp_echo_ignore_all = 1      # Ignore ping requests
net.ipv4.conf.all.accept_source_route = 0  # Block source routing
net.ipv4.conf.all.accept_redirects = 0     # Block ICMP redirects
net.ipv4.tcp_syncookies = 1                # Enable SYN cookies
net.ipv4.tcp_timestamps = 0               # Disable TCP timestamps
```

**Protection Against:**
- Network reconnaissance
- ICMP-based attacks
- Source routing attacks
- ICMP redirect attacks
- TCP SYN flood attacks

### 💾 Filesystem and Interface Security

Controls access to filesystems and hardware interfaces:

```bash
# Disabled filesystems
blacklist cramfs         # Compressed RAM filesystem
blacklist freevxfs       # Legacy filesystem
blacklist usb-storage    # USB mass storage (optional)
blacklist firewire-core  # FireWire interface
blacklist thunderbolt    # Thunderbolt interface (optional)
```

**Security Benefits:**
- Reduced attack surface
- Prevention of unauthorized data exfiltration
- Protection against hardware-based attacks
- Compliance with security policies

### 👤 User Account Security

Comprehensive user account and authentication hardening:

```bash
# Password policy enforcement
PASS_MIN_LEN 12          # Minimum password length
PASS_MAX_DAYS 90         # Maximum password age
PASS_MIN_DAYS 1          # Minimum password age
PASS_WARN_AGE 7          # Password expiration warning

# Account lockout policy
auth required pam_tally2.so deny=5 unlock_time=900
```

**Implemented Controls:**
- Strong password requirements
- Account lockout after failed attempts
- Password aging policies
- Session timeout enforcement
- Two-factor authentication support

### 🔍 Comprehensive Audit Logging

System-wide activity monitoring and logging:

```bash
# Critical audit points
-w /etc/passwd -p wa -k identity        # Monitor user accounts
-w /etc/sudoers -p wa -k scope          # Monitor privilege changes
-w /var/log/audit/ -p wa -k auditlog    # Monitor audit logs
```

**Monitored Activities:**
- User account modifications
- Privilege escalation attempts
- File system mount operations
- File deletion and permission changes
- Network configuration changes
- System administration actions

### 🛡️ AppArmor Mandatory Access Control

Enhanced application isolation and access control:

```bash
# AppArmor profiles enforcement
aa-enforce /etc/apparmor.d/usr.bin.firefox
aa-enforce /etc/apparmor.d/usr.sbin.tcpdump
```

**Security Benefits:**
- Application sandboxing
- Privilege confinement
- Access control enforcement
- Exploit containment

### ⚙️ Process and Memory Hardening

Advanced process isolation and memory protection:

```bash
# Process limits and controls
kernel.threads-max = 4194303
vm.overcommit_memory = 1
vm.swappiness = 1
fs.suid_dumpable = 0
kernel.core_pattern = |/bin/false
```

**Protection Features:**
- Process resource limits
- Core dump restrictions
- Memory overcommit control
- Swap usage optimization

### 🔧 Service and Boot Security

System service hardening and secure boot configuration:

```bash
# Disabled unnecessary services
bluetooth, cups, avahi-daemon, whoopsie, apport

# GRUB security settings
GRUB_TIMEOUT=5
GRUB_DISABLE_RECOVERY=true
```

## Usage Examples

### Standard Server Hardening

```bash
# Complete hardening with security defaults
sudo ./harden.sh

# Web server with extended session timeout
sudo ./harden.sh --session-timeout 3600 --password-min-length 14
```

### High-Security Environment

```bash
# Maximum security configuration
sudo ./harden.sh \
    --enable-two-factor \
    --disable-usb-storage \
    --disable-thunderbolt \
    --grub-password "ComplexBootPassword123!" \
    --password-min-length 16 \
    --failed-login-attempts 3 \
    --lockout-duration 1800
```

### Corporate Environment

```bash
# Corporate policy compliance
sudo ./harden.sh \
    --password-max-age 60 \
    --session-timeout 900 \
    --failed-login-attempts 3 \
    --enable-secure-boot
```

### Development Server

```bash
# Balanced security for development
sudo ./harden.sh \
    --session-timeout 7200 \
    --password-min-length 10 \
    --failed-login-attempts 10
```

## Validation and Monitoring

### Post-Hardening Validation

```bash
# Check kernel security parameters
sysctl -a | grep -E 'randomize|kptr_restrict|dmesg_restrict'

# Verify audit service
systemctl status auditd
journalctl -u auditd

# Check AppArmor status
aa-status

# Review security limits
cat /etc/security/limits.d/99-bashmin-security.conf

# Check disabled services
systemctl list-unit-files | grep disabled
```

### Ongoing Monitoring

```bash
# Monitor audit logs
tail -f /var/log/audit/audit.log

# Check failed login attempts
pam_tally2 --user=username

# Review security events
journalctl -f | grep -i security

# AppArmor violations
dmesg | grep -i apparmor
```

## Configuration Files

| File | Purpose |
|------|---------|
| `/etc/sysctl.d/99-bashmin-*.conf` | Kernel security parameters |
| `/etc/security/limits.d/99-bashmin-security.conf` | Process and resource limits |
| `/etc/audit/rules.d/99-bashmin.rules` | Audit logging rules |
| `/etc/modprobe.d/bashmin-blacklist.conf` | Disabled kernel modules |
| `/etc/pam.d/common-password` | Password policy enforcement |
| `/etc/pam.d/common-auth` | Authentication configuration |
| `/etc/login.defs` | User account policies |
| `/var/log/bashmin/hardening.log` | Hardening activity log |

## Compliance Frameworks

### CIS Ubuntu 24.04 Benchmark

The hardening script implements controls aligned with:
- Section 1: Initial Setup
- Section 2: Services
- Section 3: Network Configuration
- Section 4: Logging and Auditing
- Section 5: Access, Authentication and Authorization
- Section 6: System Maintenance

### NIST Cybersecurity Framework

Supports the following NIST functions:
- **Identify (ID)**: Asset and vulnerability identification
- **Protect (PR)**: Access control and protective technology
- **Detect (DE)**: Security monitoring and detection
- **Respond (RS)**: Incident response capabilities
- **Recover (RC)**: Recovery planning and improvements

### Additional Standards

- **PCI DSS**: Payment card industry security requirements
- **ISO 27001**: Information security management
- **OWASP**: Web application security guidelines
- **HIPAA**: Healthcare data protection (partial compliance)

## Troubleshooting

### Common Issues

**Service Start Failures**
```bash
# Check service status
systemctl status service-name

# Review logs
journalctl -u service-name

# Temporarily disable hardening
sudo sysctl -w parameter=original_value
```

**Login Issues**
```bash
# Reset account lockout
sudo pam_tally2 --user=username --reset

# Check password policy
sudo passwd -S username

# Review authentication logs
sudo tail -f /var/log/auth.log
```

**Network Connectivity Problems**
```bash
# Check IP forwarding (if needed)
sudo sysctl net.ipv4.ip_forward

# Review network parameters
sudo sysctl -a | grep net.ipv4

# Temporarily restore original settings
sudo sysctl -p /etc/sysctl.conf
```

### Recovery Procedures

**Emergency Access**
1. Boot into recovery mode
2. Mount filesystem as read-write
3. Restore configuration backups from `/var/backups/bashmin-hardening-*`
4. Reboot normally

**Configuration Rollback**
```bash
# Restore original configurations
sudo cp /var/backups/bashmin-hardening-*/etc/* /etc/

# Reset sysctl parameters
sudo sysctl -p /etc/sysctl.conf

# Restart affected services
sudo systemctl restart auditd apparmor
```

## Performance Impact

### Expected Performance Changes

| Component | Impact | Mitigation |
|-----------|--------|------------|
| **Audit Logging** | 1-3% CPU overhead | Log rotation, selective auditing |
| **AppArmor** | <1% performance impact | Profile optimization |
| **Memory Protection** | Minimal impact | Proper memory sizing |
| **Network Hardening** | Negligible impact | Network optimization |

### Monitoring Performance

```bash
# Check system performance
htop
iostat -x 1

# Monitor audit overhead
auditctl -s

# Check AppArmor performance
aa-status --verbose
```

## Integration with bashmin Security Suite

This hardening script integrates seamlessly with other bashmin security components:

- **fail2ban**: Provides intrusion detection and prevention
- **ufw**: Implements network firewall rules
- **lynis**: Performs security auditing and compliance checking
- **clamav**: Provides malware detection and removal
- **rkhunter**: Detects rootkits and malware
- **nikto**: Performs web vulnerability scanning

## Best Practices

### Pre-Hardening Checklist

1. **Backup System**: Create full system backup
2. **Test Environment**: Test hardening in non-production environment
3. **Document Changes**: Record all configuration modifications
4. **Plan Rollback**: Prepare rollback procedures
5. **Schedule Downtime**: Plan for potential service interruptions

### Post-Hardening Tasks

1. **Reboot System**: Ensure all kernel parameters take effect
2. **Test Functionality**: Verify all required services work correctly
3. **Monitor Logs**: Watch for security events and errors
4. **Update Documentation**: Record final configuration state
5. **Security Assessment**: Run comprehensive security scan

### Ongoing Maintenance

1. **Regular Updates**: Keep system and security tools updated
2. **Log Review**: Regularly review audit and security logs
3. **Policy Updates**: Adjust policies based on organizational needs
4. **Compliance Checks**: Perform periodic compliance validation
5. **Incident Response**: Maintain incident response procedures

Remember: System hardening is an ongoing process, not a one-time activity. Regular review and updates are essential for maintaining security posture.
