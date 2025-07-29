# Let's Encrypt SSL/TLS Certificate Management

This directory provides comprehensive SSL/TLS certificate management using Let's Encrypt for the bashmin toolkit. It includes installation, certificate management, automated renewals, and monitoring capabilities.

## Overview

The Let's Encrypt integration consists of three main components:

1. **`install.sh`** - Comprehensive Let's Encrypt installation and configuration
2. **`ssl-manage.sh`** - SSL certificate management utility
3. **`/crons/ssl-renewals.sh`** - Automated renewal and monitoring cron job

## Features

### 🔒 Enterprise SSL Management
- **Multi-Domain Certificates**: Support for single domain, multi-domain (SAN), and wildcard certificates
- **Web Server Integration**: Automatic configuration for Nginx, Apache, and standalone deployments
- **Security Best Practices**: Modern cipher suites, HSTS, OCSP stapling, and security headers
- **Certificate Validation**: Comprehensive certificate health checks and validation

### 🔄 Automated Operations
- **Auto-Renewal**: Intelligent certificate renewal with failure detection and retry logic
- **Service Integration**: Automatic web server reloading after certificate updates
- **Backup & Recovery**: Automated certificate backup with configurable retention
- **Monitoring**: Proactive certificate expiry monitoring with configurable thresholds

### 📊 Monitoring & Notifications
- **Email Alerts**: Comprehensive email notifications for renewals, failures, and expiry warnings
- **Slack Integration**: Real-time Slack notifications for security events
- **Health Monitoring**: Certificate status tracking with detailed reporting
- **Log Management**: Structured logging with automatic rotation and analysis

### 🛡️ Security Features
- **OCSP Stapling**: Improved certificate validation performance and privacy
- **HSTS Support**: HTTP Strict Transport Security with preload capability
- **Secure Configuration**: Modern TLS protocols and cipher suites
- **Certificate Backup**: Encrypted backup storage with integrity verification

## Quick Start

### Basic Installation
```bash
# Install Let's Encrypt with default settings
sudo ./install.sh --email admin@example.com --agree-tos

# Install with Nginx integration
sudo ./install.sh --email ssl@company.com --webserver nginx --agree-tos
```

### Request Your First Certificate
```bash
# Basic domain certificate
ssl-manage --add-certificate example.com --email admin@example.com

# Multi-domain certificate
ssl-manage --add-certificate example.com \
    --domains "example.com,www.example.com,api.example.com"

# Wildcard certificate (requires DNS validation)
ssl-manage --add-certificate example.com --wildcard \
    --email admin@example.com
```

### Certificate Management
```bash
# List all certificates
ssl-manage --list-certificates

# Check specific certificate
ssl-manage --check-certificate example.com

# Test renewal
ssl-manage --test-renewal example.com

# Force renewal
ssl-manage --renew-certificate example.com --force
```

## Installation Guide

### Prerequisites
- Ubuntu 18.04+ or Debian 9+
- Root or sudo access
- Domain(s) pointing to your server
- Web server (Nginx/Apache) or ability to run standalone

### Basic Installation
```bash
# Clone bashmin (if not already done)
git clone https://github.com/immersedone/bashmin.git
cd bashmin

# Install Let's Encrypt
sudo security/letsencrypt/install.sh \
    --email your-email@example.com \
    --webserver auto \
    --agree-tos
```

### Advanced Installation
```bash
# High-security installation with monitoring
sudo security/letsencrypt/install.sh \
    --email security@company.com \
    --webserver nginx \
    --key-type ecdsa \
    --enable-ocsp-stapling \
    --notification-email alerts@company.com \
    --slack-webhook https://hooks.slack.com/services/... \
    --enable-monitoring \
    --backup-certificates \
    --agree-tos
```

### Development/Testing Setup
```bash
# Use staging environment for testing
sudo security/letsencrypt/install.sh \
    --email dev@example.com \
    --staging \
    --webserver standalone \
    --agree-tos \
    --dry-run
```

## Certificate Management

### Adding Certificates

#### Single Domain
```bash
ssl-manage --add-certificate example.com \
    --email admin@example.com \
    --webserver nginx
```

