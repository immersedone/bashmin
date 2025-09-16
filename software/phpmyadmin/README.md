# phpMyAdmin Web Server Configuration

This directory contains scripts for installing and configuring phpMyAdmin with various web servers.

## Scripts

### 1. `install.sh`
Main installation script that downloads, installs, and configures phpMyAdmin.

**Features:**
- Downloads latest phpMyAdmin version automatically
- Supports Apache2 and FrankenPHP web servers
- Interactive URL configuration (subdirectory or subdomain)
- Automatic backup of existing installations
- Enhanced security configurations

**Usage:**
```bash
# Interactive installation
sudo ./install.sh

# The script will prompt you to:
# 1. Choose web server (Apache2, FrankenPHP, both, or none)
# 2. Select URL type (subdirectory or subdomain)
# 3. Configure access path/domain
```

### 2. `configure-webserver.sh`
Standalone script to configure phpMyAdmin for nginx, Apache2, or FrankenPHP (assumes phpMyAdmin is already installed).

**Features:**
- Supports nginx, Apache2, and FrankenPHP
- Both subdirectory and subdomain configurations
- Security hardening and optimization
- Configuration validation and testing
- Dry-run mode for testing

**Usage:**
```bash
# Interactive configuration
sudo ./configure-webserver.sh

# Non-interactive examples
sudo ./configure-webserver.sh -s nginx -t subdirectory
sudo ./configure-webserver.sh -s apache2 -t subdomain -d example.com
sudo ./configure-webserver.sh -s frankenphp -p admin-panel
sudo ./configure-webserver.sh -s all -t subdirectory -p secure-admin

# Preview configuration without making changes
sudo ./configure-webserver.sh --dry-run -s nginx -t subdomain -d mysite.com
```

## Configuration Options

### URL Types

#### Subdirectory Access
- **Default path:** `pma-1337`
- **Access URL:** `http://yoursite.com/pma-1337`
- **Custom path:** Specify with `-p` or `--path`

#### Subdomain Access
- **Default subdomain:** `pma`
- **Access URL:** `http://pma.yoursite.com`
- **Custom subdomain:** Specify with `--subdomain`
- **Domain required:** Specify with `-d` or `--domain`

### Web Server Support

#### nginx
- Optimized PHP-FPM integration
- Security headers and directory protection
- Static file optimization
- SSL-ready configuration templates

#### Apache2
- Virtual hosts for subdomains
- Alias configurations for subdirectories
- Security headers with mod_headers
- SSL placeholder configurations

#### FrankenPHP
- Modern PHP server with built-in HTTPS
- JSON-based configuration
- Automatic certificate management
- High-performance PHP handling

## Configuration Examples

### nginx Subdirectory Configuration
```nginx
# Access at http://yoursite.com/pma-1337
location /pma-1337 {
    alias /usr/share/phpmyadmin;
    index index.php;

    location ~ /pma-1337/(.+\.php)$ {
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME /usr/share/phpmyadmin/$1;
        include fastcgi_params;
    }
}
```

### Apache2 Subdomain Configuration
```apache
# Access at http://admin.example.com
<VirtualHost *:80>
    ServerName admin.example.com
    DocumentRoot /usr/share/phpmyadmin

    <Directory /usr/share/phpmyadmin>
        Options SymLinksIfOwnerMatch
        DirectoryIndex index.php
        Require all granted
    </Directory>
</VirtualHost>
```

### FrankenPHP Subdomain Configuration
```json
{
  "apps": {
    "http": {
      "servers": {
        "phpmyadmin": {
          "listen": [":80", ":443"],
          "routes": [
            {
              "match": [{"host": ["admin.example.com"]}],
              "handle": [{
                "handler": "php_server",
                "root": "/usr/share/phpmyadmin",
                "php_fastcgi": "unix//run/php/php8.3-fpm.sock"
              }]
            }
          ],
          "automatic_https": {"disable": false}
        }
      }
    }
  }
}
```

