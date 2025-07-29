# rkhunter - Rootkit Detection System

A comprehensive rootkit detection and security monitoring system for Ubuntu-based servers.

## Overview

rkhunter (Rootkit Hunter) is a Unix-based tool that scans for rootkits, backdoors, and local exploits. It performs checks by:

- Comparing SHA256 hashes of important files with known good ones in an online database
- Searching for default files used by rootkits
- Checking for wrong file permissions on binaries
- Looking for suspicious strings in kernel modules
- Performing various system checks

## Installation

### Quick Start

```bash
# Basic installation
./install.sh

# Installation with email notifications
./install.sh --mail-on-warning admin@example.com

# Custom configuration
./install.sh --disable-tests "hidden_procs,deleted_files" --use-syslog
```

### Installation Options

| Option | Description | Default |
|--------|-------------|---------|
| `--mail-on-warning EMAIL` | Email address for security warnings | None |
| `--disable-daily-checks` | Disable automatic daily scans | Enabled |
| `--disable-weekly-updates` | Disable automatic weekly database updates | Enabled |
| `--no-auto-update-db` | Disable automatic database updates | Enabled |
| `--scan-mode MODE` | Set scan mode (`--checkall`, `--check`, `--cronjob`) | `--checkall` |
| `--disable-tests TESTS` | Comma-separated list of tests to disable | None |
| `--enable-tests TESTS` | Comma-separated list of tests to enable | None |
| `--use-syslog` | Enable syslog logging | Disabled |
| `--tmpdir PATH` | Set temporary directory | `/var/lib/rkhunter/tmp` |
| `--dry-run` | Preview changes without applying | False |
| `--verbose` | Enable detailed output | False |

## Configuration

### Main Configuration File

The primary configuration is stored in `/etc/rkhunter.conf`. Key settings include:

```bash
# Database updates
UPDATE_MIRRORS=1
AUTO_X_DETECT=1

# Email notifications (if configured)
MAIL-ON-WARNING="admin@example.com"

# Logging
LOGFILE="/var/log/rkhunter.log"
USE_SYSLOG=0

# Security checks
HASH_FUNC=SHA256
PKGMGR="DPKG"
```

### Automated Scanning

The installation sets up automated security monitoring:

- **Daily Scans**: `/etc/cron.daily/rkhunter` - Performs comprehensive system checks
- **Weekly Updates**: `/etc/cron.weekly/rkhunter` - Updates detection databases

### Log Management

Logs are automatically rotated via `/etc/logrotate.d/rkhunter`:
- Daily rotation with 30-day retention
- Compressed storage to save disk space
- Secure permissions (640 root:adm)

## Usage

### Manual Operations

```bash
# Run full security scan
sudo rkhunter --check

# Run scan without user interaction (for scripts)
sudo rkhunter --check --nocolors --skip-keypress

# Update virus and malware databases
sudo rkhunter --update

# Update file property database (run after system updates)
sudo rkhunter --propupd

# Check configuration validity
sudo rkhunter --config-check

# View version and test information
sudo rkhunter --version
```

### Monitoring and Logs

```bash
# View recent scan results
sudo tail -f /var/log/rkhunter.log

# Check for warnings in recent scans
sudo grep -i warning /var/log/rkhunter.log

# View scan summary
sudo rkhunter --summary
```

## Common Test Configurations

### Recommended Disabled Tests

Some tests may produce false positives in modern environments:

```bash
# Install with commonly disabled tests
./install.sh --disable-tests "apps,hidden_procs,deleted_files,packet_cap_apps"
```

**Common false positive tests:**
- `hidden_procs` - Modern kernels may show process differences
- `deleted_files` - Running processes with updated binaries
- `packet_cap_apps` - Network monitoring tools
- `apps` - Application version mismatches

### High-Security Environments

For maximum security (may require more maintenance):

```bash
# Enable all tests with email notifications
./install.sh --mail-on-warning security@company.com --use-syslog
```

## Security Best Practices

### Regular Maintenance

1. **Review scan results weekly**
   ```bash
   sudo rkhunter --check --report-warnings-only
   ```

2. **Update database after system changes**
   ```bash
   # After installing new software or system updates
   sudo rkhunter --propupd
   ```

3. **Monitor email alerts** (if configured)
   - Investigate all warnings promptly
   - False positives should be whitelisted, not ignored

### Whitelisting

Add legitimate files that trigger warnings:

```bash
# Edit /etc/rkhunter.conf
SCRIPTWHITELIST="/path/to/legitimate/script"
ALLOWHIDDENFILE="/path/to/hidden/config"
RTKT_DIR_WHITELIST="/custom/application/path"
```

### Integration with Other Security Tools

rkhunter works well alongside:
- **fail2ban** - Intrusion prevention
- **ufw** - Firewall management  
- **lynis** - Security auditing
- **clamav** - Antivirus scanning

## Troubleshooting

### Common Issues

**Database Update Failures**
```bash
# Clear cache and retry
sudo rm -rf /var/lib/rkhunter/tmp/*
sudo rkhunter --update
```

**Permission Errors**
```bash
# Reset permissions
sudo chown -R root:root /var/lib/rkhunter
sudo chmod 700 /var/lib/rkhunter/tmp
```

**False Positive Warnings**
1. Investigate the warning thoroughly
2. If legitimate, add to whitelist in `/etc/rkhunter.conf`
3. Update file properties: `sudo rkhunter --propupd`

### Log Analysis

Check scan results:
```bash
# View warnings only
sudo rkhunter --check --report-warnings-only --nocolors

# Detailed log analysis
sudo grep -E "(FAILED|Warning)" /var/log/rkhunter.log
```

## Files and Directories

| Path | Purpose |
|------|---------|
| `/etc/rkhunter.conf` | Main configuration file |
| `/var/log/rkhunter.log` | Scan results and logs |
| `/var/lib/rkhunter/` | Database and temporary files |
| `/etc/cron.daily/rkhunter` | Daily scan automation |
| `/etc/cron.weekly/rkhunter` | Weekly update automation |
| `/etc/logrotate.d/rkhunter` | Log rotation configuration |

## Security Considerations

- rkhunter requires root privileges for comprehensive scanning
- Database updates require internet connectivity
- Email notifications need a configured mail system
- Regular maintenance is essential for effectiveness
- False positives require investigation, not dismissal

For additional security hardening, consider the complete bashmin security suite including fail2ban, ufw, and lynis.
