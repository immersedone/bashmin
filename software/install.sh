#!/bin/bash
#
# Script: software/install.sh
# Description: Install base software packages for general use
# Usage: ./software/install.sh [OPTIONS]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Base packages for all systems
CORE_PACKAGES=(
	"curl"
	"wget"
	"git"
	"vim"
	"nano"
	"htop"
	"tree"
	"unzip"
	"zip"
	"tar"
	"gzip"
	"rsync"
	"screen"
	"tmux"
	"jq"
	"bc"
	"net-tools"
	"dnsutils"
	"telnet"
	"ncdu"
	"lsof"
	"strace"
	"tcpdump"
	"iotop"
	"iftop"
	"nmap"
	"openssl"
	"ca-certificates"
	"gnupg"
	"software-properties-common"
	"apt-transport-https"
	"lsb-release"
)

# Development packages
DEVELOPMENT_PACKAGES=(
	"build-essential"
	"make"
	"cmake"
	"autoconf"
	"automake"
	"libtool"
	"pkg-config"
	"git-flow"
	"git-lfs"
	"sqlite3"
	"libsqlite3-dev"
	"python3"
	"python3-pip"
	"python3-venv"
	"python3-dev"
	"nodejs"
	"npm"
)

# System administration packages
SYSADMIN_PACKAGES=(
	"fail2ban"
	"ufw"
	"logrotate"
	"cron"
	"rsyslog"
	"systemd"
	"sudo"
	"coreutils"
	"findutils"
	"grep"
	"sed"
	"awk"
	"procps"
	"psmisc"
	"util-linux"
	"mount"
	"fdisk"
	"parted"
	"lvm2"
	"mdadm"
	"smartmontools"
	"hdparm"
)

# Network and security packages
NETWORK_PACKAGES=(
	"openssh-server"
	"openssh-client"
	"ufw"
	"iptables"
	"netfilter-persistent"
	"fail2ban"
	"rkhunter"
	"chkrootkit"
	"clamav"
	"clamav-daemon"
	"apparmor"
	"apparmor-utils"
	"auditd"
)

# Monitoring and logging packages
MONITORING_PACKAGES=(
	"rsyslog"
	"logwatch"
	"logrotate"
	"monit"
	"collectd"
	"prometheus-node-exporter"
	"nagios-plugins-basic"
)

# Web server essentials
WEB_PACKAGES=(
	"nginx"
	"apache2"
	"apache2-utils"
	"php-fpm"
	"php-cli"
	"php-mysql"
	"php-curl"
	"php-gd"
	"php-mbstring"
	"php-xml"
	"php-zip"
	"mysql-client"
	"redis-tools"
	"memcached"
)

# Optional packages for enhanced functionality
OPTIONAL_PACKAGES=(
	"zsh"
	"fish"
	"bash-completion"
	"command-not-found"
	"update-notifier-common"
	"landscape-common"
	"snapd"
	"flatpak"
	"docker.io"
	"docker-compose"
	"vagrant"
	"virtualbox"
	"wireshark"
	"ngrep"
	"socat"
	"netcat"
	"mtr"
	"traceroute"
	"whois"
	"dig"
	"host"
	"nslookup"
)

# Configuration variables
INSTALL_PROFILE="core"
CUSTOM_PACKAGES=()
SKIP_PACKAGES=()
UPDATE_SYSTEM=true
INSTALL_RECOMMENDS=true
VERBOSE=false
DRY_RUN=false
FORCE=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            INSTALL_PROFILE="$2"
            shift 2
            ;;
        --add-package)
            CUSTOM_PACKAGES+=("$2")
            shift 2
            ;;
        --skip-package)
            SKIP_PACKAGES+=("$2")
            shift 2
            ;;
        --no-update)
            UPDATE_SYSTEM=false
            shift
            ;;
        --no-recommends)
            INSTALL_RECOMMENDS=false
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Install base software packages for general use.

OPTIONS:
    --profile PROFILE       Installation profile (default: $INSTALL_PROFILE)
    --add-package PKG       Add custom package to installation
    --skip-package PKG      Skip specific package from installation
    --no-update             Skip system update before installation
    --no-recommends         Don't install recommended packages
    --force                 Force installation even if packages exist
    --quiet                 Suppress non-essential output
    --verbose               Enable verbose output
    --dry-run               Show what would be installed without executing
    -h, --help              Show this help message

