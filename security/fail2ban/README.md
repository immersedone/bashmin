# fail2ban Intrusion Prevention Installation Script

This script provides comprehensive installation and configuration of fail2ban intrusion prevention system with enterprise-grade security features for Ubuntu/Debian systems.

## Features

### 🛡️ Comprehensive Protection
- **Multi-Service Support**: Protection for SSH, Nginx, Apache, Postfix, Dovecot, MySQL, phpMyAdmin, WordPress, and FTP servers
- **Intelligent Banning**: Advanced pattern recognition with customizable ban times and retry limits
- **Recidive Detection**: Escalating penalties for repeat offenders with separate jail management
- **Geographic Blocking**: Country-based IP blocking using GeoIP databases

### 🚨 Advanced Notifications
- **Email Alerts**: Comprehensive email notifications for bans, unbans, and jail status changes
- **Slack Integration**: Real-time Slack webhook notifications for security events
- **Custom Actions**: Support for custom notification mechanisms and response actions
- **Persistent Storage**: Optional persistent ban storage across service restarts

### 🌐 Network Intelligence
- **Trusted Networks**: Intelligent whitelisting for administrative and trusted networks
- **IP Reputation**: Geographic and reputation-based blocking with country code filtering
- **Custom Filters**: Advanced pattern matching with custom regex filters for specialized protection
- **Dynamic Updates**: Real-time monitoring with multiple backend options (systemd, polling, auto)

### 📊 Enterprise Management
- **Centralized Configuration**: bashmin-integrated configuration templates and best practices
- **Log Integration**: Structured logging with automatic rotation and analysis capabilities
- **Service Monitoring**: Full systemd integration with auto-restart and health monitoring
- **Performance Optimization**: Optimized for high-traffic servers with efficient log processing

## Quick Start

### Basic SSH Protection
```bash
sudo ./security/fail2ban/install.sh
```
- Enables SSH brute force protection
- 1-hour ban time with 5 failed attempts in 10 minutes
- Uses system logs for monitoring

### Web Server Protection
```bash
sudo ./security/fail2ban/install.sh \
  --enable-nginx \
  --ban-time 2h \
  --max-retry 3
```

### Mail Server Configuration
```bash
sudo ./security/fail2ban/install.sh \
  --enable-postfix \
  --enable-dovecot \
  --email admin@example.com
```

### High-Security Setup
```bash
sudo ./security/fail2ban/install.sh \
  --enable-nginx \
  --enable-mysql \
  --blocked-countries CN,RU,KP \
  --ban-time 24h \
  --recidive-ban-time 30d \
  --email security@company.com
```

### Enterprise Configuration
```bash
sudo ./security/fail2ban/install.sh \
  --enable-nginx \
  --enable-postfix \
  --enable-mysql \
  --enable-wordpress \
  --email security@company.com \
  --slack-webhook https://hooks.slack.com/services/... \
  --trusted-networks 192.168.1.0/24,10.0.0.0/8 \
  --enable-persistent-bans
```

## Service Protection

### Web Services
```bash
# Nginx protection (recommended for web servers)
--enable-nginx

# Apache protection
--enable-apache

# WordPress specific protection
--enable-wordpress
```

**Nginx Jails Include:**
- HTTP authentication failures
- Script scanning attempts
- Bad request patterns
- Proxy abuse attempts
- Bot scanning protection
- Rate limiting violations

**Apache Jails Include:**
- Authentication failures
- Bot detection and blocking
- Script injection attempts
- Buffer overflow attempts
- Directory traversal attempts

### Mail Services
```bash
# Postfix SMTP protection
--enable-postfix

# Dovecot IMAP/POP3 protection
--enable-dovecot
```

**Mail Protection Features:**
- SASL authentication failures
- RBL/DNSBL violations
- SMTP abuse detection
- IMAP/POP3 brute force protection

### Database Services
```bash
# MySQL/MariaDB protection
--enable-mysql

# phpMyAdmin protection
--enable-phpmyadmin
```

**Database Protection:**
- Authentication failure detection
- SQL injection attempt blocking
- Administrative interface protection

### FTP Services
```bash
# vsftpd protection
--enable-vsftpd

# ProFTPD protection
--enable-proftpd
```

## Advanced Security Features

### Geographic Blocking
```bash
# Enable country-based blocking
--enable-geographic-blocking --blocked-countries CN,RU,IR,KP

# Automatic GeoIP database integration
# Blocks entire country IP ranges
```

### Recidive Jail (Repeat Offenders)
```bash
# Enhanced penalties for repeat offenders
--enable-recidive \
--recidive-ban-time 1w \
--recidive-find-time 1d \
--recidive-max-retry 5
```

