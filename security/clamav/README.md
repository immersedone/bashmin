# ClamAV Antivirus Installation Script

This script provides comprehensive installation and configuration of ClamAV antivirus with enterprise-grade security features for Ubuntu/Debian systems.

## Features

### 🛡️ Comprehensive Protection
- **Real-time Scanning**: Optional on-access scanning for immediate threat detection
- **Scheduled Scans**: Automated daily system scans with customizable timing
- **Quarantine Management**: Automatic isolation of infected files
- **Multi-format Detection**: Supports archives, PDFs, office documents, executables, and email files

### 🔧 Advanced Configuration
- **Daemon Mode**: High-performance daemon with socket-based communication
- **Custom Scan Paths**: Configurable directories and exclusion patterns
- **Performance Tuning**: Adjustable file size limits, scan timeouts, and recursion levels
- **Network Integration**: TCP socket support for remote scanning requests

### 📊 Monitoring & Notifications
- **Email Alerts**: Automatic notifications for detected threats and scan results
- **Comprehensive Logging**: Structured logging with automatic rotation
- **System Integration**: Full systemd service management and socket activation
- **Statistics**: Optional scanning performance and detection statistics

### 🚀 Enterprise Features
- **Signature Updates**: Automated virus database updates with configurable frequency
- **Phishing Protection**: Advanced phishing and malware detection
- **Bytecode Signatures**: Support for advanced signature technologies
- **Mirror Selection**: Configurable update mirrors for faster downloads

## Quick Start

### Basic Antivirus Protection
```bash
sudo ./security/clamav/install.sh
```
- Installs ClamAV with daemon mode
- Schedules daily scans at 2:00 AM
- Scans /home, /var/www, and /opt directories
- Quarantines infected files automatically

### Web Server Configuration
```bash
sudo ./security/clamav/install.sh \
  --enable-on-access \
  --scan-dirs /var/www,/home,/opt \
  --email admin@example.com
```

### Mail Server Setup
```bash
sudo ./security/clamav/install.sh \
  --enable-mail-scan \
  --enable-phishing \
  --email security@company.com \
  --scan-dirs /var/mail,/home
```

### High-Security File Server
```bash
sudo ./security/clamav/install.sh \
  --enable-on-access \
  --scan-dirs /home,/srv,/var/www \
  --log-level DEBUG \
  --quarantine-dir /secure/quarantine \
  --max-file-size 500M
```

### Development Server (Optimized)
```bash
sudo ./security/clamav/install.sh \
  --disable-archive-scan \
  --max-file-size 50M \
  --exclude-patterns "*.tmp,*.log,node_modules/*,.git/*,*.cache" \
  --scan-dirs /home,/var/www
```

## Advanced Configuration

### Daemon Options
```bash
# TCP socket for network access
--tcp-socket --tcp-port 3310 --tcp-addr 0.0.0.0

# Disable daemon (command-line only)
--disable-daemon

# Enable real-time scanning
--enable-on-access
```

### Scanning Configuration
```bash
# Custom scan directories
--scan-dirs /var/www,/home,/srv,/opt

# Exclude patterns for performance
--exclude-patterns "*.tmp,*.log,node_modules/*,.git/*,__pycache__/*"

# Performance tuning
--max-file-size 200M --max-recursion 20 --max-scan-time 300

# Custom quarantine location
--quarantine-dir /secure/quarantine
```

### Detection Settings
```bash
# Comprehensive scanning
--enable-mail-scan --enable-phishing --enable-bytecode

# Lightweight scanning
--disable-archive-scan --disable-pdf-scan --disable-office-scan

# Executable protection
--enable-pe-scan --enable-elf-scan
```

### Scheduling & Updates
```bash
# Custom scan time
--scan-time 03:30

# Frequent updates
--update-frequency 6

# Custom mirror
--update-mirror your-local-mirror.com
```

## Configuration Files

The script manages several configuration files:

### ClamAV Configuration
- **Daemon Config**: `/etc/clamav/clamd.conf`
- **Update Config**: `/etc/clamav/freshclam.conf`
- **Database Directory**: `/var/lib/clamav`
- **Socket File**: `/var/run/clamav/clamd.ctl`

### Logging & Rotation
- **Main Log**: `/var/log/clamav/clamav.log`
- **Update Log**: `/var/log/clamav/freshclam.log`
- **Log Rotation**: `/etc/logrotate.d/clamav*`

### Systemd Services
- **Daemon Service**: `clamav-daemon.service`
- **Update Service**: `clamav-freshclam.service`
- **Scan Timer**: `clamav-daily-scan.timer`
- **Socket Service**: `clamav-daemon.socket`

### Custom Scripts
- **Daily Scan Script**: `/usr/local/bin/clamav/daily-scan.sh`
- **Quarantine Directory**: `/var/quarantine/clamav` (default)

## Management & Monitoring

### Service Management
```bash
# Check service status
sudo systemctl status clamav-daemon
sudo systemctl status clamav-freshclam

# View scan timer status
sudo systemctl status clamav-daily-scan.timer
sudo systemctl list-timers | grep clamav

# Restart services
sudo systemctl restart clamav-daemon
sudo systemctl restart clamav-freshclam
```

### Manual Scanning
```bash
# Quick scan of specific directory
sudo clamscan -r /var/www

# Scan with quarantine
sudo clamscan -r --move=/var/quarantine/clamav /home

# Verbose scan with detailed output
sudo clamscan -v -r --infected /path/to/scan

# Daemon-based scanning (faster)
clamdscan /path/to/scan
```

### Log Monitoring
```bash
# Real-time log monitoring
sudo tail -f /var/log/clamav/clamav.log

# View daily scan results
sudo journalctl -u clamav-daily-scan

# Check freshclam update logs
sudo tail -f /var/log/clamav/freshclam.log

# Search for infected files
sudo grep -i "found" /var/log/clamav/clamav.log
```