## Security Features

### Built-in Security
- **Directory Protection:** Blocks access to sensitive directories (`/templates`, `/libraries`, `/setup/lib`)
- **Security Headers:** X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, Referrer-Policy
- **PHP Security:** Proper `open_basedir` restrictions and secure configurations
- **SSL Ready:** HTTPS configurations prepared for all web servers

### Access Control
- **IP Restrictions:** Can be added to web server configurations
- **Authentication:** Consider adding additional authentication layers
- **Firewall:** Configure UFW or iptables to restrict access

## Requirements

- **PHP:** Version 7.4 or higher (8.3 recommended)
- **PHP Extensions:** Common extensions (mysql, mbstring, etc.)
- **Database:** MySQL 5.5+ or MariaDB 5.5+
- **Web Server:** One of nginx, Apache2, or FrankenPHP
- **System:** Ubuntu/Debian-based system with sudo privileges

## Troubleshooting

### Common Issues

1. **404 Not Found**
   - Check web server configuration syntax
   - Verify phpMyAdmin directory exists and has correct permissions
   - Ensure web server is reloaded after configuration changes

2. **PHP Not Processing**
   - Verify PHP-FPM is running: `sudo systemctl status php8.3-fpm`
   - Check PHP-FPM socket path in configuration
   - Ensure web server has proper PHP integration

3. **Permission Denied**
   - Check file permissions: `sudo chown -R www-data:www-data /usr/share/phpmyadmin`
   - Verify web server user has access to phpMyAdmin directory

4. **Database Connection Failed**
   - Ensure MySQL/MariaDB is running
   - Check database credentials and permissions
   - Verify phpMyAdmin configuration in `/etc/phpmyadmin/config.inc.php`

### Configuration Testing

```bash
# Test web server configurations
sudo nginx -t                    # nginx
sudo apache2ctl configtest       # Apache2
frankenphp validate --config /path/to/config.json  # FrankenPHP

# Check service status
sudo systemctl status nginx
sudo systemctl status apache2
sudo systemctl status frankenphp
sudo systemctl status php8.3-fpm
sudo systemctl status mysql
```

## File Locations

### Default Paths
- **phpMyAdmin:** `/usr/share/phpmyadmin`
- **Configuration:** `/etc/phpmyadmin/config.inc.php`
- **Temporary files:** `/var/lib/phpmyadmin/`
- **Backups:** `/var/backups/phpmyadmin/`

### Web Server Configs
- **nginx:** `/etc/nginx/sites-available/phpmyadmin`
- **Apache2:** `/etc/apache2/conf-available/phpmyadmin.conf`
- **FrankenPHP:** `/etc/frankenphp/sites-available/phpmyadmin.json`

### Logs
- **nginx:** `/var/log/nginx/`
- **Apache2:** `/var/log/apache2/`
- **FrankenPHP:** `/var/log/frankenphp/`
- **PHP-FPM:** `/var/log/php8.3-fpm.log`

## Advanced Configuration

### SSL/HTTPS Setup
Both scripts create SSL-ready configurations with placeholder certificate paths. To enable HTTPS:

1. Obtain SSL certificates (Let's Encrypt recommended)
2. Update certificate paths in web server configuration
3. Enable SSL modules/features
4. Test and reload web server configuration

### Multiple Domains
The scripts support configuring multiple web servers simultaneously. This allows you to:
- Run phpMyAdmin on different ports
- Use different domains for different web servers
- Implement load balancing or failover

### Custom PHP Versions
Specify PHP version with `--php-version` parameter:
```bash
sudo ./configure-webserver.sh -s nginx --php-version 8.4
```

## Support

For issues specific to these scripts, check:
1. Script output and error messages
2. Web server error logs
3. PHP-FPM error logs
4. Database server logs

For general phpMyAdmin issues, consult the [official phpMyAdmin documentation](https://docs.phpmyadmin.net/).