#### Multiple Domains (SAN)
```bash
ssl-manage --add-certificate example.com \
    --domains "example.com,www.example.com,api.example.com,admin.example.com" \
    --email admin@example.com
```

#### Wildcard Certificate
```bash
# Requires DNS validation
ssl-manage --add-certificate example.com \
    --wildcard \
    --email admin@example.com
```

### Certificate Operations

#### Renewal Management
```bash
# Test renewal (dry run)
ssl-manage --test-renewal example.com

# Force immediate renewal
ssl-manage --renew-certificate example.com --force

# Renew all certificates
certbot renew --force-renewal
```

#### Certificate Information
```bash
# Detailed certificate information
ssl-manage --check-certificate example.com

# List all certificates with status
ssl-manage --list-certificates

# Check expiry dates
ssl-manage --check-expiry
```

#### Backup & Recovery
```bash
# Manual backup
ssl-manage --backup-certificates

# List available backups
ls -la /var/backups/letsencrypt/

# Restore from backup (manual process)
# See recovery procedures section
```

### Certificate Revocation
```bash
# Revoke and delete certificate
ssl-manage --revoke-certificate example.com

# This will:
# 1. Revoke the certificate with Let's Encrypt
# 2. Remove certificate files
# 3. Disable web server configuration
```

## Web Server Integration

### Nginx Configuration

The system automatically creates secure Nginx configurations:

```nginx
# Generated SSL configuration for example.com
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name example.com;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    
    # Modern SSL Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    # ... additional security headers
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name example.com;
    
    # ACME challenge path
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # Redirect all other traffic
    location / {
        return 301 https://$server_name$request_uri;
    }
}
```

### Apache Configuration

Automatic Apache SSL virtual host configuration:

```apache
# SSL Virtual Host for example.com
<VirtualHost *:443>
    ServerName example.com
    DocumentRoot /var/www/vhosts/example.com
    
    # SSL Configuration
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/example.com/cert.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/example.com/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/example.com/chain.pem
    
    # Modern SSL Security
    SSLProtocol All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    SSLHonorCipherOrder on
    
    # OCSP Stapling
    SSLUseStapling on
    
    # Security Headers
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    Header always set X-Frame-Options "SAMEORIGIN"
    # ... additional security headers
</VirtualHost>
```

## Automated Renewals

### Systemd Timer (Primary)
```bash
# Check renewal timer status
systemctl status certbot-renewal.timer

# View next run time
systemctl list-timers certbot-renewal.timer

# Manual trigger
systemctl start certbot-renewal.service
```

### Cron Job (Backup)
```bash
# View cron configuration
cat /etc/cron.d/certbot

# Check cron logs
grep certbot /var/log/syslog
```

### Renewal Hooks

The system includes comprehensive renewal hooks:

#### Pre-Renewal (`/etc/letsencrypt/renewal-hooks/pre/`)
- Certificate backup creation
- Service health checks
- Pre-renewal validation

#### Post-Renewal (`/etc/letsencrypt/renewal-hooks/post/`)
- Web server reloading
- Service verification
- Notification dispatch

#### Deploy Hooks (`/etc/letsencrypt/renewal-hooks/deploy/`)
- Security configuration updates
- Certificate deployment verification
- Custom deployment actions

## Monitoring & Notifications

### Certificate Monitoring

#### Daily Health Checks
```bash
# Manual health check
/usr/local/bin/ssl-monitor

# View monitoring logs
tail -f /var/log/bashmin/ssl/monitoring.log

# Check certificate expiry
ssl-manage --check-expiry
```

#### Monitoring Thresholds
- **Warning**: 30 days before expiry
- **Critical**: 7 days before expiry
- **Immediate Action**: 1 day before expiry

### Email Notifications

Configure email notifications during installation:
```bash
sudo security/letsencrypt/install.sh \
    --email admin@example.com \
    --notification-email security@company.com \
    --agree-tos
```

**Notification Types:**
- Certificate renewal success/failure
- Expiry warnings (30, 7, 1 days)
- Service restart notifications
- Backup completion alerts

### Slack Integration

