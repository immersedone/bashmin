# Nikto - Web Vulnerability Scanner

A comprehensive web application vulnerability scanner for identifying security issues in web servers and applications.

## Overview

Nikto is an open-source web server scanner that performs comprehensive tests against web servers for multiple items, including:

- Over 6700 potentially dangerous files/programs
- Checks for outdated versions of over 1250 servers
- Version-specific problems on over 270 servers
- Scan items and plugins are frequently updated
- SSL certificate validation and security testing
- Subdomain and directory enumeration

## Installation

### Quick Start

```bash
# Basic installation
./install.sh

# Installation with automated scanning
./install.sh --enable-cron --scan-targets "https://example.com,https://test.com"

# Stealth scanning setup
./install.sh --stealth-mode --proxy-server "http://proxy:8080"
```

### Installation Options

| Option | Description | Default |
|--------|-------------|---------|
| `--install-method METHOD` | Installation method: package, git | package |
| `--auto-update-db` | Enable automatic database updates | Enabled |
| `--disable-auto-update-db` | Disable automatic database updates | - |
| `--scan-targets TARGETS` | Default scan targets (comma-separated URLs) | None |
| `--aggressive-scan` | Enable aggressive scanning mode | Disabled |
| `--stealth-mode` | Enable stealth scanning (slower, less detectable) | Disabled |
| `--no-follow-redirects` | Disable following HTTP redirects | Follow redirects |
| `--max-scan-time SECONDS` | Maximum scan time per target | 3600 |
| `--thread-count COUNT` | Number of concurrent threads | 5 |
| `--user-agent STRING` | Custom User-Agent string | Nikto/bashmin-security |
| `--custom-plugins LIST` | Comma-separated list of custom plugins | None |
| `--excluded-plugins LIST` | Comma-separated list of plugins to exclude | None |
| `--proxy-server URL` | HTTP proxy server | None |
| `--proxy-auth USER:PASS` | Proxy authentication credentials | None |
| `--no-ssl-verify` | Disable SSL certificate verification | Verify SSL |
| `--enable-cron` | Enable automated scanning | Disabled |
| `--cron-schedule SCHEDULE` | Cron schedule: daily, weekly, monthly | weekly |
| `--output-format FORMAT` | Report format: html, xml, csv, txt | html |
| `--report-retention DAYS` | Report retention period in days | 90 |
| `--notification-email EMAIL` | Email for scan notifications | None |
| `--slack-webhook URL` | Slack webhook for notifications | None |

## Configuration

### Main Configuration File

The primary configuration is stored in `/etc/nikto/config.txt`. Key settings include:

```bash
# Database updates
UPDATES=yes
DBCHECK=yes
AUTOUPDATE=yes

# Scan configuration
USERAGENT=Nikto/bashmin-security
MAXTIME=3600
THREADS=5

# Output configuration
CLIOPTS=-Format html
FOLLOWREDIRECTS=yes
```

### Automated Scanning

When enabled, automated scanning is configured via:

- **Cron Job**: `/etc/cron.d/nikto-scan` - Scheduled vulnerability scans
- **Scan Script**: `/usr/local/bin/nikto-scan` - Wrapper script with notifications

### Log Management

Logs are automatically rotated via `/etc/logrotate.d/nikto`:
- Daily rotation with configurable retention
- Compressed storage to save disk space
- Automatic cleanup of old reports

## Usage

### Manual Scanning

```bash
# Basic website scan
nikto -h https://example.com

# Scan with specific output format
nikto -h https://example.com -Format html -output /tmp/scan_results.html

# Multiple format output
nikto -h https://example.com -Format html,xml,csv

# Stealth scanning (slower but less detectable)
nikto -h https://example.com -evasion 1

# Aggressive scanning with all mutate options
nikto -h https://example.com -mutate 1,2,3,4,5,6,7,8,9

# Scan multiple hosts from file
nikto -h hosts.txt

# Scan with proxy
nikto -h https://example.com -useproxy http://proxy:8080
```

### Advanced Scanning Options

```bash
# Scan specific ports
nikto -h https://example.com -port 80,443,8080,8443

# SSL-specific testing
nikto -h https://example.com -ssl

# Scan with custom plugins
nikto -h https://example.com -Plugins headers,shellshock,ssl

# Skip certain tests
nikto -h https://example.com -Plugin nikto_test@!002

# Timeout and throttling
nikto -h https://example.com -timeout 10 -Pause 2
```

### Database Management

```bash
# Update vulnerability databases
nikto -update

# List available plugins
nikto -list-plugins

# Show version information
nikto -Version

# Display help
nikto -Help
```

## Scan Types and Modes

### Standard Scan
Default comprehensive scanning with moderate detection risk:
```bash
nikto -h https://example.com
```

### Stealth Scan
Slower scanning designed to avoid detection:
```bash
./install.sh --stealth-mode
# Or manually:
nikto -h https://example.com -evasion 1 -Pause 2
```

### Aggressive Scan
Comprehensive testing with all mutation techniques:
```bash
./install.sh --aggressive-scan
# Or manually:
nikto -h https://example.com -mutate 1,2,3,4,5,6,7,8,9
```

### SSL/TLS Security Testing
Focused on SSL/TLS configuration issues:
```bash
nikto -h https://example.com -ssl -Plugins ssl
```

## Plugin Management

### Available Plugin Categories

