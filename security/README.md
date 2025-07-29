# bashmin Security Suite

A comprehensive enterprise-grade security toolkit providing multi-layered protection for Ubuntu/Debian servers through network security, malware detection, intrusion prevention, SSL management, and security auditing.

## 🛡️ Security Architecture

The bashmin Security Suite implements a **defense-in-depth strategy** with eight integrated security layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    bashmin Security Suite                   │
├─────────────────────────────────────────────────────────────┤
│ Layer 8: System Hardening (Ubuntu Hardening)               │
│ ├─ Kernel security parameters                               │
│ ├─ User account policies                                    │
│ └─ Compliance framework alignment                           │
├─────────────────────────────────────────────────────────────┤
│ Layer 7: Web Vulnerability Scanning (Nikto)                │
│ ├─ Web application security testing                         │
│ ├─ SSL/TLS configuration analysis                           │
│ └─ Automated vulnerability detection                        │
├─────────────────────────────────────────────────────────────┤
│ Layer 6: Rootkit Detection (rkhunter)                      │
│ ├─ Rootkit and malware detection                            │
│ ├─ File integrity monitoring                                │
│ └─ System backdoor identification                           │
├─────────────────────────────────────────────────────────────┤
│ Layer 5: Security Auditing & Compliance (Lynis)            │
│ ├─ Continuous security assessment                           │
│ ├─ Compliance framework validation                          │
│ └─ Vulnerability identification                             │
├─────────────────────────────────────────────────────────────┤
│ Layer 4: SSL/TLS Protection (Let's Encrypt)                │
│ ├─ Automated certificate management                         │
│ ├─ Web server integration                                   │
│ └─ Security header enforcement                              │
├─────────────────────────────────────────────────────────────┤
│ Layer 3: Intrusion Prevention (fail2ban)                   │
│ ├─ Real-time attack detection                               │
│ ├─ Geographic blocking                                      │
│ └─ Persistent offender tracking                             │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: Malware Detection (ClamAV)                        │
│ ├─ Real-time file scanning                                  │
│ ├─ Email attachment filtering                               │
│ └─ Quarantine management                                    │
├─────────────────────────────────────────────────────────────┤
│ Layer 1: Network Security (UFW Firewall)                   │
│ ├─ Stateful packet filtering                                │
│ ├─ Application-aware rules                                  │
│ └─ Rate limiting protection                                 │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Complete Security Suite Installation
```bash
# Install all security components with enterprise configuration
cd /var/www/vhosts/bashmin

# 1. Network Security (UFW Firewall)
sudo security/ufw/install.sh --rate-limiting --logging high

# 2. Malware Detection (ClamAV)
sudo security/clamav/install.sh --real-time-scan --email-notifications admin@company.com

# 3. Intrusion Prevention (fail2ban)
sudo security/fail2ban/install.sh --geo-blocking --slack-webhook https://hooks.slack.com/...

# 4. SSL Management (Let's Encrypt)
sudo security/letsencrypt/install.sh --auto-renewal --notification-email ssl@company.com

# 5. Security Auditing (Lynis)
sudo security/lynis/install.sh --enable-compliance --notification-email security@company.com

# 6. Rootkit Detection (rkhunter)
sudo security/rkhunter/install.sh --mail-on-warning security@company.com

# 7. Web Vulnerability Scanning (Nikto)
sudo security/nikto/install.sh --enable-cron --scan-targets "https://example.com"

# 8. System Hardening (Ubuntu 24.04+)
sudo security/ubuntu/harden.sh --enable-two-factor --grub-password "SecurePass123"
```

### Automated Security Assessment
```bash
# Generate unified security report
bashmin-security-report

# Run comprehensive security validation
bashmin-security-validation

# Check overall security posture
lynis-manage audit && fail2ban-client status && ufw status numbered && rkhunter --check
```

## 📋 Security Components

### 🔥 Network Security (UFW Firewall)
**Location:** `security/ufw/`

**Purpose:** First line of defense with stateful packet filtering and application-aware security rules.

**Key Features:**
- Stateful packet inspection
- Application profile management
- Rate limiting protection
- Geo-blocking capabilities
- DDoS mitigation
- Comprehensive logging

**Quick Commands:**
```bash
# Install with rate limiting
sudo security/ufw/install.sh --rate-limiting

# Configure application access
sudo ufw app list
sudo ufw allow 'Apache Full'

# Monitor traffic
sudo tail -f /var/log/ufw.log
```

### 🦠 Malware Detection (ClamAV)
**Location:** `security/clamav/`

**Purpose:** Real-time malware detection with quarantine management and automated scanning.

**Key Features:**
- Real-time file system scanning
- Email attachment filtering
- Quarantine management
- Performance optimization
- Automated signature updates
- Integration with mail servers

**Quick Commands:**
```bash
# Install with real-time scanning
sudo security/clamav/install.sh --real-time-scan

# Manual scan
sudo clamscan -r /home --infected --remove

# Check quarantine
sudo ls -la /opt/clamav/quarantine/
```

### 🚫 Intrusion Prevention (fail2ban)
**Location:** `security/fail2ban/`

**Purpose:** Advanced intrusion detection and prevention with geographic blocking and persistent offender tracking.

**Key Features:**
- Real-time log analysis
- Geographic IP blocking
- Persistent ban management
- Recidive protection
- Custom jail configuration
- Slack/email notifications

**Quick Commands:**
```bash
# Install with geo-blocking
sudo security/fail2ban/install.sh --geo-blocking

# Check jail status
sudo fail2ban-client status sshd

# Unban IP address
sudo fail2ban-client set sshd unbanip 192.168.1.100
```

### 🔐 SSL/TLS Management (Let's Encrypt)
**Location:** `security/letsencrypt/`

**Purpose:** Automated SSL certificate lifecycle management with web server integration.

**Key Features:**
- Automated certificate issuance
- Multi-domain support
- Wildcard certificates
- Web server integration
- OCSP stapling
- Security headers enforcement

**Quick Commands:**
```bash
# Install with auto-renewal
sudo security/letsencrypt/install.sh --auto-renewal

# Issue certificate
sudo ssl-manage --create example.com

# Check certificate status
sudo ssl-manage --list-certificates
```

### 🔍 Security Auditing (Lynis)
**Location:** `security/lynis/`

**Purpose:** Comprehensive security assessment and compliance checking with continuous monitoring.

**Key Features:**
- System security auditing
- Compliance framework validation
- Hardening recommendations
- Vulnerability assessment
- Automated reporting
- Trend analysis

**Quick Commands:**
```bash
# Install with compliance checking
sudo security/lynis/install.sh --enable-compliance

# Run comprehensive audit
sudo lynis-manage audit

# Check compliance status
sudo lynis-manage compliance pci-dss
```

### 🛡️ Rootkit Detection (rkhunter)
**Location:** `security/rkhunter/`

**Purpose:** Advanced rootkit detection and file integrity monitoring for comprehensive malware protection.

**Key Features:**
- Comprehensive rootkit detection
- File integrity monitoring (SHA256 hashing)
- Backdoor and exploit detection
- Automated daily security scans
- Email notification support
- System baseline verification

**Quick Commands:**
```bash
# Install with email notifications
sudo security/rkhunter/install.sh --mail-on-warning admin@company.com

# Run manual security scan
sudo rkhunter --check --nocolors --skip-keypress

# Update detection database
sudo rkhunter --update
```

### 🌐 Web Vulnerability Scanning (Nikto)
**Location:** `security/nikto/`

**Purpose:** Comprehensive web application vulnerability scanner for identifying security issues in web servers and applications.

**Key Features:**
- 6700+ potentially dangerous files/programs detection
- Outdated software version identification
- SSL/TLS security configuration testing
- Stealth and aggressive scanning modes
- Automated scheduling and reporting
- Plugin-based extensible architecture

**Quick Commands:**
```bash
# Install with automated scanning
sudo security/nikto/install.sh --enable-cron --scan-targets "https://example.com"

# Run manual vulnerability scan
nikto -h https://example.com

# Stealth scanning mode
nikto -h https://example.com -evasion 1
```

### 🔧 System Hardening (Ubuntu 24.04+)
**Location:** `security/ubuntu/`

**Purpose:** Comprehensive Ubuntu system hardening implementing CIS benchmarks, NIST guidelines, and security best practices.

**Key Features:**
- Kernel security parameter hardening (ASLR, KASLR)
- Network stack protection and configuration
- User account policies and password enforcement
- Process isolation and resource limits
- Comprehensive audit logging configuration
- AppArmor mandatory access control
- Bootloader security and filesystem hardening
- Compliance framework alignment (CIS, NIST, PCI DSS)

**Quick Commands:**
```bash
# Complete system hardening
sudo security/ubuntu/harden.sh

# High-security configuration
sudo security/ubuntu/harden.sh --enable-two-factor --disable-usb-storage

# Preview hardening changes
sudo security/ubuntu/harden.sh --dry-run --verbose
```

## 🏢 Enterprise Features

### Compliance & Governance

#### Supported Compliance Frameworks
- **PCI-DSS**: Payment Card Industry Data Security Standard
- **HIPAA**: Health Insurance Portability and Accountability Act
- **SOX**: Sarbanes-Oxley Act
- **ISO 27001**: Information Security Management Systems
- **NIST**: National Institute of Standards and Technology
- **CIS**: Center for Internet Security Benchmarks
- **GDPR**: General Data Protection Regulation

#### Compliance Reporting
```bash
# Generate compliance reports for all frameworks
for framework in pci-dss hipaa sox iso27001 nist cis gdpr; do
    lynis-manage compliance $framework --format json > "compliance-${framework}-$(date +%Y%m%d).json"
done

# Executive compliance dashboard
lynis-manage report --compliance --executive
```

### Centralized Management

#### Unified Security Dashboard
```bash
# Create unified security status script
cat > /usr/local/bin/security-dashboard << 'EOF'
#!/bin/bash

echo "bashmin Security Suite Dashboard"
echo "================================"
echo "Server: $(hostname)"
echo "Generated: $(date)"
echo ""

# Network Security Status
echo "🔥 Network Security (UFW):"
if systemctl is-active --quiet ufw; then
    echo "   Status: ✓ Active"
    echo "   Rules: $(ufw status numbered 2>/dev/null | grep -c '\[')"
    echo "   Default: $(ufw status verbose 2>/dev/null | grep 'Default:' | head -1)"
else
    echo "   Status: ⚠ Inactive"
fi
echo ""

# Malware Detection Status
echo "🦠 Malware Detection (ClamAV):"
if systemctl is-active --quiet clamav-daemon; then
    echo "   Status: ✓ Active"
    echo "   Last Update: $(stat -c %y /var/lib/clamav/daily.cvd 2>/dev/null | cut -d' ' -f1 || echo 'Unknown')"
    echo "   Quarantined: $(ls -1 /opt/clamav/quarantine/ 2>/dev/null | wc -l) files"
else
    echo "   Status: ⚠ Inactive"
fi
echo ""

# Intrusion Prevention Status
echo "🚫 Intrusion Prevention (fail2ban):"
if systemctl is-active --quiet fail2ban; then
    echo "   Status: ✓ Active"
    echo "   Active Jails: $(fail2ban-client status 2>/dev/null | grep 'Jail list:' | cut -d':' -f2 | tr -d '\t' | wc -w)"
    echo "   Banned IPs: $(fail2ban-client status 2>/dev/null | grep -o 'Currently banned:[[:space:]]*[0-9]*' | grep -o '[0-9]*' | head -1 || echo '0')"
else
    echo "   Status: ⚠ Inactive"
fi
echo ""

# SSL Management Status
echo "🔐 SSL/TLS Management:"
if [[ -d /etc/letsencrypt/live/ ]] && [[ -n "$(ls -A /etc/letsencrypt/live/ 2>/dev/null)" ]]; then
    echo "   Status: ✓ Configured"
    echo "   Certificates: $(ls -1 /etc/letsencrypt/live/ 2>/dev/null | wc -l)"
    echo "   Auto-renewal: $(systemctl is-enabled certbot.timer 2>/dev/null || echo 'Unknown')"
else
    echo "   Status: ⚠ No certificates"
fi
echo ""

# Security Auditing Status
echo "🔍 Security Auditing (Lynis):"
if command -v lynis-manage >/dev/null 2>&1; then
    echo "   Status: ✓ Installed"
    latest_report=$(find /var/log/bashmin/security/lynis/reports/ -name "*.dat" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    if [[ -f "$latest_report" ]]; then
        hardening_index=$(grep "hardening_index" "$latest_report" 2>/dev/null | cut -d'=' -f2 || echo "Unknown")
        warnings=$(grep -c "warning\[\]" "$latest_report" 2>/dev/null || echo "0")
        echo "   Hardening Index: ${hardening_index}%"
        echo "   Warnings: $warnings"
        echo "   Last Audit: $(stat -c %y "$latest_report" 2>/dev/null | cut -d' ' -f1 || echo 'Unknown')"
    else
        echo "   Status: ⚠ No audit reports found"
    fi
else
    echo "   Status: ⚠ Not installed"
fi
echo ""

# Rootkit Detection Status
echo "🛡️ Rootkit Detection (rkhunter):"
if command -v rkhunter >/dev/null 2>&1; then
    echo "   Status: ✓ Installed"
    if [[ -f /var/log/rkhunter.log ]]; then
        last_scan=$(tail -1 /var/log/rkhunter.log 2>/dev/null | grep -o '^[0-9][0-9]*-[0-9][0-9]*-[0-9]*' || echo 'Unknown')
        warnings=$(grep -c "Warning:" /var/log/rkhunter.log 2>/dev/null || echo "0")
        echo "   Last Scan: $last_scan"
        echo "   Warnings: $warnings"
    else
        echo "   Status: ⚠ No scan logs found"
    fi
else
    echo "   Status: ⚠ Not installed"
fi
echo ""

# Web Vulnerability Scanning Status
echo "🌐 Web Vulnerability Scanning (Nikto):"
if command -v nikto >/dev/null 2>&1; then
    echo "   Status: ✓ Installed"
    if [[ -f /var/log/bashmin/security/nikto/nikto.log ]]; then
        last_scan=$(tail -1 /var/log/bashmin/security/nikto/nikto.log 2>/dev/null | grep -o '^[0-9][0-9]*-[0-9][0-9]*-[0-9]*' || echo 'Unknown')
        report_count=$(ls -1 /var/log/bashmin/security/nikto/reports/ 2>/dev/null | wc -l || echo "0")
        echo "   Last Scan: $last_scan"
        echo "   Reports Generated: $report_count"
    else
        echo "   Status: ⚠ No scan logs found"
    fi
else
    echo "   Status: ⚠ Not installed"
fi
echo ""

# System Hardening Status
echo "🔧 System Hardening:"
hardening_applied=false
if [[ -f /etc/sysctl.d/99-bashmin-kernel-hardening.conf ]]; then
    echo "   Kernel Hardening: ✓ Applied"
    hardening_applied=true
fi
if [[ -f /etc/sysctl.d/99-bashmin-network-hardening.conf ]]; then
    echo "   Network Hardening: ✓ Applied"
    hardening_applied=true
fi
if [[ -f /etc/security/limits.d/99-bashmin-security.conf ]]; then
    echo "   Security Limits: ✓ Applied"
    hardening_applied=true
fi
if [[ -f /etc/audit/rules.d/99-bashmin.rules ]]; then
    echo "   Audit Rules: ✓ Applied"
    hardening_applied=true
fi
if [[ "$hardening_applied" == false ]]; then
    echo "   Status: ⚠ Not applied"
fi
echo ""

echo "For detailed status, run individual component commands:"
echo "• ufw status verbose"
echo "• fail2ban-client status"
echo "• systemctl status clamav-daemon"
echo "• ssl-manage --list-certificates"
echo "• lynis-manage report"
echo "• rkhunter --check --report-warnings-only"
echo "• nikto -Version"
echo "• sysctl -a | grep -E 'randomize|kptr_restrict' # Check hardening"
EOF

chmod +x /usr/local/bin/security-dashboard
```

### Automation & Orchestration

#### Automated Security Workflows
```bash
# Create comprehensive security automation
cat > /usr/local/bin/security-automation << 'EOF'
#!/bin/bash

# Daily security automation workflow
case "${1:-daily}" in
    "hourly")
        # Hourly security checks
        fail2ban-client reload >/dev/null 2>&1
        freshclam --quiet >/dev/null 2>&1
        ;;
        
    "daily")
        # Daily security operations
        clamscan -r /home --infected --quiet --log=/var/log/bashmin/security/clamav/daily-scan.log
        fail2ban-client status | mail -s "Daily fail2ban Status - $(hostname)" security@company.com
        certbot renew --quiet
        ;;
        
    "weekly")
        # Weekly comprehensive security assessment
        lynis-manage audit
        lynis-manage report --weekly
        security-dashboard | mail -s "Weekly Security Report - $(hostname)" security@company.com
        ;;
        
    "monthly")
        # Monthly compliance and deep security review
        for framework in pci-dss hipaa iso27001; do
            lynis-manage compliance $framework
        done
        lynis-manage report --executive --monthly
        ;;
esac
EOF

chmod +x /usr/local/bin/security-automation

# Schedule security automation
cat > /etc/cron.d/bashmin-security << 'EOF'
# bashmin Security Suite Automation
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Hourly security checks
0 * * * * root /usr/local/bin/security-automation hourly

# Daily security operations
0 2 * * * root /usr/local/bin/security-automation daily

# Weekly security assessment
0 3 * * 0 root /usr/local/bin/security-automation weekly

# Monthly compliance review
0 4 1 * * root /usr/local/bin/security-automation monthly
EOF
```

## 📊 Monitoring & Alerting

### Real-Time Monitoring

#### Security Event Monitoring
```bash
# Create security event monitor
cat > /usr/local/bin/security-monitor << 'EOF'
#!/bin/bash

# Monitor security events in real-time
echo "Security Event Monitor - Press Ctrl+C to stop"
echo "=============================================="

# Monitor UFW firewall blocks
echo "🔥 Monitoring UFW firewall blocks..."
tail -f /var/log/ufw.log | grep --line-buffered BLOCK | while read line; do
    echo "[$(date '+%H:%M:%S')] UFW BLOCK: $line"
done &

# Monitor fail2ban actions
echo "🚫 Monitoring fail2ban actions..."
tail -f /var/log/fail2ban.log | grep --line-buffered "Ban\|Unban" | while read line; do
    echo "[$(date '+%H:%M:%S')] FAIL2BAN: $line"
done &

# Monitor ClamAV detections
echo "🦠 Monitoring ClamAV detections..."
tail -f /var/log/clamav/clamav.log | grep --line-buffered "FOUND\|MOVED" | while read line; do
    echo "[$(date '+%H:%M:%S')] CLAMAV: $line"
done &

# Monitor SSL certificate events
echo "🔐 Monitoring SSL events..."
tail -f /var/log/letsencrypt/letsencrypt.log | grep --line-buffered "Cert\|Error" | while read line; do
    echo "[$(date '+%H:%M:%S')] SSL: $line"
done &

wait
EOF

chmod +x /usr/local/bin/security-monitor
```

#### Health Monitoring
```bash
# Create comprehensive health check
cat > /usr/local/bin/security-health-check << 'EOF'
#!/bin/bash

EXIT_CODE=0

echo "bashmin Security Suite Health Check"
echo "==================================="

# Check UFW firewall
if systemctl is-active --quiet ufw; then
    echo "✓ UFW Firewall: Active"
else
    echo "✗ UFW Firewall: Inactive"
    EXIT_CODE=1
fi

# Check ClamAV
if systemctl is-active --quiet clamav-daemon; then
    echo "✓ ClamAV: Active"
    # Check signature age
    sig_age=$(( $(date +%s) - $(stat -c %Y /var/lib/clamav/daily.cvd 2>/dev/null || echo 0) ))
    if [[ $sig_age -lt 86400 ]]; then
        echo "✓ ClamAV Signatures: Up to date"
    else
        echo "⚠ ClamAV Signatures: Outdated ($(( sig_age / 86400 )) days)"
        EXIT_CODE=1
    fi
else
    echo "✗ ClamAV: Inactive"
    EXIT_CODE=1
fi

# Check fail2ban
if systemctl is-active --quiet fail2ban; then
    echo "✓ fail2ban: Active"
    jail_count=$(fail2ban-client status 2>/dev/null | grep 'Jail list:' | cut -d':' -f2 | tr -d '\t' | wc -w)
    if [[ $jail_count -gt 0 ]]; then
        echo "✓ fail2ban Jails: $jail_count active"
    else
        echo "⚠ fail2ban Jails: None active"
    fi
else
    echo "✗ fail2ban: Inactive"
    EXIT_CODE=1
fi

# Check SSL certificates
if [[ -d /etc/letsencrypt/live/ ]] && [[ -n "$(ls -A /etc/letsencrypt/live/ 2>/dev/null)" ]]; then
    echo "✓ SSL Certificates: Configured"
    # Check certificate expiration
    for cert_dir in /etc/letsencrypt/live/*/; do
        if [[ -f "$cert_dir/cert.pem" ]]; then
            domain=$(basename "$cert_dir")
            exp_date=$(openssl x509 -in "$cert_dir/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
            if [[ -n "$exp_date" ]]; then
                exp_timestamp=$(date -d "$exp_date" +%s 2>/dev/null)
                current_timestamp=$(date +%s)
                days_left=$(( (exp_timestamp - current_timestamp) / 86400 ))
                
                if [[ $days_left -gt 30 ]]; then
                    echo "✓ SSL Certificate ($domain): Valid for $days_left days"
                elif [[ $days_left -gt 7 ]]; then
                    echo "⚠ SSL Certificate ($domain): Expires in $days_left days"
                else
                    echo "✗ SSL Certificate ($domain): Expires in $days_left days"
                    EXIT_CODE=1
                fi
            fi
        fi
    done
else
    echo "⚠ SSL Certificates: None configured"
fi

# Check Lynis
if command -v lynis-manage >/dev/null 2>&1; then
    echo "✓ Lynis: Installed"
    latest_report=$(find /var/log/bashmin/security/lynis/reports/ -name "*.dat" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    if [[ -f "$latest_report" ]]; then
        report_age=$(( $(date +%s) - $(stat -c %Y "$latest_report") ))
        if [[ $report_age -lt 604800 ]]; then  # 7 days
            hardening_index=$(grep "hardening_index" "$latest_report" 2>/dev/null | cut -d'=' -f2 || echo "0")
            if [[ $hardening_index -ge 80 ]]; then
                echo "✓ Lynis Hardening Index: ${hardening_index}% (Excellent)"
            elif [[ $hardening_index -ge 70 ]]; then
                echo "⚠ Lynis Hardening Index: ${hardening_index}% (Good)"
            else
                echo "✗ Lynis Hardening Index: ${hardening_index}% (Needs Improvement)"
                EXIT_CODE=1
            fi
        else
            echo "⚠ Lynis: Last audit is $((report_age / 86400)) days old"
        fi
    else
        echo "⚠ Lynis: No audit reports found"
    fi
else
    echo "⚠ Lynis: Not installed"
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Overall Status: ✓ All security components healthy"
else
    echo "Overall Status: ⚠ Issues detected - review above"
fi

exit $EXIT_CODE
EOF

chmod +x /usr/local/bin/security-health-check
```

### Alert Configuration

#### Critical Security Alerts
```bash
# Create critical security alert system
cat > /usr/local/bin/security-critical-alert << 'EOF'
#!/bin/bash

ALERT_EMAIL="${SECURITY_ALERT_EMAIL:-security@company.com}"
SLACK_WEBHOOK="${SECURITY_SLACK_WEBHOOK:-}"

send_alert() {
    local severity="$1"
    local component="$2"
    local message="$3"
    local details="$4"
    
    # Format alert message
    alert_message="SECURITY ALERT: $severity
Server: $(hostname)
Component: $component
Time: $(date)

$message

Details:
$details

Please investigate immediately."

    # Send email alert
    if [[ -n "$ALERT_EMAIL" ]]; then
        echo "$alert_message" | mail -s "SECURITY ALERT: $severity - $(hostname)" "$ALERT_EMAIL"
    fi
    
    # Send Slack alert
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$alert_message\"}" \
            "$SLACK_WEBHOOK" >/dev/null 2>&1
    fi
    
    # Log alert
    echo "$(date): $severity - $component - $message" >> /var/log/bashmin/security/critical-alerts.log
}

# Check for critical security events
check_ufw_attacks() {
    # Check for excessive blocked connections (more than 100 in last hour)
    block_count=$(grep "$(date '+%b %d %H')" /var/log/ufw.log 2>/dev/null | grep -c BLOCK || echo 0)
    if [[ $block_count -gt 100 ]]; then
        send_alert "HIGH" "UFW Firewall" "Excessive blocked connections detected" "Blocked connections in last hour: $block_count"
    fi
}

check_fail2ban_events() {
    # Check for new persistent offenders
    persistent_count=$(fail2ban-client status recidive 2>/dev/null | grep "Currently banned" | grep -o '[0-9]*' || echo 0)
    if [[ $persistent_count -gt 10 ]]; then
        send_alert "HIGH" "fail2ban" "High number of persistent offenders" "Persistent offenders banned: $persistent_count"
    fi
}

check_clamav_detections() {
    # Check for malware detections in last hour
    malware_count=$(grep "$(date '+%a %b %d %H')" /var/log/clamav/clamav.log 2>/dev/null | grep -c FOUND || echo 0)
    if [[ $malware_count -gt 0 ]]; then
        send_alert "CRITICAL" "ClamAV" "Malware detected" "Malware files found in last hour: $malware_count"
    fi
}

check_ssl_issues() {
    # Check for SSL certificate expiration warnings
    for cert_dir in /etc/letsencrypt/live/*/; do
        if [[ -f "$cert_dir/cert.pem" ]]; then
            domain=$(basename "$cert_dir")
            exp_date=$(openssl x509 -in "$cert_dir/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
            if [[ -n "$exp_date" ]]; then
                exp_timestamp=$(date -d "$exp_date" +%s 2>/dev/null)
                current_timestamp=$(date +%s)
                days_left=$(( (exp_timestamp - current_timestamp) / 86400 ))
                
                if [[ $days_left -le 7 ]] && [[ $days_left -gt 0 ]]; then
                    send_alert "HIGH" "SSL Certificate" "Certificate expiring soon" "Domain: $domain expires in $days_left days"
                elif [[ $days_left -le 0 ]]; then
                    send_alert "CRITICAL" "SSL Certificate" "Certificate expired" "Domain: $domain expired $((-days_left)) days ago"
                fi
            fi
        fi
    done
}

check_lynis_degradation() {
    # Check for significant hardening index degradation
    latest_report=$(find /var/log/bashmin/security/lynis/reports/ -name "*.dat" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    if [[ -f "$latest_report" ]]; then
        current_index=$(grep "hardening_index" "$latest_report" 2>/dev/null | cut -d'=' -f2 || echo "0")
        
        # Check previous report for comparison
        previous_report=$(find /var/log/bashmin/security/lynis/reports/ -name "*.dat" -printf '%T@ %p\n' 2>/dev/null | sort -nr | sed -n '2p' | cut -d' ' -f2-)
        if [[ -f "$previous_report" ]]; then
            previous_index=$(grep "hardening_index" "$previous_report" 2>/dev/null | cut -d'=' -f2 || echo "0")
            
            # Alert if hardening index dropped by more than 10 points
            if [[ $((current_index + 10)) -lt $previous_index ]]; then
                send_alert "HIGH" "Lynis" "Hardening index degraded significantly" "Dropped from ${previous_index}% to ${current_index}%"
            fi
        fi
        
        # Alert if hardening index is critically low
        if [[ $current_index -lt 60 ]]; then
            send_alert "HIGH" "Lynis" "Low hardening index" "Current hardening index: ${current_index}%"
        fi
        
        # Check for critical warnings
        critical_warnings=$(grep -c "warning\[\].*critical" "$latest_report" 2>/dev/null || echo "0")
        if [[ $critical_warnings -gt 0 ]]; then
            send_alert "CRITICAL" "Lynis" "Critical security warnings found" "Critical warnings: $critical_warnings"
        fi
    fi
}

check_rkhunter_warnings() {
    # Check for rkhunter security warnings
    if [[ -f /var/log/rkhunter.log ]]; then
        warning_count=$(grep -c "Warning:" /var/log/rkhunter.log 2>/dev/null || echo "0")
        if [[ $warning_count -gt 0 ]]; then
            recent_warnings=$(grep "$(date '+%Y-%m-%d')" /var/log/rkhunter.log 2>/dev/null | grep -c "Warning:" || echo "0")
            if [[ $recent_warnings -gt 0 ]]; then
                send_alert "HIGH" "rkhunter" "Rootkit detection warnings" "New warnings today: $recent_warnings, Total: $warning_count"
            fi
        fi
    fi
}

check_nikto_vulnerabilities() {
    # Check for new web vulnerabilities detected by Nikto
    if [[ -f /var/log/bashmin/security/nikto/nikto.log ]]; then
        # Check for recent vulnerability detections
        today_scans=$(grep "$(date '+%Y-%m-%d')" /var/log/bashmin/security/nikto/nikto.log 2>/dev/null | wc -l || echo "0")
        if [[ $today_scans -gt 0 ]]; then
            # Check latest scan reports for vulnerabilities
            latest_report=$(find /var/log/bashmin/security/nikto/reports/ -name "*.html" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
            if [[ -f "$latest_report" ]]; then
                vuln_count=$(grep -c "OSVDB" "$latest_report" 2>/dev/null || echo "0")
                if [[ $vuln_count -gt 5 ]]; then
                    send_alert "HIGH" "Nikto" "High number of web vulnerabilities detected" "Vulnerabilities found: $vuln_count in latest scan"
                fi
            fi
        fi
    fi
}

check_system_hardening() {
    # Check if critical hardening measures are still in place
    if [[ -f /etc/sysctl.d/99-bashmin-kernel-hardening.conf ]]; then
        # Check if ASLR is still enabled
        aslr_status=$(sysctl kernel.randomize_va_space 2>/dev/null | cut -d' ' -f3 || echo "0")
        if [[ "$aslr_status" != "2" ]]; then
            send_alert "CRITICAL" "System Hardening" "ASLR disabled or compromised" "Current ASLR status: $aslr_status (should be 2)"
        fi
        
        # Check if kernel pointer restrictions are in place
        kptr_status=$(sysctl kernel.kptr_restrict 2>/dev/null | cut -d' ' -f3 || echo "0")
        if [[ "$kptr_status" != "2" ]]; then
            send_alert "HIGH" "System Hardening" "Kernel pointer restrictions compromised" "Current kptr_restrict: $kptr_status (should be 2)"
        fi
    fi
}

# Run all security checks
check_ufw_attacks
check_fail2ban_events
check_clamav_detections
check_ssl_issues
check_lynis_degradation
check_rkhunter_warnings
check_nikto_vulnerabilities
check_system_hardening
EOF

chmod +x /usr/local/bin/security-critical-alert

# Schedule critical alert checks
echo "*/15 * * * * root /usr/local/bin/security-critical-alert" >> /etc/cron.d/bashmin-security-alerts
```

## 🔧 Configuration Management

### Centralized Configuration

#### Security Configuration Template
```bash
# Create centralized security configuration
cat > /etc/bashmin/security.conf << 'EOF'
# bashmin Security Suite Configuration
# ===================================

# Global Settings
SECURITY_EMAIL="security@company.com"
SLACK_WEBHOOK="https://hooks.slack.com/services/..."
LOG_LEVEL="INFO"
NOTIFICATION_LEVEL="HIGH"

# UFW Firewall Settings
UFW_RATE_LIMITING="yes"
UFW_LOGGING_LEVEL="high"
UFW_DEFAULT_POLICY="deny"

# ClamAV Settings
CLAMAV_REAL_TIME="yes"
CLAMAV_EMAIL_SCAN="yes"
CLAMAV_QUARANTINE_NOTIFICATIONS="yes"

# fail2ban Settings
FAIL2BAN_GEO_BLOCKING="yes"
FAIL2BAN_PERSISTENT_BANS="yes"
FAIL2BAN_NOTIFICATION_METHOD="email,slack"

# SSL Settings
SSL_AUTO_RENEWAL="yes"
SSL_SECURITY_HEADERS="yes"
SSL_OCSP_STAPLING="yes"

# Lynis Settings
LYNIS_COMPLIANCE_MODE="yes"
LYNIS_AUDIT_FREQUENCY="weekly"
LYNIS_HARDENING_THRESHOLD="80"
LYNIS_PENTEST_MODE="no"
EOF

# Create configuration validation script
cat > /usr/local/bin/security-config-validate << 'EOF'
#!/bin/bash

source /etc/bashmin/security.conf 2>/dev/null || {
    echo "Error: Security configuration file not found"
    exit 1
}

echo "Validating bashmin Security Configuration"
echo "========================================"

# Validate email address
if [[ "$SECURITY_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "✓ Security email: $SECURITY_EMAIL"
else
    echo "✗ Invalid security email: $SECURITY_EMAIL"
fi

# Validate Slack webhook
if [[ "$SLACK_WEBHOOK" =~ ^https://hooks\.slack\.com/services/ ]]; then
    echo "✓ Slack webhook: Configured"
else
    echo "⚠ Slack webhook: Not configured or invalid"
fi

# Validate component configurations
echo ""
echo "Component Configurations:"
echo "• UFW Rate Limiting: $UFW_RATE_LIMITING"
echo "• ClamAV Real-time Scan: $CLAMAV_REAL_TIME"
echo "• fail2ban Geo-blocking: $FAIL2BAN_GEO_BLOCKING"
echo "• SSL Auto-renewal: $SSL_AUTO_RENEWAL"
echo "• Lynis Compliance Mode: $LYNIS_COMPLIANCE_MODE"

echo ""
echo "Configuration validation completed"
EOF

chmod +x /usr/local/bin/security-config-validate
```

### Backup & Recovery

#### Security Configuration Backup
```bash
# Create security backup script
cat > /usr/local/bin/security-backup << 'EOF'
#!/bin/bash

BACKUP_DIR="/opt/bashmin/backups/security"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="security-config-backup-$TIMESTAMP.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "Creating security configuration backup..."

# Create temporary directory for backup staging
TEMP_DIR=$(mktemp -d)

# Copy security configurations
mkdir -p "$TEMP_DIR/etc"
cp -r /etc/ufw/ "$TEMP_DIR/etc/" 2>/dev/null
cp -r /etc/fail2ban/ "$TEMP_DIR/etc/" 2>/dev/null
cp -r /etc/clamav/ "$TEMP_DIR/etc/" 2>/dev/null
cp -r /etc/letsencrypt/ "$TEMP_DIR/etc/" 2>/dev/null
cp -r /etc/lynis/ "$TEMP_DIR/etc/" 2>/dev/null
cp /etc/bashmin/security.conf "$TEMP_DIR/etc/" 2>/dev/null

# Copy logs (last 7 days)
mkdir -p "$TEMP_DIR/logs"
find /var/log/bashmin/security/ -type f -mtime -7 -exec cp {} "$TEMP_DIR/logs/" \; 2>/dev/null

# Copy cron configurations
mkdir -p "$TEMP_DIR/cron"
cp /etc/cron.d/bashmin-security* "$TEMP_DIR/cron/" 2>/dev/null

# Copy custom scripts
mkdir -p "$TEMP_DIR/scripts"
cp /usr/local/bin/security-* "$TEMP_DIR/scripts/" 2>/dev/null
cp /usr/local/bin/ssl-manage "$TEMP_DIR/scripts/" 2>/dev/null
cp /usr/local/bin/lynis-manage "$TEMP_DIR/scripts/" 2>/dev/null

# Create backup metadata
cat > "$TEMP_DIR/backup-info.txt" << EOF
bashmin Security Suite Backup
Created: $(date)
Server: $(hostname)
Backup Type: Configuration and Logs
Components:
- UFW Firewall
- ClamAV Antivirus
- fail2ban Intrusion Prevention
- Let's Encrypt SSL
- Lynis Security Auditing
EOF

# Create compressed backup
cd "$TEMP_DIR"
tar -czf "$BACKUP_DIR/$BACKUP_FILE" . 2>/dev/null

# Cleanup
rm -rf "$TEMP_DIR"

# Maintain backup retention (keep last 30 backups)
find "$BACKUP_DIR" -name "security-config-backup-*.tar.gz" -type f | sort | head -n -30 | xargs rm -f

echo "Security backup created: $BACKUP_DIR/$BACKUP_FILE"
echo "Backup size: $(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)"

# Optional: Upload to remote backup location
if [[ -n "${BACKUP_REMOTE_HOST:-}" ]]; then
    scp "$BACKUP_DIR/$BACKUP_FILE" "$BACKUP_REMOTE_HOST:/backups/security/" 2>/dev/null && \
        echo "Backup uploaded to remote location"
fi
EOF

chmod +x /usr/local/bin/security-backup

# Schedule daily backups
echo "0 1 * * * root /usr/local/bin/security-backup" >> /etc/cron.d/bashmin-security-backup
```

## 📚 Documentation & Support

### Component Documentation
- **[UFW Firewall](security/ufw/README.md)** - Network security and firewall management
- **[ClamAV Antivirus](security/clamav/README.md)** - Malware detection and quarantine
- **[fail2ban](security/fail2ban/README.md)** - Intrusion prevention and geographic blocking
- **[Let's Encrypt SSL](security/letsencrypt/README.md)** - SSL certificate lifecycle management
- **[Lynis Security Auditing](security/lynis/README.md)** - Security assessment and compliance

### Quick Reference Commands

#### Daily Operations
```bash
# Security status overview
security-dashboard

# Run health check
security-health-check

# View recent security events
security-monitor

# Generate unified report
bashmin-security-report
```

#### Emergency Response
```bash
# Block suspicious IP immediately
sudo ufw deny from <IP_ADDRESS>
sudo fail2ban-client set <JAIL> banip <IP_ADDRESS>

# Quarantine suspicious file
sudo clamscan --move=/opt/clamav/quarantine/ <FILE_PATH>

# Emergency SSL certificate renewal
sudo ssl-manage --renew <DOMAIN> --force

# Run emergency security audit
sudo lynis-manage audit --quick
```

#### Maintenance Tasks
```bash
# Update all security components
security-automation daily

# Create configuration backup
security-backup

# Validate configuration
security-config-validate

# Clean old logs and reports
find /var/log/bashmin/security/ -type f -mtime +30 -delete
```

## 🔄 Updates & Maintenance

### Automated Updates
```bash
# Schedule weekly security updates
cat > /etc/cron.d/bashmin-security-updates << 'EOF'
# Weekly security component updates
0 5 * * 1 root /usr/local/bin/security-update-all
EOF

# Create update script
cat > /usr/local/bin/security-update-all << 'EOF'
#!/bin/bash

echo "Updating bashmin Security Suite..."

# Update ClamAV signatures
freshclam --quiet

# Update fail2ban rules
fail2ban-client reload >/dev/null 2>&1

# Update Lynis database
if [[ -d /opt/lynis/.git ]]; then
    cd /opt/lynis && git pull origin main >/dev/null 2>&1
fi

# Update UFW application profiles
ufw app update all >/dev/null 2>&1

# Update SSL certificates
certbot renew --quiet

echo "Security suite updates completed"
EOF

chmod +x /usr/local/bin/security-update-all
```

### Version Management
```bash
# Create version tracking
cat > /usr/local/bin/security-version << 'EOF'
#!/bin/bash

echo "bashmin Security Suite Version Information"
echo "========================================"

# UFW version
if command -v ufw >/dev/null 2>&1; then
    echo "UFW: $(ufw version 2>/dev/null | head -1)"
fi

# ClamAV version
if command -v clamscan >/dev/null 2>&1; then
    echo "ClamAV: $(clamscan --version 2>/dev/null | head -1)"
fi

# fail2ban version
if command -v fail2ban-client >/dev/null 2>&1; then
    echo "fail2ban: $(fail2ban-client version 2>/dev/null)"
fi

# Certbot version
if command -v certbot >/dev/null 2>&1; then
    echo "Certbot: $(certbot --version 2>/dev/null | head -1)"
fi

# Lynis version
if command -v lynis >/dev/null 2>&1; then
    echo "Lynis: $(lynis show version 2>/dev/null | grep 'Lynis version' | cut -d':' -f2 | tr -d ' ')"
fi

# bashmin Security Suite
echo "bashmin Security Suite: 1.0.0"
echo "Last Updated: $(date)"
EOF

chmod +x /usr/local/bin/security-version
```

---

## 🎯 Next Steps

1. **Install Core Components**: Start with UFW firewall and fail2ban intrusion prevention
2. **Add Malware Protection**: Install ClamAV for comprehensive malware detection
3. **Implement SSL Management**: Deploy Let's Encrypt for automated certificate management
4. **Enable Security Auditing**: Install Lynis for continuous security assessment
5. **Configure Monitoring**: Set up unified monitoring and alerting
6. **Implement Compliance**: Enable compliance checking for your industry requirements

For detailed installation and configuration instructions, refer to the individual component README files in each security subdirectory.

**Enterprise Support**: For enterprise deployment assistance, custom security configurations, or compliance consulting, contact the bashmin security team.