Set up Slack notifications:
```bash
sudo security/letsencrypt/install.sh \
    --email admin@example.com \
    --slack-webhook https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK \
    --agree-tos
```

**Slack Alerts Include:**
- Real-time renewal status
- Certificate expiry warnings
- System health notifications
- Service availability alerts

### Log Management

#### Log Locations
```bash
# Let's Encrypt logs
/var/log/letsencrypt/

# bashmin SSL logs
/var/log/bashmin/ssl/
├── letsencrypt.log      # Installation logs
├── ssl-manage.log       # Management operations
├── renewals.log         # Renewal activities
├── monitoring.log       # Certificate monitoring
└── weekly_report_*.txt  # Weekly reports
```

#### Log Rotation
Automatic log rotation is configured:
```bash
# View logrotate configuration
cat /etc/logrotate.d/bashmin-ssl

# Manual log rotation
logrotate -f /etc/logrotate.d/bashmin-ssl
```

## Security Features

### Modern TLS Configuration

#### RSA Certificates (Default)
- **Key Size**: 4096 bits
- **Protocols**: TLSv1.2, TLSv1.3
- **Cipher Suites**: Modern ECDHE suites

#### ECDSA Certificates (Recommended)
```bash
ssl-manage --add-certificate example.com \
    --key-type ecdsa \
    --email admin@example.com
```
- **Curve**: secp384r1
- **Performance**: Better performance than RSA
- **Security**: Equivalent security with smaller keys

### Security Headers

Automatic security header configuration:
```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Frame-Options: SAMEORIGIN
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
X-XSS-Protection: 1; mode=block
```

### OCSP Stapling

Enabled by default for improved performance:
- Faster certificate validation
- Enhanced privacy protection
- Reduced server load
- Better user experience

### Certificate Backup Security

- **Encrypted Storage**: Backups stored with secure permissions
- **Retention Policy**: Configurable retention (default: 30 days)
- **Integrity Verification**: Backup integrity checks
- **Access Control**: Restricted access to certificate files

## Troubleshooting

### Common Issues

#### Certificate Request Failures
```bash
# Check domain resolution
nslookup example.com

# Verify web server configuration
nginx -t  # or apache2ctl configtest

# Check firewall rules
ufw status

# Test ACME challenge path
curl http://example.com/.well-known/acme-challenge/test
```

#### Renewal Failures
```bash
# Test renewal manually
certbot renew --dry-run

# Check renewal logs
tail -f /var/log/letsencrypt/letsencrypt.log

# Verify certificate permissions
ls -la /etc/letsencrypt/live/example.com/

# Test web server reload
systemctl reload nginx  # or apache2
```

#### Permission Issues
```bash
# Fix certificate permissions
sudo chown -R root:root /etc/letsencrypt/
sudo chmod -R 600 /etc/letsencrypt/
sudo chmod 755 /etc/letsencrypt/ /etc/letsencrypt/live/

# Fix log directory permissions
sudo mkdir -p /var/log/bashmin/ssl/
sudo chown root:root /var/log/bashmin/ssl/
sudo chmod 755 /var/log/bashmin/ssl/
```

### Debug Mode

Enable verbose logging for troubleshooting:
```bash
# Dry run with verbose output
sudo security/letsencrypt/install.sh \
    --dry-run --verbose \
    --email admin@example.com \
    --agree-tos

# Certificate management with debug
ssl-manage --add-certificate example.com \
    --verbose --dry-run \
    --email admin@example.com
```

### Service Diagnostics

#### Check Service Status
```bash
# Certbot timer
systemctl status certbot-renewal.timer

# Web servers
systemctl status nginx
systemctl status apache2

# Certificate monitoring
/usr/local/bin/ssl-monitor
```

#### Test Configurations
```bash
# Nginx configuration test
nginx -t

# Apache configuration test
apache2ctl configtest

# SSL certificate validation
openssl x509 -in /etc/letsencrypt/live/example.com/cert.pem -text -noout
```

### Recovery Procedures