### Persistent Bans
```bash
# Maintain bans across service restarts
--enable-persistent-bans \
--persistent-ban-file /var/lib/fail2ban/persistent.bans
```

### Network Trust Management
```bash
# Never ban trusted networks
--trusted-networks 192.168.1.0/24,10.0.0.0/8,172.16.0.0/12

# Custom ignore IPs
--ignore-ips 127.0.0.1/8,::1,203.0.113.0/24
```

## Notification Systems

### Email Notifications
```bash
# Basic email alerts
--email admin@example.com

# Custom SMTP configuration
--email admin@example.com \
--email-sender security@company.com \
--smtp-host mail.company.com \
--smtp-port 587
```

**Email Features:**
- Ban/unban notifications
- Jail start/stop alerts
- Failed login summaries
- IP reputation reports

### Slack Integration
```bash
# Real-time Slack notifications
--slack-webhook https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX
```

**Slack Notifications Include:**
- Real-time ban alerts
- Jail status changes
- Service start/stop notifications
- Security event summaries

## Configuration Management

### Ban Time Configuration
```bash
# Short bans for development
--ban-time 30m

# Standard production bans
--ban-time 2h

# Long-term bans for persistent threats
--ban-time 7d

# Permanent bans
--ban-time -1
```

### Detection Sensitivity
```bash
# Strict detection (fewer attempts)
--max-retry 3 --find-time 5m

# Standard detection
--max-retry 5 --find-time 10m

# Lenient detection (for development)
--max-retry 10 --find-time 30m
```

### Backend Optimization
```bash
# Systemd journal (fastest, recommended)
--backend systemd

# File polling (universal compatibility)
--backend polling

# Auto-detection (default)
--backend auto
```

## Custom Jails and Actions

### Custom Jails
```bash
# Enable custom application protection
--custom-jails "api-rate-limit,app-auth-failures,ddos-protection"
```

### Custom Actions
```bash
# Custom notification and response actions
--custom-actions "telegram-notify,webhook-alert,firewall-escalate"
```

## Management & Monitoring

### Service Management
```bash
# Check fail2ban status
sudo systemctl status fail2ban

# Check all jail status
sudo fail2ban-client status

# Check specific jail
sudo fail2ban-client status sshd

# Reload configuration
sudo fail2ban-client reload
```

### Manual IP Management
```bash
# Ban IP manually
sudo fail2ban-client set sshd banip 192.0.2.100

# Unban IP
sudo fail2ban-client set sshd unbanip 192.0.2.100

# Check banned IPs
sudo fail2ban-client status sshd
```

### Log Analysis
```bash
# View recent activity
sudo tail -f /var/log/fail2ban/fail2ban.log

# Search for specific IP
sudo grep "192.0.2.100" /var/log/fail2ban/fail2ban.log

# Recent bans
sudo grep "Ban " /var/log/fail2ban/fail2ban.log | tail -10

# Recent unbans
sudo grep "Unban " /var/log/fail2ban/fail2ban.log | tail -10
```

### Jail-Specific Commands
```bash
# SSH jail management
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd bantime 3600
sudo fail2ban-client set sshd maxretry 3

# Nginx jail management
sudo fail2ban-client status nginx-http-auth
sudo fail2ban-client set nginx-http-auth unbanip 192.0.2.100

# WordPress jail management
sudo fail2ban-client status wordpress-auth
```

## Performance Optimization

### High-Traffic Servers
```bash
# Optimized for high traffic
--backend systemd \
--find-time 5m \
--max-retry 10 \
--ban-time 1h
```

### Resource-Constrained Systems
```bash
# Minimal resource usage
--backend polling \
--log-level WARNING \
--disable-recidive
```

### Development Environments
```bash
# Developer-friendly settings
--trusted-networks 192.168.0.0/16,10.0.0.0/8 \
--ban-time 10m \
--max-retry 20 \
--find-time 30m
```

## Security Profiles

### Basic Server Profile
- SSH protection only
- Standard ban times (1 hour)
- Local logging
- No geographic blocking

### Web Server Profile
- SSH + Nginx/Apache protection
- Enhanced bot detection
- Rate limiting protection
- Custom filters for common attacks

### Mail Server Profile
- SSH + Postfix + Dovecot protection
- SMTP abuse detection
- SASL authentication monitoring
- RBL integration

### Database Server Profile
- SSH + MySQL protection
- phpMyAdmin security
- SQL injection detection
- Administrative interface protection

### High-Security Profile
- All service protections enabled
- Geographic blocking
- Persistent bans
- Email and Slack notifications
- Recidive jail with escalating penalties

