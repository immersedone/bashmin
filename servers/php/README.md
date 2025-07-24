# PHP Configuration Scripts

This directory contains scripts for managing PHP configurations across multiple PHP versions on Ubuntu-based systems.

## Scripts Overview

### `install.sh` - Complete PHP Installation & Configuration
**NEW:** Now includes automatic PHP configuration after installation! Installs PHP versions with extensions AND configures them with optimized settings in one go.

### `configure.sh` - Standalone Configuration Script
Configures PHP settings across all installed PHP versions for CLI, FPM, and Apache modules. Use this for reconfiguring existing PHP installations.

### `debug_version.sh` - Debug and Information Script  
Displays PHP version information, configuration files, and service status for troubleshooting.

## Quick Start

### Complete PHP Setup (Recommended)
```bash
# Interactive installation with configuration
./install.sh

# Silent production setup
./install.sh --silent --production

# Development environment with custom settings
./install.sh --development --memory-limit 1G --upload-size 256M
```

### Reconfigure Existing PHP
```bash
# Standalone configuration (for already installed PHP)
./configure.sh --production --silent

# Check current setup
./debug_version.sh --all
```

## Installation + Configuration Options

### Complete Workflows
```bash
# Production server setup (secure, optimized)
./install.sh --silent --production --with-apache

# Development environment (debug-friendly)  
./install.sh --silent --development --memory-limit 2G

# Custom installation with specific settings
./install.sh --version 8.3 --memory-limit 512M --upload-size 128M --production

# Install without auto-configuration (configure manually later)
./install.sh --silent --no-configure
```

## Common Use Cases

### New Server Setup
```bash
# Complete production setup from scratch
./install.sh --silent --production --version 8.3 --with-apache

# Development environment setup
./install.sh --development --memory-limit 2G --upload-size 256M
```

### Existing Server Reconfiguration
```bash
# Apply production settings to existing PHP
./configure.sh --production --silent

# Apply to FPM only with custom memory limit
./configure.sh --fpm-only --production --memory-limit 1G
```

### Specific Version Management
```bash
# Install and configure only PHP 8.3
./install.sh --version 8.3 --memory-limit 512M --upload-size 64M

# Reconfigure specific version later
./configure.sh --version 8.3 --cli-only --max-execution-time 0
```

## Configuration Options

### Installation + Configuration (install.sh)
- `--production` - Apply production-ready PHP configuration
- `--development` - Apply development-friendly PHP configuration  
- `--no-configure` - Skip PHP configuration after installation
- `--memory-limit SIZE` - Set PHP memory limit (default: 256M)
- `--upload-size SIZE` - Set upload max filesize (default: 128M)
- `--version VERSION` - Install specific PHP version
- `--with-apache` - Install Apache2 and PHP module
- `--no-extensions` - Skip PHP extensions installation

### Standalone Configuration (configure.sh)
- `--memory-limit` - Set memory_limit (default: 512M)
- `--upload-size` - Set upload_max_filesize and post_max_size (default: 64M)  
- `--max-execution-time` - Set max_execution_time (default: 300)
- `--max-input-vars` - Set max_input_vars (default: 3000)

### Environment Presets
- `--production` - Security-focused settings, OPcache enabled
- `--development` - Debug-friendly settings, verbose errors

### Target Applications
- `--cli-only` - Apply to CLI configuration only
- `--fpm-only` - Apply to FPM configuration only  
- `--apache-only` - Apply to Apache module only

### Safety Options
- `--dry-run` - Preview changes without applying
- `--no-backup` - Skip creating backup files
- `--verbose` - Show detailed output

## Key Settings Configured

### Performance Settings
```ini
memory_limit = 512M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
max_input_vars = 3000
opcache.enable = 1
```

### Security Settings (Production)
```ini
expose_php = Off
display_errors = Off
session.cookie_secure = 1
session.cookie_httponly = 1
session.use_strict_mode = 1
```

