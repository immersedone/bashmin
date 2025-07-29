#!/bin/bash
#
# Script: wsl/configure.sh
# Description: Configure WSL2 environment with common optimizations and fixes
# Usage: ./configure.sh [OPTIONS]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly WSL_CONF="/etc/wsl.conf"
readonly WSLCONFIG_PATH="/mnt/c/Users/$USER/.wslconfig"
readonly BASHRC_PATH="$HOME/.bashrc"
readonly PROFILE_PATH="$HOME/.profile"
readonly HOSTS_FILE="/etc/hosts"
readonly RESOLV_CONF="/etc/resolv.conf"
readonly SYSTEMD_RESOLVED_CONF="/etc/systemd/resolved.conf"

# Configuration variables
ENABLE_SYSTEMD=true
ENABLE_INTEROP=true
APPEND_NT_PATH=true
GENERATE_HOSTS=false
GENERATE_RESOLV_CONF=true
ENABLE_GPU_SUPPORT=false
ENABLE_DOCKER_INTEGRATION=true
CONFIGURE_MEMORY_LIMIT=false
MEMORY_LIMIT="8GB"
CONFIGURE_SWAP=false
SWAP_SIZE="2GB"
CONFIGURE_PROCESSORS=false
PROCESSOR_COUNT="4"
ENABLE_NESTED_VIRTUALIZATION=false
CONFIGURE_NETWORKING=true
NETWORK_MODE="mirrored"
ENABLE_BRIDGE_MODE=false
BRIDGE_INTERFACE=""
CONFIGURE_DNS=true
DNS_SERVERS=("8.8.8.8" "8.8.4.4" "1.1.1.1")
ENABLE_PORT_FORWARDING=false
FORWARDED_PORTS=()
CONFIGURE_MOUNT_OPTIONS=true
MOUNT_DRIVES_DRV_FS=true
MOUNT_OPTIONS="metadata,uid=1000,gid=1000,umask=022,fmask=011"
ENABLE_WINDOWS_PATH_FILTERING=true
WINDOWS_PATH_ELEMENTS=("/mnt/c/Windows/System32" "/mnt/c/Windows" "/mnt/c/Program Files")
CONFIGURE_LOCALE=true
LOCALE_LANG="en_US.UTF-8"
CONFIGURE_TIMEZONE=true
TIMEZONE="UTC"
ENABLE_BASH_COMPLETION=true
ENABLE_WSL_ALIASES=true
CONFIGURE_GIT_CREDENTIAL_MANAGER=true
ENABLE_VSCODE_INTEGRATION=true
FORCE_CONFIGURE=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --disable-systemd)
            ENABLE_SYSTEMD=false
            shift
            ;;
        --disable-interop)
            ENABLE_INTEROP=false
            shift
            ;;
        --no-nt-path)
            APPEND_NT_PATH=false
            shift
            ;;
        --enable-hosts-generation)
            GENERATE_HOSTS=true
            shift
            ;;
        --disable-resolv-generation)
            GENERATE_RESOLV_CONF=false
            shift
            ;;
        --enable-gpu)
            ENABLE_GPU_SUPPORT=true
            shift
            ;;
        --disable-docker)
            ENABLE_DOCKER_INTEGRATION=false
            shift
            ;;
        --memory-limit)
            CONFIGURE_MEMORY_LIMIT=true
            MEMORY_LIMIT="$2"
            shift 2
            ;;
        --swap-size)
            CONFIGURE_SWAP=true
            SWAP_SIZE="$2"
            shift 2
            ;;
        --processors)
            CONFIGURE_PROCESSORS=true
            PROCESSOR_COUNT="$2"
            shift 2
            ;;
        --enable-nested-virtualization)
            ENABLE_NESTED_VIRTUALIZATION=true
            shift
            ;;
        --network-mode)
            NETWORK_MODE="$2"
            shift 2
            ;;
        --enable-bridge)
            ENABLE_BRIDGE_MODE=true
            BRIDGE_INTERFACE="$2"
            shift 2
            ;;
        --dns-servers)
            IFS=',' read -ra DNS_SERVERS <<< "$2"
            shift 2
            ;;
        --disable-dns)
            CONFIGURE_DNS=false
            shift
            ;;
        --port-forward)
            ENABLE_PORT_FORWARDING=true
            IFS=',' read -ra FORWARDED_PORTS <<< "$2"
            shift 2
            ;;
        --mount-options)
            MOUNT_OPTIONS="$2"
            shift 2
            ;;
        --disable-mount-config)
            CONFIGURE_MOUNT_OPTIONS=false
            shift
            ;;
        --disable-drvfs)
            MOUNT_DRIVES_DRV_FS=false
            shift
            ;;
        --windows-path-filter)
            IFS=',' read -ra WINDOWS_PATH_ELEMENTS <<< "$2"
            shift 2
            ;;
        --disable-path-filtering)
            ENABLE_WINDOWS_PATH_FILTERING=false
            shift
            ;;
        --locale)
            LOCALE_LANG="$2"
            shift 2
            ;;
        --timezone)
            TIMEZONE="$2"
            shift 2
            ;;
        --disable-bash-completion)
            ENABLE_BASH_COMPLETION=false
            shift
            ;;
        --disable-wsl-aliases)
            ENABLE_WSL_ALIASES=false
            shift
            ;;
        --disable-git-credential-manager)
            CONFIGURE_GIT_CREDENTIAL_MANAGER=false
            shift
            ;;
        --disable-vscode)
            ENABLE_VSCODE_INTEGRATION=false
            shift
            ;;
        --force)
            FORCE_CONFIGURE=true
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

