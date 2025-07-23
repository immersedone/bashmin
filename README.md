# 🛠️ BashMin

> Personal collection of useful bash scripts for system administration

A lightweight repository of practical bash scripts to simplify common system administration tasks, server management, and routine maintenance.

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/immersedone/bashmin.git
cd bashmin

# Make scripts executable
chmod +x *.sh

# Run a script
./script-name.sh
```

## 📁 Script Categories

### � Server Stack Management (`/servers/`)
- **Apache2** - Web server installation and virtual host management
- **Nginx** - Web server, proxy configuration, and vhost setup
- **PHP** - Multi-version PHP CLI/FPM installer (8.3, 8.4, 8.5)
- **FrankenPHP** - Modern PHP application server
- **MariaDB** - Database server installation and configuration
- **MongoDB** - NoSQL database setup
- **Redis** - In-memory data store
- **Elasticsearch** - Search and analytics engine
- **Varnish** - HTTP acceleration and caching

### 🔒 Security & SSL (`/security/`)
- **Let's Encrypt** - SSL certificate automation
- **Ubuntu Security** - System hardening and security configurations

### 🛠️ Software Management (`/software/`)
- **Package Installer** - Automated software installation
- **NVM** - Node.js version manager setup
- **Nodemon** - Development tool installation
- **Unattended Upgrades** - Automatic security updates

### � System Services (`/services/`)
- **phpMyAdmin** - Database administration interface

### 🏗️ Infrastructure (`/structure/`)
- **Directory Structure** - Standardized folder organization

### 🤖 AI Integration (`/ai/`)
- **AI-powered Scripts** - Intelligent automation tools

### ⚡ Aliases & Shortcuts (`/aliases/`)
- **Custom Aliases** - Command shortcuts and productivity tools
- **Self-Update** - Repository update mechanisms

### 🩹 Self-Healing (`/self-healing/`)
- **Automated Recovery** - Self-diagnosing and fixing scripts

### 🪟 WSL Support (`/wsl/`)
- **Windows Subsystem for Linux** - WSL-specific configurations

### 🔧 Helper Functions (`/_helpers/`)
- **Common Functions** - Shared utilities and functions
- **CLI Tools** - User interaction and menu systems
- **System Tools** - System detection and validation

## 💡 Usage Examples

### Install PHP (Modern Versions)
```bash
# Interactive installation
./servers/php/install.sh

# Silent installation with specific version
./servers/php/install.sh --silent --version 8.4

# Dry run to see what would be installed
./servers/php/install.sh --dry-run --verbose
```

### Set up Nginx with Virtual Host
```bash
# Install Nginx
./servers/nginx/install.sh

# Add a virtual host
./servers/nginx/add-vhost.sh example.com
```

### Install Complete LEMP Stack
```bash
# Install Nginx, PHP, and MariaDB
./servers/nginx/install.sh
./servers/php/install.sh --silent
./servers/mariadb/install.sh
```

### Software Installation
```bash
# Install common development tools
./software/install.sh

# Set up Node.js with NVM
./software/nvm/install.sh
```

## 🛡️ Features

- **Dry Run Mode** - Test scripts without making changes (`--dry-run`)
- **Verbose Output** - Detailed logging for troubleshooting (`--verbose`)
- **Silent Mode** - Automated installation without prompts (`--silent`)
- **Smart Detection** - Automatic OS version and compatibility checking
- **Package Validation** - Dynamic availability checking before installation
- **Modular Design** - Organized helper functions and reusable components
- **Modern PHP Support** - Multi-version PHP installation (8.3, 8.4, 8.5)
- **Virtual Host Management** - Automated web server configuration
- **SSL Integration** - Let's Encrypt certificate automation
- **Error Handling** - Comprehensive error checking and graceful failures

## 📋 Requirements

- **Ubuntu 20.04+** (Primary target, other Debian-based distributions may work)
- **Bash 4.0+** (Standard on modern systems)
- **Root/sudo access** for system operations
- **Internet connection** for package downloads and repository access
- **Standard Linux tools** (grep, awk, sed, find, apt)

## 🎯 Supported Systems

- Ubuntu 20.04 LTS (Focal)
- Ubuntu 22.04 LTS (Jammy)
- Ubuntu 24.04 LTS (Noble)
- Debian-based distributions (limited testing)

## 📝 Script Template

All scripts follow a consistent structure for reliability and maintainability:

```bash
#!/bin/bash
#
# Script: example-script.sh
# Description: Brief description of script functionality
# Usage: ./example-script.sh [OPTIONS]
#

set -euo pipefail

# Get script directory and source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$BASE_DIR/_helpers/common.sh"
source "$BASE_DIR/_helpers/system.sh"
source "$BASE_DIR/_helpers/cli.sh"

# Global variables
VERBOSE=false
DRY_RUN=false
SILENT=false

# Main function
main() {
    # Script logic here
    show_script_header "Script Name"
    # Implementation...
}

# Run main function
main "$@"
```