### Development Settings
```ini
display_errors = On
display_startup_errors = On
error_reporting = E_ALL
log_errors = On
```

## Debugging and Troubleshooting

### Check Configuration Applied
```bash
# Show all PHP version info
./debug_version.sh --all

# Check specific settings
./debug_version.sh --version 8.3 --verbose
```

### Verify Services
```bash
# Check FPM and Apache status
./debug_version.sh --services

# Check specific version service
systemctl status php8.3-fpm
```

### View Configuration Files
```bash
# Show ini file locations and recent changes
./debug_version.sh --ini-files

# Direct file inspection
php8.3 --ini
```

### Test PHP Functionality
```bash
# Quick syntax test
php8.3 -r "echo 'PHP working: ' . phpversion();"

# Check specific setting
php8.3 -r "echo 'Memory limit: ' . ini_get('memory_limit');"
```

## File Locations

### Configuration Files
- CLI: `/etc/php/8.3/cli/php.ini`
- FPM: `/etc/php/8.3/fpm/php.ini`  
- Apache: `/etc/php/8.3/apache2/php.ini`

### Service Files
- FPM Service: `php8.3-fpm`
- FPM Pools: `/etc/php/8.3/fpm/pool.d/`

### Log Files
- FPM Logs: `/var/log/php8.3-fpm.log`
- Error Logs: Check `error_log` setting in php.ini

## Safety Features

### Automatic Backups
The configure script automatically creates timestamped backups:
```
/etc/php/8.3/fpm/php.ini.backup.20250724_143022
```

### Rollback Process
```bash
# Find backup file
ls -la /etc/php/8.3/fpm/php.ini.backup.*

# Restore backup (example)
sudo cp /etc/php/8.3/fpm/php.ini.backup.20250724_143022 /etc/php/8.3/fpm/php.ini

# Restart services
sudo systemctl restart php8.3-fpm
```

### Validation
The script validates configuration values before applying:
- Memory formats (512M, 1G, etc.)
- Numeric values for timeouts and limits
- Timezone validity

## Integration with Other Scripts

### Integrated Workflow (NEW!)
The install script now automatically configures PHP after installation:
```bash
# Complete setup in one command
./install.sh --silent --production

# This replaces the old two-step process:
# ./install.sh --silent
# ./configure.sh --production
```

### Standalone Configuration
For existing PHP installations, use the standalone configuration script:
```bash
# Configure already installed PHP
./configure.sh --version 8.3 --production
```

### Web Server Integration
The install script automatically handles service restarts:
- PHP-FPM processes (restart after configuration)
- Apache (reload configuration if installed)
- Nginx (reload configuration if detected)

## Examples

### WordPress Optimized
```bash
./configure.sh \
  --memory-limit 512M \
  --upload-size 128M \
  --max-execution-time 300 \
  --max-input-vars 3000 \
  --production
```

### Laravel Development
```bash
./configure.sh \
  --memory-limit 1G \
  --max-execution-time 0 \
  --development \
  --cli-only
```

### High-Traffic API Server
```bash
./configure.sh \
  --memory-limit 2G \
  --max-execution-time 60 \
  --enable-opcache \
  --production \
  --fpm-only
```

## Error Handling

### Common Issues
1. **Permission Denied**: Run with sudo or ensure user has php config write access
2. **Service Not Found**: Check if PHP-FPM is installed for the version
3. **Invalid Values**: Use `--dry-run` to validate before applying

### Recovery Steps
1. Check backup files in `/etc/php/VERSION/SAPI/`
2. Restore from backup if needed
3. Use `debug_version.sh` to verify current state
4. Check service logs for errors

## Best Practices

1. **Always test first**: Use `--dry-run` before applying to production
2. **Backup important configs**: Default backup behavior saves you
3. **Monitor after changes**: Check application logs and performance
4. **Version-specific testing**: Test each PHP version separately
5. **Service restart verification**: Ensure services restart properly

For more details, run any script with `--help` to see all available options.