Configure WSL2 environment with common optimizations and development-friendly settings.

SYSTEM OPTIONS:
    --disable-systemd           Disable systemd support (default: enabled)
    --disable-interop           Disable Windows interoperability (default: enabled)
    --no-nt-path                Don't append Windows PATH to Linux PATH (default: append)
    --enable-hosts-generation   Enable automatic /etc/hosts generation (default: disabled)
    --disable-resolv-generation Disable automatic /etc/resolv.conf generation (default: enabled)

PERFORMANCE OPTIONS:
    --memory-limit SIZE         Set memory limit (e.g., 8GB, 4GB) (default: unlimited)
    --swap-size SIZE            Set swap file size (e.g., 2GB, 1GB) (default: unlimited)
    --processors COUNT          Limit processor count (default: all available)
    --enable-gpu                Enable GPU support for CUDA/AI workloads (default: disabled)
    --enable-nested-virtualization Enable nested virtualization (default: disabled)

NETWORKING OPTIONS:
    --network-mode MODE         Network mode: mirrored, nat, bridged (default: mirrored)
    --enable-bridge INTERFACE   Enable bridge mode with specified interface
    --dns-servers IPS           Comma-separated DNS servers (default: 8.8.8.8,8.8.4.4,1.1.1.1)
    --disable-dns               Disable DNS configuration
    --port-forward PORTS        Comma-separated port forwards (e.g., 3000,8080,9000)

FILESYSTEM OPTIONS:
    --mount-options OPTIONS     Custom mount options for drives (default: metadata,uid=1000,gid=1000,umask=022,fmask=011)
    --disable-mount-config      Don't configure drive mounting
    --disable-drvfs             Disable DrvFS automounting
    --windows-path-filter PATHS Comma-separated Windows PATH elements to include
    --disable-path-filtering    Don't filter Windows PATH elements

LOCALIZATION OPTIONS:
    --locale LOCALE             Set system locale (default: en_US.UTF-8)
    --timezone TZ               Set timezone (default: UTC)

DEVELOPMENT OPTIONS:
    --disable-docker            Disable Docker Desktop integration
    --disable-bash-completion   Disable enhanced bash completion
    --disable-wsl-aliases       Don't add WSL-specific aliases
    --disable-git-credential-manager Don't configure Git Credential Manager
    --disable-vscode            Don't configure VS Code integration