## Integration Features

### bashmin Integration
- **Configuration Templates**: Uses optimized bashmin jail and filter configurations
- **Log Rotation**: Integrates with bashmin logrotate configurations
- **Service Monitoring**: Uses bashmin systemd service templates with auto-healing
- **Notification Scripts**: Leverages bashmin notification infrastructure

### System Integration
- **iptables/netfilter**: Automatic firewall rule management
- **systemd**: Full service lifecycle management with socket activation
- **rsyslog**: Structured logging with automatic log parsing
- **logrotate**: Automatic log rotation and compression

### Security Ecosystem
- **UFW Integration**: Works alongside UFW firewall rules
- **ClamAV Compatibility**: Compatible with antivirus scanning
- **SSH Hardening**: Complements SSH security configurations
- **System Monitoring**: Integrates with system health monitoring

## Troubleshooting

### Common Issues

**Service Won't Start**
```bash
# Check configuration syntax
sudo fail2ban-client -t

# Check service logs
sudo journalctl -u fail2ban -f

# Test jail configuration
sudo fail2ban-client reload
```

**No Bans Occurring**
```bash
# Check log file paths
sudo fail2ban-client status [jail_name]

# Verify log file permissions
ls -la /var/log/auth.log /var/log/nginx/

# Test filter patterns
sudo fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf
```

**Email Notifications Not Working**
```bash
# Test mail system
echo "Test" | mail -s "fail2ban test" admin@example.com

# Check SMTP configuration
sudo fail2ban-client get sshd action sendmail

# Verify email settings in jail.local
sudo grep -A5 "destemail" /etc/fail2ban/jail.local
```

**High Resource Usage**
```bash
# Check backend efficiency
sudo fail2ban-client get [jail] backend

# Monitor process resources
htop | grep fail2ban

# Optimize log monitoring
--backend systemd --log-level WARNING
```

### Debug Mode
```bash
# Maximum verbosity with dry-run
sudo ./security/fail2ban/install.sh --dry-run --verbose --log-level DEBUG

# Test specific configuration
sudo ./security/fail2ban/install.sh --dry-run --enable-nginx --email test@example.com
```

## Security Considerations

### ⚠️ Important Warnings
- **Administrative Lockout**: Always configure trusted networks before enabling
- **Log File Access**: Ensure fail2ban can read relevant log files
- **Firewall Integration**: Test ban/unban functionality with existing firewall rules
- **Service Dependencies**: Verify protected services are properly configured

### Best Practices
1. **Gradual Deployment**: Start with basic SSH protection, then add services
2. **Monitoring Setup**: Configure notifications before enabling strict policies
3. **Testing Protocol**: Test ban/unban functionality in development first
4. **Backup Strategy**: Backup configurations before making changes
5. **Documentation**: Document custom filters and actions for team members

### Recovery Procedures
```bash
# Emergency access if locked out
# 1. Access via console or alternative network
# 2. Disable fail2ban temporarily
sudo systemctl stop fail2ban

# 3. Clear all bans
sudo iptables -F fail2ban-sshd

# 4. Reconfigure trusted networks
sudo nano /etc/fail2ban/jail.local

# 5. Restart with new configuration
sudo systemctl start fail2ban
```

## Related bashmin Tools

- **UFW Firewall**: `security/ufw/` - Network access control and basic firewall protection
- **ClamAV Antivirus**: `security/clamav/` - Malware detection and removal
- **SSH Hardening**: `sshd/configure.sh` - SSH daemon security configuration
- **System Monitoring**: `self-healing/` - Automated system health monitoring
- **Log Management**: `system/etc/logrotate.d/` - Centralized log rotation and analysis

## Updates & Maintenance

### Regular Maintenance Tasks
1. **Weekly**: Review banned IPs and false positives
2. **Monthly**: Analyze attack patterns and update filters
3. **Quarterly**: Review and update geographic blocking lists
4. **Annually**: Audit jail configurations and security policies

### Configuration Updates
```bash
# Update with new settings
sudo ./security/fail2ban/install.sh --force --new-options

# Add new jails to existing configuration
sudo ./security/fail2ban/install.sh --force --enable-wordpress

# Update notification settings
sudo ./security/fail2ban/install.sh --force --email new@example.com
```

### Filter Updates
- **Automatic**: fail2ban package updates include new filters
- **Manual**: Custom filters can be added to `/etc/fail2ban/filter.d/`
- **Community**: Additional filters available from fail2ban community
- **bashmin**: Updated filters distributed with bashmin releases

---

For comprehensive server security, combine fail2ban with other bashmin security tools for layered protection against modern threats.
