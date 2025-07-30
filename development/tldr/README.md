# TLDR (Too Long; Didn't Read) Installation

## Overview

This script installs and configures the TLDR (Too Long; Didn't Read) community-driven manual pages system. TLDR provides simplified, practical examples for command-line tools, making it easier to understand and use various commands quickly.

## Features

### Multiple Client Options
- **Tealdeer** (Rust) - Fast, feature-rich, recommended
- **Node.js** - Cross-platform, rich features
- **C Client** - Lightweight, minimal dependencies
- **Python** - Feature-rich, extensible

### Multi-language Support
- English (default)
- Spanish, French, German, Italian
- Portuguese (Brazil), Russian
- Chinese, Japanese, Korean

### Advanced Features
- **Custom Pages**: Create your own command examples
- **Shell Completion**: Bash, Zsh, Fish support
- **Automatic Updates**: Scheduled cache updates
- **Syntax Highlighting**: Enhanced readability
- **Management Tools**: Comprehensive administration script

## Quick Installation

### Default Installation (Tealdeer)
```bash
sudo ./install.sh
```

### Custom Installation
```bash
# Install Node.js client with multiple languages
sudo ./install.sh --install-method node --languages "en,es,fr"

# Install with daily cache updates
sudo ./install.sh --cache-frequency daily

# Minimal installation without custom pages
sudo ./install.sh --disable-custom-pages --disable-completion
```

## Installation Methods

### 1. Tealdeer (Rust) - Recommended
- **Performance**: Fastest implementation
- **Features**: Best shell integration, syntax highlighting
- **Requirements**: None (static binary)
- **Installation**: Automatic binary download

```bash
sudo ./install.sh --install-method tealdeer
```

### 2. Node.js Client
- **Performance**: Good performance
- **Features**: Rich feature set, cross-platform
- **Requirements**: Node.js and npm
- **Installation**: Via npm global package

```bash
sudo ./install.sh --install-method node
```

### 3. C Client
- **Performance**: Fast and lightweight
- **Features**: Basic functionality, minimal footprint
- **Requirements**: Build tools (if compiling from source)
- **Installation**: Package or source compilation

```bash
# From package (preferred)
sudo ./install.sh --install-method c-client --client-type package

# From source
sudo ./install.sh --install-method c-client --client-type source
```

### 4. Python Client
- **Performance**: Good performance
- **Features**: Feature-rich, easily extensible
- **Requirements**: Python 3 and pip
- **Installation**: Via pip

```bash
sudo ./install.sh --install-method python
```

## Configuration Options

### Language Support
```bash
# Single language
sudo ./install.sh --language es

# Multiple languages
sudo ./install.sh --languages "en,es,fr,de"

# View available languages
./install.sh --list-languages
```

### Cache Management
```bash
# Automatic updates (default: weekly)
sudo ./install.sh --auto-update --cache-frequency daily

# Manual updates only
sudo ./install.sh --disable-auto-update
```

### Custom Pages
```bash
# Enable custom pages (default)
sudo ./install.sh --enable-custom-pages

# Custom directory location
sudo ./install.sh --custom-pages-dir /opt/tldr-custom

# Disable custom pages
sudo ./install.sh --disable-custom-pages
```

## Post-Installation Usage

### Basic Commands
```bash
# Update page cache
tldr --update

# View examples for a command
tldr tar
tldr git commit
tldr docker run

# Search for commands
tldr --search "compress"

# List available pages
tldr --list
```

### Language-Specific Usage
```bash
# Use Spanish examples
tldr -L es curl

# Set default language
export TLDR_LANGUAGE=es
tldr curl
```

### Custom Pages
```bash
# Create custom page
tldr-manage create-custom-page mycommand

# Edit custom page
nano /usr/local/share/tldr-custom/pages.en/mycommand.md

# View custom pages
tldr-manage list-custom-pages
```

## Management Tools

The installation creates a comprehensive management script at `/usr/local/bin/tldr-manage`:

### Cache Management
```bash
# Update cache
tldr-manage update

# Clear cache
tldr-manage clear-cache

# View statistics
tldr-manage show-stats
```

### Health Monitoring
```bash
# Check installation health
tldr-manage health-check

# View version information
tldr-manage version
```

### Custom Page Management
```bash
# Create new custom page
tldr-manage create-custom-page myapp

# Validate custom pages
tldr-manage validate-custom-pages
```

## Directory Structure

```
/opt/tldr/                          # TLDR installation directory
/var/cache/tldr/                    # Page cache directory
/usr/local/share/tldr-custom/       # Custom pages directory
├── pages.en/                       # English custom pages
├── pages.es/                       # Spanish custom pages
└── pages.fr/                       # French custom pages
/etc/tldr/                          # Configuration directory
├── config.toml                     # Tealdeer configuration
/var/log/bashmin/development/tldr/  # Log directory
├── install.log                     # Installation log
├── cache-update.log               # Cache update log
└── management.log                 # Management operations log
```

## Automation

### Cron Jobs
The installer automatically creates cron jobs for:
- **Cache Updates**: Based on specified frequency (daily/weekly/monthly)
- **Log Rotation**: Automatic cleanup of old logs

### Systemd Integration
- Service user: `tldr`
- Automatic cache updates
- Proper permissions and security

## Troubleshooting

### Common Issues

#### 1. TLDR Not Found
```bash
# Check if binary is installed
which tldr

# Check PATH
echo $PATH

# Reinstall with force
sudo ./install.sh --force
```

#### 2. Cache Issues
```bash
# Clear and rebuild cache
tldr-manage clear-cache
tldr --update

# Check cache permissions
ls -la /var/cache/tldr/
```

#### 3. Language Issues
```bash
# Check available languages
tldr --list-languages

# Update cache for specific language
TLDR_LANGUAGE=es tldr --update
```

#### 4. Custom Pages Not Working
```bash
# Check custom pages directory
ls -la /usr/local/share/tldr-custom/

# Validate custom pages
tldr-manage validate-custom-pages

# Check permissions
sudo chown -R tldr:tldr /usr/local/share/tldr-custom/
```

### Log Analysis
```bash
# View installation log
tail -f /var/log/bashmin/development/tldr/install.log

# Check management operations
tail -f /var/log/bashmin/development/tldr/management.log

# Monitor cache updates
tail -f /var/log/bashmin/development/tldr/cache-update.log
```

### Health Check
```bash
# Run comprehensive health check
tldr-manage health-check

# Check system requirements
./install.sh --dry-run --verbose
```

## Integration Examples

### Bash Profile Integration
```bash
# Add to ~/.bashrc
alias man='tldr'
alias help='tldr'

# Function for quick lookup
function t() {
    tldr "$1" 2>/dev/null || man "$1"
}
```

### Zsh Integration
```bash
# Add to ~/.zshrc
autoload -U compinit
compinit

# Custom completion
fpath+=(/usr/share/zsh/vendor-completions)
```

### Custom Page Examples

#### Example Custom Page
```markdown
# myapp

> My custom application for data processing.
> More information: <https://mycompany.com/myapp>.

- Process a single file:
  `myapp process {{input_file}}`

- Process with output file:
  `myapp process {{input_file}} --output {{output_file}}`

- Batch process directory:
  `myapp batch {{directory}} --format {{json|xml|csv}}`

- Verbose processing with logging:
  `myapp process {{input_file}} --verbose --log {{log_file}}`
```

## Advanced Configuration

### Tealdeer Configuration
Edit `/etc/tldr/config.toml`:
```toml
[display]
compact = false
use_pager = false

[style]
description.foreground = "white"
command_name.foreground = "green"
example_text.foreground = "blue"
example_code.foreground = "yellow"

[updates]
auto_update = true
auto_update_interval_hours = 168  # Weekly
```

### Environment Variables
```bash
export TLDR_LANGUAGE=es          # Default language
export TLDR_CACHE_DIR=/custom    # Custom cache directory
export TLDR_COLOR=always         # Force color output
```

## Performance Optimization

### Cache Optimization
- Use SSD storage for cache directory
- Regular cache cleanup and rebuilds
- Optimize cache update frequency

### Client Performance
- **Tealdeer**: Fastest, recommended for daily use
- **C Client**: Good for resource-constrained systems
- **Node.js**: Good balance of features and performance
- **Python**: Best for customization and extensions

## Security Considerations

- TLDR service user with minimal privileges
- Secure cache directory permissions
- Automatic security updates enabled
- Custom pages validation and sanitization

## Compliance & Auditing

- Installation logging for compliance
- Change tracking for custom pages
- Regular health checks and monitoring
- Integration with system audit logs

---

**Next Steps**: After installation, run `tldr --update` to populate the cache and try `tldr tar` to see your first examples!