GENERAL OPTIONS:
    --force                     Force reconfiguration even if already configured
    --quiet                     Suppress non-essential output
    --verbose                   Enable verbose output
    --dry-run                   Show what would be configured without executing
    -h, --help                  Show this help message

CONFIGURATION MODES:
    Default Mode:               Optimized for development with systemd, Docker, and VS Code
    Performance Mode:           Add --memory-limit, --processors, --swap-size for resource control
    Minimal Mode:               Use --disable-* flags to create lightweight environment
    Network Mode:               Use --network-mode and --port-forward for advanced networking

EXAMPLES:
    # Basic WSL2 optimization
    $0

    # Development workstation with resource limits
    $0 --memory-limit 8GB --processors 6 --swap-size 2GB

    # Minimal environment for CI/testing
    $0 --disable-systemd --disable-interop --disable-docker --disable-vscode

    # High-performance AI/ML workstation
    $0 --enable-gpu --memory-limit 16GB --enable-nested-virtualization

    # Custom networking for web development
    $0 --network-mode mirrored --port-forward 3000,8080,9000,5432

    # Corporate environment with custom DNS
    $0 --dns-servers 192.168.1.1,8.8.8.8 --timezone America/New_York

NOTES:
    - Some changes require WSL restart: wsl --shutdown
    - GPU support requires WSL 2.0+ and compatible drivers
    - Nested virtualization requires Hyper-V features
    - Network mirroring requires Windows 11 22H2 or later
    - Changes to .wslconfig affect all WSL distributions

SECURITY NOTES:
    - Windows interop enabled by default for development convenience
    - PATH filtering reduces Windows executable exposure
    - DNS configuration improves privacy and performance
    - Mount options provide proper file permissions

EOF
}

# Function to detect WSL environment
detect_wsl_environment() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Detecting WSL environment..."
    fi
    
    # Check if we're running in WSL
    if [[ ! -f /proc/version ]] || ! grep -qi "microsoft\|wsl" /proc/version; then
        print_error "This script must be run inside WSL2"
        exit 1
    fi
    
    # Detect WSL version
    if grep -qi "wsl2\|microsoft" /proc/version; then
        WSL_VERSION="2"
    else
        WSL_VERSION="1"
        print_warning "WSL1 detected. Some features require WSL2."
    fi
    
    # Get WSL distribution name
    WSL_DISTRO_NAME=$(cat /etc/hostname 2>/dev/null || echo "unknown")
    
    # Detect Windows username
    if [[ -d "/mnt/c/Users" ]]; then
        WINDOWS_USER=$(ls /mnt/c/Users | grep -v "Public\|Default\|All Users" | head -1)
    else
        WINDOWS_USER="$USER"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "WSL Version: $WSL_VERSION"
        print_info "Distribution: $WSL_DISTRO_NAME"
        print_info "Windows User: $WINDOWS_USER"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Checking prerequisites..."
    fi
    
    # Check if we have sudo access
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        exit 1
    fi
    
    # Validate memory limit format
    if [[ "$CONFIGURE_MEMORY_LIMIT" == true ]]; then
        if [[ ! "$MEMORY_LIMIT" =~ ^[0-9]+[GMgm][Bb]?$ ]]; then
            print_error "Invalid memory limit format: $MEMORY_LIMIT (use format like 8GB or 4GB)"
            exit 1
        fi
    fi
    
    # Validate swap size format
    if [[ "$CONFIGURE_SWAP" == true ]]; then
        if [[ ! "$SWAP_SIZE" =~ ^[0-9]+[GMgm][Bb]?$ ]]; then
            print_error "Invalid swap size format: $SWAP_SIZE (use format like 2GB or 1GB)"
            exit 1
        fi
    fi
    
    # Validate processor count
    if [[ "$CONFIGURE_PROCESSORS" == true ]]; then
        if [[ ! "$PROCESSOR_COUNT" =~ ^[0-9]+$ ]] || [[ "$PROCESSOR_COUNT" -lt 1 ]]; then
            print_error "Invalid processor count: $PROCESSOR_COUNT"
            exit 1
        fi
    fi
    
    # Validate network mode
    case "$NETWORK_MODE" in
        mirrored|nat|bridged) ;;
        *)
            print_error "Invalid network mode: $NETWORK_MODE (use: mirrored, nat, or bridged)"
            exit 1
            ;;
    esac
    
    # Validate timezone
    if [[ "$CONFIGURE_TIMEZONE" == true && ! -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
        print_error "Invalid timezone: $TIMEZONE"
        print_info "List available timezones: timedatectl list-timezones"
        exit 1
    fi
}

# Function to configure wsl.conf
configure_wsl_conf() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure /etc/wsl.conf"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring /etc/wsl.conf..."
    fi
    
    # Backup existing configuration
    if [[ -f "$WSL_CONF" ]]; then
        sudo cp "$WSL_CONF" "$WSL_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create new wsl.conf
    cat << EOF | sudo tee "$WSL_CONF" >/dev/null
# WSL Configuration
# Generated by bashmin on $(date)

[boot]
systemd=$(bool_to_true_false $ENABLE_SYSTEMD)

[interop]
enabled=$(bool_to_true_false $ENABLE_INTEROP)
appendWindowsPath=$(bool_to_true_false $APPEND_NT_PATH)

[network]
generateHosts=$(bool_to_true_false $GENERATE_HOSTS)
generateResolvConf=$(bool_to_true_false $GENERATE_RESOLV_CONF)

[automount]
enabled=true
root=/mnt/
options="$MOUNT_OPTIONS"
mountFsTab=false

[user]
default=$USER
EOF
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "/etc/wsl.conf configured"
    fi
}

