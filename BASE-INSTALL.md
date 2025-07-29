# bashmin Suite Base Installer

## Overview

The `base-install.sh` script is the main entry point for installing and configuring the entire bashmin suite. It provides three modes of operation:

1. **Interactive CLI GUI** (default) - User-friendly menu-driven interface
2. **Quiet Mode** - Minimal output for automated deployments
3. **Automatic Mode** - Preset-based installations

## Quick Start

### Interactive Installation (Recommended)
```bash
sudo ./base-install.sh
```

This launches the CLI GUI with the following main menu:
```
╔══════════════════════════════════════════════════════════════╗
║                    bashmin Suite Installer                  ║
║                  Enterprise Server Management               ║
╚══════════════════════════════════════════════════════════════╝

Installation Options:
1) Quick Install (Preset Configurations)
2) Custom Install (Select Individual Modules)
3) Security Suite Only (8-Layer Defense)
4) Development Environment
5) Web Server Stack
6) Full Installation (All Modules)
7) Show Module Information
8) View Installation Log
9) Exit
```

### Automated Installation
```bash
# Install security suite silently
sudo ./base-install.sh --quiet --preset security

# Install specific modules
sudo ./base-install.sh --modules "system,security-ufw,server-nginx" --quiet

# Development environment with verbose output
sudo ./base-install.sh --preset development --verbose
```

## Installation Modes

### 1. Interactive Mode (`--interactive` or default)
- Full CLI GUI with menu navigation
- Module selection by category
- Real-time installation progress
- Confirmation prompts for safety

### 2. Quiet Mode (`--quiet`)
- Minimal output for scripts/automation
- No interactive prompts
- Suitable for CI/CD pipelines
- Logs to file for debugging

### 3. Automatic Mode (`--auto`)
- Uses preset configurations
- No user interaction required
- Perfect for provisioning scripts

## Available Presets

| Preset | Description | Modules |
|--------|-------------|---------|
| `minimal` | Core system only | system, structure, users |
| `security` | 8-layer security suite | All security components + core |
| `webserver` | Web server stack | Apache2, PHP, MariaDB + security |
| `development` | Developer tools | Composer, NVM, Git hooks + core |
| `full` | Everything | All available modules |

## Module Categories

### Core System
- **system**: Basic system configuration
- **structure**: Directory structure setup
- **users**: User management and security

### Security Suite (8-Layer Defense)
- **security-ufw**: Network firewall protection
- **security-clamav**: Malware detection and quarantine
- **security-fail2ban**: Intrusion prevention system
- **security-letsencrypt**: SSL certificate management
- **security-lynis**: Security auditing and compliance
- **security-rkhunter**: Rootkit detection system
- **security-nikto**: Web vulnerability scanning
- **security-hardening**: Ubuntu system hardening

### Web Servers
- **server-apache2**: Apache HTTP Server
- **server-nginx**: Nginx web server
- **server-frankenphp**: Modern PHP server

### Databases
- **server-mariadb**: MariaDB database server
- **server-mongodb**: MongoDB document database
- **server-redis**: Redis in-memory database
- **server-elasticsearch**: Elasticsearch search engine
- **server-typesense**: Typesense search engine

### Development Tools
- **dev-composer**: PHP dependency manager
- **dev-nvm**: Node.js version manager
- **dev-pnpm**: Fast npm alternative
- **dev-cghooks**: Git hooks automation
- **dev-tldr**: Command documentation

## Command Line Options

```bash
./base-install.sh [OPTIONS]

OPTIONS:
    -h, --help              Show help message
    -i, --interactive       Interactive CLI GUI (default)
    -q, --quiet             Quiet mode - minimal output
    -a, --auto              Automatic mode with presets
    -m, --modules LIST      Comma-separated module list
    -p, --preset NAME       Use predefined preset
    -d, --dry-run           Preview without installing
    -v, --verbose           Enable verbose output
    -l, --log FILE          Custom log file location
    --list-modules          Show all available modules
    --list-presets          Show all available presets
```

## Usage Examples

### Basic Installations
```bash
# Interactive installation (recommended for first-time users)
sudo ./base-install.sh

# Install security suite only
sudo ./base-install.sh --preset security --quiet

# Install web server stack
sudo ./base-install.sh --preset webserver --verbose
```

### Custom Module Selection
```bash
# Install specific security modules
sudo ./base-install.sh --modules "security-ufw,security-fail2ban,security-clamav"

# Development environment with custom modules
sudo ./base-install.sh --modules "system,dev-composer,dev-nvm,server-nginx"
```

### Testing and Validation
```bash
# Test installation without executing
sudo ./base-install.sh --dry-run --preset full

# Verbose dry run for debugging
sudo ./base-install.sh --dry-run --verbose --modules "security-ufw,server-apache2"

# Custom log file location
sudo ./base-install.sh --log /tmp/my-install.log --preset development
```

## Interactive CLI GUI Navigation

The interactive mode provides an intuitive menu system:

1. **Main Menu**: Choose installation type or view information
2. **Preset Selection**: Quick installation with predefined configurations
3. **Module Categories**: Browse modules by functional category
4. **Module Selection**: Toggle individual modules on/off
5. **Installation Summary**: Review selections before proceeding

### Navigation Tips
- Use numeric keys to select menu options
- Modules can be toggled on/off in custom selection mode
- View selected modules before installation
- Installation progress is shown in real-time
- Logs are automatically saved for troubleshooting

## Troubleshooting

### Common Issues
1. **Permission denied**: Ensure you're running with `sudo`
2. **Module not found**: Use `--list-modules` to see available options
3. **Installation fails**: Check log file for detailed error messages
4. **Insufficient space**: Ensure at least 1GB free disk space

### Log Files
- Default location: `/var/log/bashmin/base-install-YYYYMMDD_HHMMSS.log`
- Custom location: Use `--log /path/to/logfile`
- View recent logs: Option 8 in interactive menu

### Debugging
```bash
# Verbose output with dry run
sudo ./base-install.sh --dry-run --verbose --preset full

# Check specific module availability
ls -la /var/www/vhosts/bashmin/security/*/install.sh

# Validate module mapping
sudo ./base-install.sh --list-modules
```

## Integration with CI/CD

Perfect for automated server provisioning:

```yaml
# Example GitHub Actions workflow
- name: Install bashmin security suite
  run: |
    cd /opt/bashmin
    sudo ./base-install.sh --quiet --preset security --log /tmp/security-install.log
```

```bash
# Example Ansible playbook task
- name: Install bashmin development environment
  shell: |
    cd /opt/bashmin
    ./base-install.sh --auto --preset development
  become: yes
```

The base installer provides enterprise-grade flexibility while maintaining ease of use for both interactive administration and automated deployment scenarios.
