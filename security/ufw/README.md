# UFW Firewall Installation Script

This script provides comprehensive installation and configuration of UFW (Uncomplicated Firewall) with enterprise-grade security hardening for Ubuntu/Debian systems.

## Features

### 🔒 Security Hardening
- **Kernel Security Parameters**: Configures SYN flood protection, IP spoofing protection, and other kernel-level security settings
- **Default Deny Policy**: Implements secure default policies (deny incoming, allow outgoing)
- **Rate Limiting**: Built-in SSH brute force protection with connection rate limiting
- **Network Security**: Disables dangerous features like source routing and ICMP redirects by default

### 🌐 Service Support
- **Web Services**: HTTP/HTTPS support for web servers
- **Database Support**: MySQL/MariaDB, PostgreSQL, MongoDB, Redis, Elasticsearch
- **Custom Ports**: Flexible port range support (single ports or ranges)
- **Trusted Networks**: Network-based access control for management subnets

### 📊 Logging & Monitoring
- **Structured Logging**: Integrates with existing bashmin rsyslog configuration
- **Log Rotation**: Automatic log rotation with compression
- **Multiple Log Levels**: off, low, medium, high, full logging levels
- **Centralized Logs**: All UFW logs directed to `/var/log/ufw/ufw.log`

### 🛠️ Application Profiles
- **Pre-built Profiles**: Nginx, Apache, development tools, databases
- **Custom Profiles**: Easy to extend with additional service profiles
- **Standard Compliance**: Uses UFW's standard application profile format

## Quick Start

### Basic Secure Server
```bash
sudo ./security/ufw/install.sh
```
- Enables SSH with rate limiting
- Denies all other incoming connections
- Allows all outgoing connections

### Web Server Configuration
```bash
sudo ./security/ufw/install.sh --allow-http --allow-https
```

### Database Server
```bash
sudo ./security/ufw/install.sh --allow-mysql --allow-postgresql --ssh-port 2222
```

### Development Server
```bash
sudo ./security/ufw/install.sh \
  --allow-ports 3000,8080,9000 \
  --trusted-networks 192.168.1.0/24 \
  --log-level medium
```

### High-Security Configuration
```bash
sudo ./security/ufw/install.sh \
  --incoming-policy reject \
  --disable-ipv6 \
  --log-level high \
  --ssh-port 2222 \
  --trusted-networks 10.0.0.0/8
```

## Advanced Usage

### Custom Port Ranges
```bash
# Allow specific ports
--allow-ports 8080,9000,3000-3010

# Block specific ports
--deny-ports 25,587,465
```

### Network Access Control
```bash
# Trust management networks
--trusted-networks 192.168.1.0/24,10.0.0.0/8

# Block problematic networks  
--blocked-networks 172.16.0.0/12
```

### Security Policies
```bash
# Conservative policies
--incoming-policy reject    # Reject instead of deny (sends ICMP response)
--outgoing-policy deny      # Restrict outgoing connections
--routed-policy deny        # Block packet forwarding

# Disable IPv6 if not needed
--disable-ipv6
```

## Testing & Validation

### Dry Run Mode
```bash
# Preview configuration without applying
sudo ./security/ufw/install.sh --dry-run --verbose --allow-https
```

### Force Reconfiguration
```bash
# Reconfigure existing UFW setup
sudo ./security/ufw/install.sh --force --allow-mysql
```

### Verbose Output
```bash
# Detailed installation process
sudo ./security/ufw/install.sh --verbose --allow-https --allow-mysql
```

## Configuration Files

The script manages several configuration files:

- **UFW Rules**: `/etc/ufw/`
- **Kernel Security**: `/etc/ufw/sysctl.conf`
- **Application Profiles**: `/etc/ufw/applications.d/`
- **Log Configuration**: `/etc/rsyslog.d/20-ufw.conf`
- **Log Rotation**: `/etc/logrotate.d/ufw`

## Monitoring & Management

### Check Firewall Status
```bash
sudo ufw status verbose
sudo ufw status numbered
```

### View Logs
```bash
# Real-time log monitoring
sudo tail -f /var/log/ufw/ufw.log

# Search for blocked connections
sudo grep BLOCK /var/log/ufw/ufw.log
```

### Manage Rules
```bash
# Add temporary rule
sudo ufw allow from 203.0.113.0/24 to any port 22

# Delete rule by number
sudo ufw delete 3

# Insert rule at specific position
sudo ufw insert 1 allow from 10.0.0.0/8
```

### Application Profiles
```bash
# List available profiles
sudo ufw app list

# Show profile details
sudo ufw app info "Nginx Full"

# Use application profile
sudo ufw allow "Nginx Full"
```

## Security Considerations

### ⚠️ Important Warnings
- **Test SSH access** before enabling UFW to avoid lockout
- **Use management network** for administrative access when possible
- **Monitor logs** for legitimate traffic being blocked
- **Document firewall rules** for team members

### Best Practices
1. **Principle of Least Privilege**: Only allow necessary services
2. **Regular Audits**: Review firewall rules periodically
3. **Log Monitoring**: Set up alerts for unusual blocking patterns
4. **Backup Rules**: Keep configuration backups before changes
5. **Testing**: Use dry-run mode before applying changes

### Recovery Options
```bash
# Disable firewall if locked out (via console)
sudo ufw disable

# Reset to defaults
sudo ufw --force reset

# Emergency SSH access (temporarily)
sudo ufw insert 1 allow 22
```

## Integration with bashmin

This script integrates seamlessly with the bashmin toolkit:

- **Logging**: Uses bashmin's standardized rsyslog configuration
- **Log Rotation**: Leverages existing logrotate patterns
- **Common Functions**: Shares bashmin helper functions
- **CLI Patterns**: Consistent with other bashmin tools
- **System Configs**: Integrates with bashmin's system configuration templates

## Troubleshooting

### Common Issues

**UFW already configured**
```bash
# Force reconfiguration
sudo ./security/ufw/install.sh --force
```

**SSH access blocked**
```bash
# Access via console and allow SSH
sudo ufw allow ssh
sudo ufw allow 22
```

**Logs not appearing**
```bash
# Restart rsyslog
sudo systemctl restart rsyslog

# Check log directory
ls -la /var/log/ufw/
```

**Service not starting**
```bash
# Check UFW status
sudo systemctl status ufw

# Enable UFW manually
sudo ufw enable
```

### Debug Mode
```bash
# Maximum verbosity with dry-run
sudo ./security/ufw/install.sh --dry-run --verbose --force
```

## Related bashmin Tools

- **fail2ban**: `security/ubuntu/fail2ban/` - Intrusion prevention
- **SSH Hardening**: `sshd/configure.sh` - SSH daemon security
- **System Security**: `security/ubuntu/` - Ubuntu security hardening
- **Log Management**: `system/etc/logrotate.d/` - Centralized log rotation

---

For more information about bashmin security tools, see the main project documentation.