# Function to configure .wslconfig (Windows side)
configure_wslconfig() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure .wslconfig in Windows user profile"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring .wslconfig..."
    fi
    
    # Ensure Windows user directory exists
    local windows_config_dir="/mnt/c/Users/$WINDOWS_USER"
    if [[ ! -d "$windows_config_dir" ]]; then
        print_warning "Windows user directory not found: $windows_config_dir"
        return 0
    fi
    
    local wslconfig_path="$windows_config_dir/.wslconfig"
    
    # Backup existing configuration
    if [[ -f "$wslconfig_path" ]]; then
        cp "$wslconfig_path" "$wslconfig_path.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Create .wslconfig
    cat << EOF > "$wslconfig_path"
# WSL Global Configuration
# Generated by bashmin on $(date)

[wsl2]
EOF
    
    # Add memory configuration
    if [[ "$CONFIGURE_MEMORY_LIMIT" == true ]]; then
        echo "memory=$MEMORY_LIMIT" >> "$wslconfig_path"
    fi
    
    # Add processor configuration
    if [[ "$CONFIGURE_PROCESSORS" == true ]]; then
        echo "processors=$PROCESSOR_COUNT" >> "$wslconfig_path"
    fi
    
    # Add swap configuration
    if [[ "$CONFIGURE_SWAP" == true ]]; then
        echo "swap=$SWAP_SIZE" >> "$wslconfig_path"
    fi
    
    # Add GPU support
    if [[ "$ENABLE_GPU_SUPPORT" == true ]]; then
        echo "wslEnableFirewall=false" >> "$wslconfig_path"
        echo "kernelCommandLine=cgroup_no_v1=all systemd.unified_cgroup_hierarchy=1" >> "$wslconfig_path"
    fi
    
    # Add networking configuration
    if [[ "$CONFIGURE_NETWORKING" == true ]]; then
        echo "networkingMode=$NETWORK_MODE" >> "$wslconfig_path"
        
        if [[ "$ENABLE_BRIDGE_MODE" == true && -n "$BRIDGE_INTERFACE" ]]; then
            echo "vmSwitch=$BRIDGE_INTERFACE" >> "$wslconfig_path"
        fi
        
        if [[ "$ENABLE_PORT_FORWARDING" == true && ${#FORWARDED_PORTS[@]} -gt 0 ]]; then
            echo "# Port forwarding configured via netsh (see configure_port_forwarding function)" >> "$wslconfig_path"
        fi
    fi
    
    # Add nested virtualization
    if [[ "$ENABLE_NESTED_VIRTUALIZATION" == true ]]; then
        echo "nestedVirtualization=true" >> "$wslconfig_path"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success ".wslconfig configured at: $wslconfig_path"
    fi
}

# Function to configure DNS
configure_dns() {
    if [[ "$CONFIGURE_DNS" == false || "$DRY_RUN" == true ]]; then
        if [[ "$DRY_RUN" == true && "$CONFIGURE_DNS" == true ]]; then
            echo "[DRY-RUN] Would configure DNS settings"
        fi
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring DNS settings..."
    fi
    
    # Configure systemd-resolved if available
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved; then
        # Backup existing configuration
        if [[ -f "$SYSTEMD_RESOLVED_CONF" ]]; then
            sudo cp "$SYSTEMD_RESOLVED_CONF" "$SYSTEMD_RESOLVED_CONF.backup.$(date +%Y%m%d_%H%M%S)"
        fi
        
        # Configure systemd-resolved
        cat << EOF | sudo tee "$SYSTEMD_RESOLVED_CONF" >/dev/null
# systemd-resolved configuration
# Generated by bashmin on $(date)

[Resolve]
DNS=${DNS_SERVERS[*]}
FallbackDNS=8.8.8.8 1.1.1.1
Domains=~.
DNSSEC=yes
DNSOverTLS=opportunistic
Cache=yes
DNSStubListener=yes
EOF
        
        # Restart systemd-resolved
        sudo systemctl restart systemd-resolved
        
    else
        # Configure resolv.conf directly
        if [[ -f "$RESOLV_CONF" ]]; then
            sudo cp "$RESOLV_CONF" "$RESOLV_CONF.backup.$(date +%Y%m%d_%H%M%S)"
        fi
        
        cat << EOF | sudo tee "$RESOLV_CONF" >/dev/null
# DNS configuration
# Generated by bashmin on $(date)

EOF
        
        for dns in "${DNS_SERVERS[@]}"; do
            echo "nameserver $dns" | sudo tee -a "$RESOLV_CONF" >/dev/null
        done
        
        # Make it immutable to prevent overwriting
        sudo chattr +i "$RESOLV_CONF" 2>/dev/null || true
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "DNS configuration completed"
    fi
}

# Function to configure locale and timezone
configure_locale_timezone() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure locale and timezone"
        return 0
    fi
    
    if [[ "$CONFIGURE_LOCALE" == true ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Configuring locale: $LOCALE_LANG"
        fi
        
        # Generate locale
        sudo locale-gen "$LOCALE_LANG" >/dev/null 2>&1 || true
        
        # Set system locale
        echo "LANG=$LOCALE_LANG" | sudo tee /etc/default/locale >/dev/null
        export LANG="$LOCALE_LANG"
    fi
    
    if [[ "$CONFIGURE_TIMEZONE" == true ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Configuring timezone: $TIMEZONE"
        fi
        
        # Set timezone
        sudo timedatectl set-timezone "$TIMEZONE" 2>/dev/null || {
            sudo ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
        }
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Locale and timezone configured"
    fi
}

# Function to configure development tools
configure_development_tools() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure development tools integration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring development tools..."
    fi
    
    # Configure Git Credential Manager
    if [[ "$CONFIGURE_GIT_CREDENTIAL_MANAGER" == true ]]; then
        configure_git_credential_manager
    fi
    
    # Configure VS Code integration
    if [[ "$ENABLE_VSCODE_INTEGRATION" == true ]]; then
        configure_vscode_integration
    fi
    
    # Configure Docker integration
    if [[ "$ENABLE_DOCKER_INTEGRATION" == true ]]; then
        configure_docker_integration
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Development tools configured"
    fi
}

# Function to configure Git Credential Manager
configure_git_credential_manager() {
    if command -v git >/dev/null 2>&1; then
        # Configure Git to use Windows Credential Manager
        git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager-core.exe" 2>/dev/null || true
        
        # Alternative path for Git Credential Manager
        if [[ ! -f "/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager-core.exe" ]]; then
            git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/libexec/git-core/git-credential-manager-core.exe" 2>/dev/null || true
        fi
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Git Credential Manager configured"
        fi
    fi
}

# Function to configure VS Code integration
configure_vscode_integration() {
    # Add VS Code to PATH if not already there
    if ! command -v code >/dev/null 2>&1; then
        local vscode_path="/mnt/c/Users/$WINDOWS_USER/AppData/Local/Programs/Microsoft VS Code/bin"
        if [[ -d "$vscode_path" ]]; then
            echo "export PATH=\"\$PATH:$vscode_path\"" >> "$BASHRC_PATH"
        fi
    fi
    
    # Create VS Code alias
    if [[ "$ENABLE_WSL_ALIASES" == true ]]; then
        echo "alias code='/mnt/c/Users/$WINDOWS_USER/AppData/Local/Programs/Microsoft\ VS\ Code/Code.exe'" >> "$BASHRC_PATH"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "VS Code integration configured"
    fi
}

# Function to configure Docker integration
configure_docker_integration() {
    # Add Docker Desktop integration
    local docker_desktop_path="/mnt/c/Program Files/Docker/Docker/resources/bin"
    if [[ -d "$docker_desktop_path" ]]; then
        echo "export PATH=\"\$PATH:$docker_desktop_path\"" >> "$BASHRC_PATH"
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Docker Desktop integration configured"
        fi
    fi
}

# Function to configure shell enhancements
configure_shell_enhancements() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure shell enhancements"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring shell enhancements..."
    fi
    
    # Backup existing bashrc
    if [[ -f "$BASHRC_PATH" ]]; then
        cp "$BASHRC_PATH" "$BASHRC_PATH.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Add WSL-specific configurations to bashrc
    cat << 'EOF' >> "$BASHRC_PATH"

# WSL-specific configurations added by bashmin
# Generated on $(date)

# Enhanced bash completion
if [[ "$ENABLE_BASH_COMPLETION" == true ]]; then
    if ! shopt -oq posix; then
        if [ -f /usr/share/bash-completion/bash_completion ]; then
            . /usr/share/bash-completion/bash_completion
        elif [ -f /etc/bash_completion ]; then
            . /etc/bash_completion
        fi
    fi
fi

# WSL aliases
if [[ "$ENABLE_WSL_ALIASES" == true ]]; then
    # Windows drive shortcuts
    alias win_c="cd /mnt/c/"
    alias win_d="cd /mnt/d/"
    alias win_downloads="cd /mnt/c/Users/$WINDOWS_USER/Downloads/"
    alias win_desktop="cd /mnt/c/Users/$WINDOWS_USER/Desktop/"
    alias win_documents="cd /mnt/c/Users/$WINDOWS_USER/Documents/"
    
    # Windows utilities
    alias explorer="explorer.exe"
    alias notepad="notepad.exe"
    alias powershell="powershell.exe"
    alias cmd="cmd.exe"
    
    # Development shortcuts
    alias ll="ls -alF"
    alias la="ls -A"
    alias l="ls -CF"
    alias grep="grep --color=auto"
    alias fgrep="fgrep --color=auto"
    alias egrep="egrep --color=auto"
fi

# Windows PATH filtering
if [[ "$ENABLE_WINDOWS_PATH_FILTERING" == true ]]; then
    # Filter Windows PATH to only include essential elements
    export PATH=$(echo $PATH | tr ':' '\n' | grep -E '^/mnt/c/(Windows/System32|Windows|Program Files)' | tr '\n' ':' | sed 's/:$//')$(echo $PATH | tr ':' '\n' | grep -v '^/mnt/c/' | tr '\n' ':' | sed 's/:$//')
fi

# WSL environment variables
export WSL_DISTRO_NAME=$(cat /etc/hostname 2>/dev/null || echo "unknown")
export IS_WSL=true

EOF
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Shell enhancements configured"
    fi
}

# Function to configure port forwarding
configure_port_forwarding() {
    if [[ "$ENABLE_PORT_FORWARDING" == false || ${#FORWARDED_PORTS[@]} -eq 0 || "$DRY_RUN" == true ]]; then
        if [[ "$DRY_RUN" == true && "$ENABLE_PORT_FORWARDING" == true ]]; then
            echo "[DRY-RUN] Would configure port forwarding for ports: ${FORWARDED_PORTS[*]}"
        fi
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring port forwarding..."
    fi
    
    # Create PowerShell script for port forwarding
    local ps_script="/mnt/c/Users/$WINDOWS_USER/wsl_port_forward.ps1"
    
    cat << EOF > "$ps_script"
# WSL Port Forwarding Script
# Generated by bashmin on $(date)

# Remove existing port forwarding rules
netsh interface portproxy reset

# Add new port forwarding rules
EOF
    
    for port in "${FORWARDED_PORTS[@]}"; do
        echo "netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=localhost" >> "$ps_script"
    done
    
    cat << EOF >> "$ps_script"

# Display current port forwarding rules
Write-Host "Current port forwarding rules:"
netsh interface portproxy show all
EOF
    
    print_info "Port forwarding script created: $ps_script"
    print_info "Run as Administrator in PowerShell: & '$ps_script'"
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Port forwarding configuration prepared"
    fi
}

# Function to optimize performance
optimize_performance() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would apply performance optimizations"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Applying performance optimizations..."
    fi
    
    # Disable unnecessary services if systemd is enabled
    if [[ "$ENABLE_SYSTEMD" == true ]] && command -v systemctl >/dev/null 2>&1; then
        # Disable unnecessary services for WSL
        for service in "snapd" "bluetooth" "cups" "avahi-daemon"; do
            sudo systemctl disable "$service" 2>/dev/null || true
            sudo systemctl stop "$service" 2>/dev/null || true
        done
    fi
    
    # Configure swappiness for better performance
    echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf >/dev/null
    
    # Optimize file system cache
    echo "vm.vfs_cache_pressure=50" | sudo tee -a /etc/sysctl.conf >/dev/null
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Performance optimizations applied"
    fi
}

# Helper function to convert boolean to true/false
bool_to_true_false() {
    if [[ "$1" == true ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to show completion summary
show_completion_summary() {
    if [[ "$QUIET" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo
    print_success "WSL2 configuration completed successfully! 🚀"
    echo
    print_info "=== WSL2 Configuration Summary ==="
    cat << EOF
WSL Version:         $WSL_VERSION
Distribution:        $WSL_DISTRO_NAME
Windows User:        $WINDOWS_USER

System Settings:
  Systemd:           $(bool_to_true_false $ENABLE_SYSTEMD)
  Windows Interop:   $(bool_to_true_false $ENABLE_INTEROP)
  Windows PATH:      $(bool_to_true_false $APPEND_NT_PATH)
  GPU Support:       $(bool_to_true_false $ENABLE_GPU_SUPPORT)

EOF

    if [[ "$CONFIGURE_MEMORY_LIMIT" == true || "$CONFIGURE_PROCESSORS" == true || "$CONFIGURE_SWAP" == true ]]; then
        print_info "=== Resource Limits ==="
        [[ "$CONFIGURE_MEMORY_LIMIT" == true ]] && echo "Memory Limit:        $MEMORY_LIMIT"
        [[ "$CONFIGURE_PROCESSORS" == true ]] && echo "Processor Limit:     $PROCESSOR_COUNT"
        [[ "$CONFIGURE_SWAP" == true ]] && echo "Swap Size:           $SWAP_SIZE"
        echo
    fi

    if [[ "$CONFIGURE_NETWORKING" == true ]]; then
        print_info "=== Networking ==="
        cat << EOF
Network Mode:        $NETWORK_MODE
DNS Configuration:   $(bool_to_true_false $CONFIGURE_DNS)
$(if [[ "$CONFIGURE_DNS" == true ]]; then echo "DNS Servers:         ${DNS_SERVERS[*]}"; fi)
$(if [[ "$ENABLE_PORT_FORWARDING" == true ]]; then echo "Port Forwarding:     ${FORWARDED_PORTS[*]}"; fi)

EOF
    fi

    print_info "=== Development Tools ==="
    cat << EOF
Docker Integration:  $(bool_to_true_false $ENABLE_DOCKER_INTEGRATION)
VS Code Integration: $(bool_to_true_false $ENABLE_VSCODE_INTEGRATION)
Git Credential Mgr:  $(bool_to_true_false $CONFIGURE_GIT_CREDENTIAL_MANAGER)
WSL Aliases:         $(bool_to_true_false $ENABLE_WSL_ALIASES)

EOF

    print_info "=== Configuration Files ==="
    cat << EOF
WSL Config:          $WSL_CONF
Windows Config:      /mnt/c/Users/$WINDOWS_USER/.wslconfig
Bash Config:         $BASHRC_PATH
DNS Config:          $(if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved; then echo "$SYSTEMD_RESOLVED_CONF"; else echo "$RESOLV_CONF"; fi)

EOF

    print_info "=== Next Steps ==="
    cat << EOF
1. Restart WSL to apply changes: wsl --shutdown
2. Start your distribution again
3. Verify configuration: cat /etc/wsl.conf
$(if [[ "$ENABLE_PORT_FORWARDING" == true ]]; then echo "4. Run port forwarding script as Administrator in PowerShell"; fi)
$(if [[ "$ENABLE_GPU_SUPPORT" == true ]]; then echo "5. Install NVIDIA drivers for WSL if needed"; fi)

EOF

    print_info "=== Verification Commands ==="
    cat << EOF
Check systemd:       systemctl status
Check DNS:           nslookup google.com
Check mounts:        mount | grep drvfs
Check locale:        locale
Check timezone:      timedatectl
$(if [[ "$ENABLE_DOCKER_INTEGRATION" == true ]]; then echo "Check Docker:        docker version"; fi)

EOF

    print_warning "Important: Restart WSL with 'wsl --shutdown' to apply all changes!"
    
    print_info "🏗️ Your WSL2 environment is now optimized for development!"
}

# Main function
main() {
    # Detect WSL environment
    detect_wsl_environment
    
    if [[ "$QUIET" == false ]]; then
        show_script_header "WSL2 Configuration"
        print_info "Configuring WSL2 environment for optimal development experience"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show configuration plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuration plan:"
        print_info "  WSL Version: $WSL_VERSION"
        print_info "  Systemd: $(bool_to_true_false $ENABLE_SYSTEMD)"
        print_info "  Windows Interop: $(bool_to_true_false $ENABLE_INTEROP)"
        print_info "  Network Mode: $NETWORK_MODE"
        [[ "$CONFIGURE_MEMORY_LIMIT" == true ]] && print_info "  Memory Limit: $MEMORY_LIMIT"
        [[ "$CONFIGURE_PROCESSORS" == true ]] && print_info "  Processor Limit: $PROCESSOR_COUNT"
        print_info "  Development Tools: Docker=$ENABLE_DOCKER_INTEGRATION, VSCode=$ENABLE_VSCODE_INTEGRATION"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with WSL2 configuration?" "Y"; then
            print_info "WSL2 configuration cancelled"
            exit 0
        fi
    fi
    
    # Execute configuration steps
    configure_wsl_conf
    configure_wslconfig
    configure_dns
    configure_locale_timezone
    configure_development_tools
    configure_shell_enhancements
    configure_port_forwarding
    optimize_performance
    
    # Show completion summary
    show_completion_summary
}

# Run main function
main "$@"