PROFILES:
    core                    Essential packages for basic server operation
    development             Core + development tools and languages
    sysadmin                Core + system administration tools
    security                Core + security and monitoring tools
    web                     Core + web server and related packages
    full                    All available packages
    minimal                 Only the most essential packages
    custom                  Only packages specified with --add-package

EXAMPLES:
    $0                                      # Install core packages
    $0 --profile development                # Install development profile
    $0 --profile web --add-package docker.io   # Web profile + Docker
    $0 --profile custom --add-package git --add-package vim  # Custom selection
    $0 --skip-package nodejs --profile development  # Skip specific packages
    $0 --dry-run --verbose --profile full   # Preview full installation

PACKAGE CATEGORIES:
    Core:        Essential system utilities and tools
    Development: Programming languages, build tools, version control
    SysAdmin:    System administration and maintenance tools
    Security:    Security, monitoring, and audit tools
    Web:         Web servers, databases, and related tools
    Network:     Network utilities and security tools
    Monitoring:  System monitoring and logging tools
    Optional:    Additional useful packages

NOTES:
    - Requires sudo privileges
    - Updates package cache before installation (unless --no-update)
    - Installs recommended packages by default
    - Some packages may require additional configuration
    - Use --dry-run to preview installation without changes

EOF
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$QUIET" == false ]]; then
        print_info "Checking prerequisites..."
    fi
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. This is acceptable for system package installation."
    elif ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        exit 1
    fi
    
    # Check Ubuntu/Debian system
    if ! command -v apt &> /dev/null; then
        print_error "This script requires apt package manager (Ubuntu/Debian-based systems)"
        exit 1
    fi
    
    # Check internet connectivity
    if ! curl -s --connect-timeout 5 http://archive.ubuntu.com > /dev/null; then
        print_warning "Internet connectivity may be limited"
        print_info "Some packages may fail to install"
    fi
    
    if [[ "$QUIET" == false ]]; then
        print_success "Prerequisites check completed"
    fi
}

# Function to get packages for profile
get_packages_for_profile() {
    local profile="$1"
    local packages=()
    
    case "$profile" in
        minimal)
            packages+=(
                "curl" "wget" "git" "vim" "htop" "tree" "unzip" "zip" 
                "rsync" "jq" "net-tools" "openssl" "ca-certificates"
            )
            ;;
        core)
            packages+=("${CORE_PACKAGES[@]}")
            ;;
        development)
            packages+=("${CORE_PACKAGES[@]}")
            packages+=("${DEVELOPMENT_PACKAGES[@]}")
            ;;
        sysadmin)
            packages+=("${CORE_PACKAGES[@]}")
            packages+=("${SYSADMIN_PACKAGES[@]}")
            packages+=("${MONITORING_PACKAGES[@]}")
            ;;
        security)
            packages+=("${CORE_PACKAGES[@]}")
            packages+=("${NETWORK_PACKAGES[@]}")
            packages+=("${MONITORING_PACKAGES[@]}")
            ;;
        web)
            packages+=("${CORE_PACKAGES[@]}")
            packages+=("${DEVELOPMENT_PACKAGES[@]}")
            packages+=("${WEB_PACKAGES[@]}")
            packages+=("${NETWORK_PACKAGES[@]}")
            ;;
        full)
            packages+=("${CORE_PACKAGES[@]}")
            packages+=("${DEVELOPMENT_PACKAGES[@]}")
            packages+=("${SYSADMIN_PACKAGES[@]}")
            packages+=("${NETWORK_PACKAGES[@]}")
            packages+=("${MONITORING_PACKAGES[@]}")
            packages+=("${WEB_PACKAGES[@]}")
            packages+=("${OPTIONAL_PACKAGES[@]}")
            ;;
        custom)
            # Only custom packages
            ;;
        *)
            print_error "Unknown profile: $profile"
            print_info "Available profiles: minimal, core, development, sysadmin, security, web, full, custom"
            exit 1
            ;;
    esac
    
    # Add custom packages
    packages+=("${CUSTOM_PACKAGES[@]}")
    
    # Remove skipped packages
    for skip in "${SKIP_PACKAGES[@]}"; do
        packages=("${packages[@]/$skip}")
    done
    
    # Remove empty elements and duplicates
    local unique_packages=()
    for pkg in "${packages[@]}"; do
        if [[ -n "$pkg" ]] && ! [[ " ${unique_packages[*]} " =~ " $pkg " ]]; then
            unique_packages+=("$pkg")
        fi
    done
    
    printf '%s\n' "${unique_packages[@]}"
}

