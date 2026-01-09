# Generic Virtual Host Creator

The `add-vhost.sh` script provides a unified interface for creating complete virtual host stacks with nginx reverse proxy to either Apache2 or FrankenPHP backends.

## Features

- **Unified Interface**: Single command to create full stack (backend + nginx proxy + SSL)
- **Backend Selection**: Choose between Apache2 or FrankenPHP
- **Interactive Mode**: Prompts for all required configuration if not provided
- **Project Directory Selection**: Specify custom project paths or use defaults
- **PHP Version Management**: Auto-detects and allows selection from installed PHP versions
- **SSL Support**: Automatic SSL configuration (can be disabled)
- **Dry Run Mode**: Preview changes without executing

## Architecture

```
Internet → Nginx (80/443) → Apache2/FrankenPHP (8080+/8100+) → PHP-FPM → Application
```

## Usage

### Basic (Interactive)

```bash
./add-vhost.sh example.com
```

This will:
1. Prompt you to select backend (apache2 or frankenphp)
2. Prompt for project directory (default: `/var/www/vhosts/example.com`)
3. Prompt for PHP version selection from installed versions
4. Create backend virtual host
5. Create nginx reverse proxy
6. Update `/etc/hosts` file
7. Reload services

### Command Line Options

```bash
./add-vhost.sh [OPTIONS] DOMAIN

Options:
  -d, --domain DOMAIN     Domain name (alternative to positional arg)
  -b, --backend TYPE      Backend server type: apache2, frankenphp
  -p, --project-dir PATH  Project directory path
  --php-version VERSION   PHP version to use (auto-detected if not specified)
  --no-ssl                Disable SSL/TLS
  --force                 Force creation even if vhost exists
  --verbose               Enable verbose output
  --dry-run               Show what would be done without executing
  -h, --help              Show help message
```

### Examples

#### Apache2 Backend

```bash
# Basic with Apache2
./add-vhost.sh -b apache2 example.com

# Custom project directory
./add-vhost.sh -b apache2 -p /var/www/myapp example.com

# Specific PHP version
./add-vhost.sh -b apache2 --php-version 8.4 api.example.com

# Without SSL
./add-vhost.sh -b apache2 --no-ssl local.dev
```

#### FrankenPHP Backend

```bash
# Basic with FrankenPHP
./add-vhost.sh -b frankenphp example.com

# Custom project directory
./add-vhost.sh -b frankenphp -p /var/www/myapp example.com

# Specific PHP version
./add-vhost.sh -b frankenphp --php-version 8.5 api.example.com
```

#### Preview Changes

```bash
# See what would be done without executing
./add-vhost.sh --dry-run --verbose -b apache2 test.com
```

## Bash Alias

After installing aliases, you can use:

```bash
add-vhost example.com
```

## Backend Port Assignments

### Apache2
- HTTP: 8080, 8081, 8082 (based on PHP version/port selection)
- HTTPS: 8443, 8444, 8445

### FrankenPHP
- HTTP: 8100-8199
- HTTPS: 8143 (and other ports in range)

## Project Directory Structure

The script expects/creates the following structure:

```
/var/www/vhosts/example.com/
├── public/           # Web-accessible files (document root)
│   └── index.php     # Entry point
├── logs/             # Application logs
└── tmp/              # Temporary files
```

- **Apache2**: Uses `--webroot` to specify the `public/` directory directly
- **FrankenPHP**: Uses `--root` to specify the base directory (adds `/public` automatically)

## Prerequisites

### Required
- Nginx (for reverse proxy)
- Either Apache2 OR FrankenPHP installed and configured
- Sudo privileges

### Installation
```bash
# Install Nginx
./servers/nginx/install.sh

# Install Apache2 (choose one)
./servers/apache2/install.sh

# OR Install FrankenPHP (choose one)
./servers/frankenphp/install.sh
```

## How It Works

1. **Validation**: Checks domain name and prerequisites
2. **Backend Selection**: Prompts or validates backend choice
3. **Project Directory**: Prompts for or validates project path
4. **PHP Version**: Auto-detects available versions and prompts for selection
5. **Backend Creation**: Runs backend-specific add-vhost script
6. **Proxy Creation**: Configures nginx reverse proxy to backend
7. **Service Reload**: Reloads nginx and backend services
8. **Hosts Update**: Adds domain to `/etc/hosts`

## PHP Version Support

The script automatically:
- Detects all installed PHP versions (8.5, 8.4, 8.3, 8.2, 8.1, 8.0, 7.4)
- Presents an interactive menu for selection
- Validates specified versions against installed versions
- Defaults to latest installed version

## SSL Configuration

By default, SSL is enabled and will:
- Create SSL certificates (via Let's Encrypt or self-signed)
- Configure HTTPS on nginx (ports 80 → 443)
- Set security headers

Disable with `--no-ssl` for local development.

## Troubleshooting

### Check Service Status
```bash
sudo systemctl status nginx
sudo systemctl status apache2    # or frankenphp
```

### View Logs
```bash
# Nginx logs
sudo tail -f /var/log/nginx/example.com-*.log

# Apache2 logs
sudo tail -f /var/log/apache2/example.com-*.log

# FrankenPHP logs
sudo journalctl -u frankenphp -f
```

### Test Configuration
```bash
# Nginx
sudo nginx -t

# Apache2
sudo apache2ctl -t
```

### Manual Service Reload
```bash
sudo systemctl reload nginx
sudo systemctl reload apache2    # or frankenphp
```

## Advanced Usage

### Force Overwrite Existing
```bash
./add-vhost.sh --force -b apache2 existing.com
```

### Multiple Environments
```bash
# Production (Apache2)
./add-vhost.sh -b apache2 -p /var/www/prod/myapp myapp.com

# Staging (FrankenPHP)
./add-vhost.sh -b frankenphp -p /var/www/staging/myapp staging.myapp.com
```

## Related Scripts

- **Apache2 Direct**: `./servers/apache2/add-vhost.sh`
- **FrankenPHP Direct**: `./servers/frankenphp/add-vhost.sh`
- **Nginx Proxy**: `./servers/nginx/add-proxy.sh`
- **Update Hosts**: `./hosts/update-hosts.sh`

## Notes

- The generic script creates a **complete stack** with nginx proxy
- For backend-only configuration (no nginx), use the specific backend scripts directly
- Project directories are created automatically if they don't exist
- Both Apache2 and FrankenPHP scripts support custom project directory selection:
  - Apache2: `--webroot /path/to/public`
  - FrankenPHP: `--root /path/to/project` (appends `/public` automatically)