#### Certificate Recovery
```bash
# List available backups
ls -la /var/backups/letsencrypt/

# Extract backup
cd /var/backups/letsencrypt/
tar -xzf backup_YYYYMMDD_HHMMSS.tar.gz

# Restore certificates (manual process)
sudo cp -r backup_YYYYMMDD_HHMMSS/letsencrypt /etc/

# Reload web servers
sudo systemctl reload nginx apache2
```

#### Emergency Certificate Generation
```bash
# Generate self-signed certificate for emergency use
openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout /tmp/emergency.key \
    -out /tmp/emergency.crt \
    -subj "/CN=example.com"
```

## Advanced Configuration

### DNS Validation for Wildcards

For wildcard certificates, DNS validation is required:
```bash
# Install DNS plugin (example for Cloudflare)
sudo snap install certbot-dns-cloudflare

# Create credentials file
sudo nano /etc/letsencrypt/cloudflare.ini

# Request wildcard certificate
certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
    -d example.com \
    -d "*.example.com"
```

### Custom Certificate Profiles

#### High-Security Profile
```bash
ssl-manage --add-certificate example.com \
    --key-type ecdsa \
    --must-staple \
    --hsts-preload \
    --enable-ocsp \
    --email security@company.com
```

#### Development Profile
```bash
ssl-manage --add-certificate dev.example.com \
    --staging \
    --key-type rsa \
    --webserver standalone \
    --standalone-port 8080 \
    --email dev@company.com
```

### Integration with Load Balancers

#### HAProxy Integration
```haproxy
# HAProxy SSL termination with Let's Encrypt
frontend https_frontend
    bind *:443 ssl crt /etc/letsencrypt/live/example.com/fullchain.pem
    redirect scheme https if !{ ssl_fc }
    default_backend web_servers

backend web_servers
    balance roundrobin
    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check
```

#### Nginx Load Balancer
```nginx
# Nginx load balancer with SSL
upstream backend {
    server 192.168.1.10:80;
    server 192.168.1.11:80;
}

server {
    listen 443 ssl http2;
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    
    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Performance Optimization

### Certificate Management
- Use ECDSA certificates for better performance
- Enable OCSP stapling to reduce validation time
- Implement HTTP/2 for modern browsers
- Configure proper cipher suite ordering

### Monitoring Efficiency
- Schedule renewals during low-traffic periods
- Use systemd timers instead of cron for better reliability
- Implement certificate caching strategies
- Monitor renewal success rates

### Backup Optimization
- Compress backups to save storage space
- Implement incremental backup strategies
- Use retention policies to manage storage
- Verify backup integrity regularly

## Integration with bashmin

### System Integration
- **Logging**: Integrates with bashmin logging infrastructure
- **Monitoring**: Uses bashmin monitoring patterns
- **Security**: Follows bashmin security best practices
- **Configuration**: Uses bashmin configuration templates

### Service Coordination
- **Web Servers**: Coordinates with bashmin web server installations
- **Firewall**: Works with UFW firewall configurations
- **Monitoring**: Integrates with system health monitoring
- **Backup**: Coordinates with system backup strategies

### Related Tools
- **UFW Firewall**: `security/ufw/` - Network access control
- **fail2ban**: `security/fail2ban/` - Intrusion prevention
- **Web Servers**: `servers/nginx/`, `servers/apache2/` - Web server management
- **Monitoring**: `self-healing/` - System health monitoring

## Updates & Maintenance

### Regular Maintenance Tasks
1. **Weekly**: Review certificate status and renewal logs
2. **Monthly**: Test renewal process and backup procedures
3. **Quarterly**: Review security configurations and update policies
4. **Annually**: Audit certificate usage and cleanup unused certificates

### Update Procedures
```bash
# Update certbot
sudo snap refresh certbot

# Update bashmin SSL management
cd /var/www/vhosts/bashmin
git pull origin main

# Test configuration after updates
sudo security/letsencrypt/install.sh --dry-run --force
```

### Security Updates
- Monitor Let's Encrypt announcements for policy changes
- Update web server configurations for new security standards
- Review and update cipher suites regularly
- Keep SSL management tools updated

---

For comprehensive server security, combine Let's Encrypt SSL management with other bashmin security tools for complete protection against modern threats.