# Function to check if package is available
package_available() {
    local package="$1"
    apt-cache show "$package" &>/dev/null
}

# Function to check if package is installed
package_installed() {
    local package="$1"
    dpkg -l "$package" 2>/dev/null | grep -q "^ii"
}

# Function to update system packages
update_system() {
    if [[ "$UPDATE_SYSTEM" == false ]]; then
        return 0
    fi
    
    if [[ "$QUIET" == false ]]; then
        print_info "Updating system package cache..."
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would update package cache"
        return 0
    fi
    
    execute_command "sudo apt update" "Updating package cache"
    
    if [[ "$QUIET" == false ]]; then
        print_success "Package cache updated"
    fi
}

# Function to install packages
install_packages() {
    local packages=()
    readarray -t packages < <(get_packages_for_profile "$INSTALL_PROFILE")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        print_warning "No packages to install"
        return 0
    fi
    
    if [[ "$QUIET" == false ]]; then
        print_info "Installing ${#packages[@]} packages..."
        if [[ "$VERBOSE" == true ]]; then
            print_info "Package list: ${packages[*]}"
        fi
    fi
    
    # Filter packages: check availability and installation status
    local to_install=()
    local already_installed=()
    local unavailable=()
    
    for package in "${packages[@]}"; do
        if [[ -z "$package" ]]; then
            continue
        fi
        
        if ! package_available "$package"; then
            unavailable+=("$package")
            continue
        fi
        
        if package_installed "$package"; then
            already_installed+=("$package")
            if [[ "$FORCE" == false ]]; then
                continue
            fi
        fi
        
        to_install+=("$package")
    done
    
    # Report status
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        if [[ ${#already_installed[@]} -gt 0 ]]; then
            print_info "Already installed (${#already_installed[@]}): ${already_installed[*]}"
        fi
        
        if [[ ${#unavailable[@]} -gt 0 ]]; then
            print_warning "Unavailable packages (${#unavailable[@]}): ${unavailable[*]}"
        fi
    fi
    
    if [[ ${#to_install[@]} -eq 0 ]]; then
        if [[ "$QUIET" == false ]]; then
            print_success "All packages are already installed"
        fi
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install ${#to_install[@]} packages:"
        printf '  %s\n' "${to_install[@]}"
        return 0
    fi
    
    # Build apt command
    local apt_cmd="sudo apt install -y"
    if [[ "$INSTALL_RECOMMENDS" == false ]]; then
        apt_cmd="$apt_cmd --no-install-recommends"
    fi
    
    # Install packages in batches to handle potential failures
    local batch_size=20
    local installed_count=0
    local failed_packages=()
    
    for ((i=0; i<${#to_install[@]}; i+=batch_size)); do
        local batch=("${to_install[@]:i:batch_size}")
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Installing batch: ${batch[*]}"
        fi
        
        if $apt_cmd "${batch[@]}" 2>/dev/null; then
            installed_count=$((installed_count + ${#batch[@]}))
        else
            # Try installing packages individually to identify failures
            for pkg in "${batch[@]}"; do
                if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                    print_info "Installing: $pkg"
                fi
                
                if $apt_cmd "$pkg" 2>/dev/null; then
                    installed_count=$((installed_count + 1))
                else
                    failed_packages+=("$pkg")
                    if [[ "$QUIET" == false ]]; then
                        print_warning "Failed to install: $pkg"
                    fi
                fi
            done
        fi
    done
    
    # Report results
    if [[ "$QUIET" == false ]]; then
        print_success "Successfully installed $installed_count packages"
        
        if [[ ${#failed_packages[@]} -gt 0 ]]; then
            print_warning "Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}"
        fi
        
        if [[ ${#unavailable[@]} -gt 0 ]]; then
            print_info "Unavailable packages were skipped: ${unavailable[*]}"
        fi
    fi
}

# Function to cleanup after installation
cleanup_installation() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would cleanup package cache"
        return 0
    fi
    
    if [[ "$QUIET" == false ]]; then
        print_info "Cleaning up package cache..."
    fi
    
    execute_command "sudo apt autoremove -y" "Removing unnecessary packages" || true
    execute_command "sudo apt autoclean" "Cleaning package cache" || true
    
    if [[ "$QUIET" == false ]]; then
        print_success "Cleanup completed"
    fi
}

# Function to show installation summary
show_installation_summary() {
    if [[ "$QUIET" == true ]]; then
        return 0
    fi
    
    local packages=()
    readarray -t packages < <(get_packages_for_profile "$INSTALL_PROFILE")
    
    echo
    print_info "=== Software Installation Summary ==="
    echo
    
    cat << EOF
Installation Profile: $INSTALL_PROFILE
Total Packages: ${#packages[@]}
System Update: $(if [[ "$UPDATE_SYSTEM" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
Install Recommends: $(if [[ "$INSTALL_RECOMMENDS" == true ]]; then echo "Yes"; else echo "No"; fi)
Custom Packages: ${#CUSTOM_PACKAGES[@]} $(if [[ ${#CUSTOM_PACKAGES[@]} -gt 0 ]]; then echo "(${CUSTOM_PACKAGES[*]})"; fi)
Skipped Packages: ${#SKIP_PACKAGES[@]} $(if [[ ${#SKIP_PACKAGES[@]} -gt 0 ]]; then echo "(${SKIP_PACKAGES[*]})"; fi)

Package Categories Included:
$(case "$INSTALL_PROFILE" in
    minimal) echo "  ✓ Essential utilities only" ;;
    core) echo "  ✓ Core system packages" ;;
    development) echo "  ✓ Core system packages"; echo "  ✓ Development tools and languages" ;;
    sysadmin) echo "  ✓ Core system packages"; echo "  ✓ System administration tools"; echo "  ✓ Monitoring packages" ;;
    security) echo "  ✓ Core system packages"; echo "  ✓ Security and network tools"; echo "  ✓ Monitoring packages" ;;
    web) echo "  ✓ Core system packages"; echo "  ✓ Development tools"; echo "  ✓ Web server packages"; echo "  ✓ Network tools" ;;
    full) echo "  ✓ All available package categories" ;;
    custom) echo "  ✓ Custom packages only" ;;
esac)

Key Software Included:
  • System utilities: curl, wget, git, vim, htop, tree, jq
  • Network tools: net-tools, dnsutils, nmap, telnet
  • Development: build-essential, python3, nodejs (if profile includes)
  • Security: openssl, fail2ban, ufw (if profile includes)
  • Monitoring: rsyslog, logrotate (if profile includes)

Post-Installation Notes:
  • Some packages may require additional configuration
  • Services are not automatically started - use systemctl as needed
  • Development tools are ready for use
  • Security tools may need policy configuration

Useful Commands After Installation:
  sudo systemctl status <service>     # Check service status
  sudo ufw enable                     # Enable firewall (if installed)
  git config --global user.name      # Configure git (if installed)
  
EOF
    
    print_success "Software installation completed successfully! 🚀"
}

# Main installation function
main() {
    if [[ "$QUIET" == false ]]; then
        show_script_header "Software Package Installation Script"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show installation plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        local packages=()
        readarray -t packages < <(get_packages_for_profile "$INSTALL_PROFILE")
        
        print_info "Installation plan:"
        print_info "  Profile: $INSTALL_PROFILE"
        print_info "  Packages: ${#packages[@]}"
        print_info "  Update system: $UPDATE_SYSTEM"
        print_info "  Install recommends: $INSTALL_RECOMMENDS"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with package installation?" "Y"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Installation steps
    update_system
    install_packages
    cleanup_installation
    
    # Show summary
    show_installation_summary
}

# Run main function
main "$@"