| Plugin Category | Description |
|----------------|-------------|
| `headers` | HTTP header security analysis |
| `shellshock` | Shellshock vulnerability testing |
| `ssl` | SSL/TLS configuration testing |
| `cookies` | Cookie security analysis |
| `cgi` | CGI script vulnerability testing |
| `apache` | Apache-specific tests |
| `iis` | IIS-specific tests |
| `nginx` | Nginx-specific tests |
| `robots` | robots.txt analysis |
| `paths` | Directory and file enumeration |

### Custom Plugin Configuration

```bash
# Enable specific plugins only
./install.sh --custom-plugins "headers,ssl,shellshock"

# Exclude problematic plugins
./install.sh --excluded-plugins "cgi,paths"
```

## Automated Scanning

### Schedule Configuration

```bash
# Daily automated scans
./install.sh --enable-cron --cron-schedule daily --scan-targets "https://site1.com,https://site2.com"

# Weekly scans with notifications
./install.sh --enable-cron --cron-schedule weekly \
    --notification-email admin@example.com \
    --scan-targets "https://example.com"
```

### Notification Setup

**Email Notifications:**
```bash
# Requires mailutils or similar
./install.sh --notification-email security@company.com
```

**Slack Notifications:**
```bash
./install.sh --slack-webhook "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

## Report Analysis

### HTML Reports
Generated by default, includes:
- Executive summary with vulnerability counts
- Detailed findings with OSVDB references
- Risk classifications and remediation guidance
- Timeline and scan metadata

### XML Reports
Machine-readable format for integration:
```bash
nikto -h https://example.com -Format xml -output scan.xml
```

### CSV Reports
Spreadsheet-compatible format:
```bash
nikto -h https://example.com -Format csv -output scan.csv
```

## Security Best Practices

### Scanning Ethics and Legal Considerations

⚠️ **Important**: Only scan systems you own or have explicit permission to test.

1. **Authorization**: Ensure proper authorization before scanning
2. **Rate Limiting**: Use stealth mode for production systems
3. **Time Windows**: Schedule scans during maintenance windows
4. **Documentation**: Maintain logs of all scanning activities

### Production Environment Scanning

```bash
# Recommended settings for production
./install.sh --stealth-mode --max-scan-time 1800 --thread-count 2 \
    --cron-schedule weekly --notification-email ops@company.com
```

### Integration with WAF/Security Tools

Nikto integrates well with:
- **ModSecurity**: Web Application Firewall
- **fail2ban**: Intrusion prevention
- **Suricata/Snort**: Network intrusion detection
- **SIEM systems**: Via structured logging

## Troubleshooting

### Common Issues

**Database Update Failures**
```bash
# Manual database update
nikto -update -Debug

# Check network connectivity
curl -I https://www.cirt.net/nikto/
```

**SSL Certificate Errors**
```bash
# Skip SSL verification (use cautiously)
nikto -h https://example.com -nossl

# Or configure in install:
./install.sh --no-ssl-verify
```

**Proxy Configuration Issues**
```bash
# Test proxy connectivity
curl --proxy http://proxy:8080 https://example.com

# Configure during install:
./install.sh --proxy-server "http://proxy:8080" --proxy-auth "user:pass"
```

**False Positive Management**
```bash
# Exclude specific tests
nikto -h https://example.com -Plugin nikto_test@!002,!003

# Or configure during install:
./install.sh --excluded-plugins "002,003"
```

### Performance Tuning

**Large Scale Scanning:**
```bash
# Increase threads and timeout for faster scanning
./install.sh --thread-count 10 --max-scan-time 7200
```

**Resource-Constrained Environments:**
```bash
# Reduce threads and enable stealth mode
./install.sh --thread-count 2 --stealth-mode --max-scan-time 1800
```

### Log Analysis

```bash
# View recent scan results
tail -f /var/log/bashmin/security/nikto/nikto.log

# Check for errors
grep -i error /var/log/bashmin/security/nikto/nikto-error.log

# Analyze scan reports
find /var/log/bashmin/security/nikto/reports -name "*.html" -mtime -7
```

## Files and Directories

| Path | Purpose |
|------|---------|
| `/etc/nikto/config.txt` | Main configuration file |
| `/var/log/bashmin/security/nikto/` | Log directory |
| `/var/log/bashmin/security/nikto/reports/` | Scan reports |
| `/usr/local/bin/nikto-scan` | Automated scan script |
| `/etc/cron.d/nikto-scan` | Cron job configuration |
| `/etc/logrotate.d/nikto` | Log rotation configuration |

## Integration Examples

### CI/CD Pipeline Integration

```bash
# Add to build pipeline for security testing
nikto -h https://staging.example.com -Format xml -output nikto-results.xml
```

### Monitoring Integration

```bash
# Export metrics for monitoring systems
nikto -h https://example.com -Format csv | \
    awk -F, 'NR>1{print "nikto_vulnerability_count{host=\"$1\"} " NF-1}'
```

### SIEM Integration

Configure structured logging in `/etc/nikto/config.txt`:
```bash
CLIOPTS=-Format csv
# Then parse CSV logs into SIEM
```

## Security Considerations

- Nikto can generate significant web server logs and may trigger security alerts
- Use stealth mode when scanning production environments
- Consider impact on server performance during scanning
- Regular database updates are essential for current vulnerability detection
- Coordinate with system administrators before automated scanning
- Review and validate all findings before remediation

For complete security coverage, combine Nikto with other bashmin security tools including nmap, SSL Labs testing, and OWASP ZAP.