### Database Management
```bash
# Check database version
sudo freshclam --version

# Manual database update
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl start clamav-freshclam

# Check database info
sudo sigtool --info /var/lib/clamav/main.cvd
```

### Socket Communication
```bash
# Test Unix socket
echo "PING" | socat - UNIX-CONNECT:/var/run/clamav/clamd.ctl

# Test TCP socket (if enabled)
echo "PING" | nc localhost 3310

# Get version info
echo "VERSION" | socat - UNIX-CONNECT:/var/run/clamav/clamd.ctl
```

## Performance Optimization

### System Resource Management
```bash
# For low-memory systems
--max-file-size 50M --max-recursion 10

# For high-performance systems
--max-file-size 1G --max-recursion 25 --max-scan-time 600

# Exclude development directories
--exclude-patterns "node_modules/*,.git/*,__pycache__/*,*.tmp,*.log"
```

### Network Optimization
```bash
# Use local mirror for faster updates
--update-mirror your-local-mirror.example.com

# Reduce update frequency for bandwidth savings
--update-frequency 48
```

### Scanning Strategy
```bash
# Real-time for critical paths only
--enable-on-access --scan-dirs /var/www,/home/important

# Scheduled scans for everything else
--scan-dirs /home,/opt,/srv,/var/backups --scan-time 01:00
```

## Security Considerations

### ⚠️ Important Notes
- **Performance Impact**: On-access scanning can affect system performance
- **Resource Usage**: Large file scanning consumes CPU and memory
- **False Positives**: Review quarantined files before permanent deletion
- **Update Frequency**: Balance security vs. bandwidth requirements

### Best Practices
1. **Regular Monitoring**: Check logs and scan results daily
2. **Quarantine Review**: Periodically review quarantined files
3. **Exclusion Lists**: Exclude known-safe development directories
4. **Performance Testing**: Monitor system load with on-access scanning
5. **Backup Integration**: Scan backup files before storage

### Incident Response
```bash
# Emergency scan of critical systems
sudo clamscan -r --infected /var/www /home

# Quarantine suspicious files immediately
sudo clamscan -r --move=/urgent/quarantine /path/to/scan

# Check for specific threats
sudo clamscan -r --log=/tmp/emergency-scan.log /entire/system
```

## Integration Features

### Email Notifications
- **Threat Alerts**: Automatic emails when malware is detected
- **Scan Reports**: Daily summaries of scan results
- **Service Alerts**: Notifications for service failures or configuration issues
- **Custom Recipients**: Multiple email addresses supported

### Systemd Integration
- **Service Management**: Full systemd service lifecycle management
- **Socket Activation**: On-demand daemon startup
- **Timer-based Scans**: Reliable scheduled scanning with systemd timers
- **Auto-restart**: Automatic service recovery on failures

### bashmin Integration
- **Log Rotation**: Uses existing bashmin logrotate configurations
- **Service Monitoring**: Integrates with bashmin service monitoring
- **Notification Scripts**: Uses bashmin notification infrastructure
- **Configuration Patterns**: Follows bashmin CLI and configuration standards

## Troubleshooting

### Common Issues

**Database Update Failures**
```bash
# Check network connectivity
sudo freshclam --verbose

# Manual update with debug
sudo freshclam --debug --verbose

# Check mirror availability
dig db.local.clamav.net
```

**Service Start Failures**
```bash
# Check configuration syntax
sudo clamd --config-check

# Review service logs
sudo journalctl -u clamav-daemon -f

# Check socket permissions
ls -la /var/run/clamav/
```

**Performance Issues**
```bash
# Monitor resource usage during scans
htop

# Check scan statistics
sudo grep -i "stats" /var/log/clamav/clamav.log

# Adjust scanning parameters
--max-file-size 50M --max-scan-time 60
```

**False Positive Management**
```bash
# Check quarantined files
ls -la /var/quarantine/clamav/

# Review specific detections
sudo clamscan --log=/tmp/detailed.log /path/to/file

# Report false positives to ClamAV
# https://www.clamav.net/reports/fp
```

### Debug Mode
```bash
# Maximum verbosity with dry-run
sudo ./security/clamav/install.sh --dry-run --verbose --log-level DEBUG

# Test configuration without installation
sudo ./security/clamav/install.sh --dry-run --enable-on-access --email test@example.com
```

## Related bashmin Tools

- **UFW Firewall**: `security/ufw/` - Network security and access control
- **fail2ban**: `security/ubuntu/fail2ban/` - Intrusion detection and prevention
- **SSH Hardening**: `sshd/configure.sh` - SSH daemon security configuration
- **System Monitoring**: `self-healing/` - Automated system health monitoring
- **Log Management**: `system/etc/logrotate.d/` - Centralized log rotation

## Updates & Maintenance

### Regular Maintenance Tasks
1. **Weekly**: Review scan logs and quarantine directory
2. **Monthly**: Check system performance impact
3. **Quarterly**: Review and update exclusion patterns
4. **Annually**: Review and update scanning policies

### Signature Database
- **Automatic Updates**: Configured via freshclam service
- **Update Frequency**: Configurable (default: 24 hours)
- **Mirror Management**: Automatic failover between mirrors
- **Bandwidth Control**: Configurable update scheduling

### Configuration Updates
```bash
# Reconfigure with new settings
sudo ./security/clamav/install.sh --force --new-options

# Update scan directories
sudo systemctl edit clamav-daily-scan.service

# Modify exclusion patterns
sudo nano /usr/local/bin/clamav/daily-scan.sh
```

---

For comprehensive server security, combine ClamAV with other bashmin security tools for layered protection.
