#!/bin/bash
#
# Script: development/tldr/install.sh
# Description: Install and configure TLDR (Too Long; Didn't Read) community-driven manual pages
# Usage: ./install.sh [OPTIONS]
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly TLDR_USER="tldr"
readonly TLDR_GROUP="tldr"
readonly TLDR_HOME="/opt/tldr"
readonly TLDR_CONFIG_DIR="/etc/tldr"
readonly BASHMIN_LOG_DIR="/var/log/bashmin"
readonly BASHMIN_TLDR_DIR="/var/log/bashmin/development/tldr"
readonly TLDR_CACHE_DIR="/var/cache/tldr"
readonly TLDR_CLIENT_REPO="https://github.com/tldr-pages/tldr-c-client.git"
readonly TLDR_PAGES_REPO="https://github.com/tldr-pages/tldr.git"
readonly TEALDEER_RELEASES_URL="https://api.github.com/repos/dbrgn/tealdeer/releases/latest"
readonly TLDR_NODE_CLIENT="@tldr-pages/tldr"

# Configuration variables
INSTALL_METHOD="tealdeer"  # tealdeer (Rust), node (Node.js), c-client (C), python (Python)
CLIENT_TYPE="binary"       # binary, source, package
AUTO_UPDATE=true
ENABLE_COMPLETION=true
ENABLE_SYNTAX_HIGHLIGHTING=true
CACHE_UPDATE_FREQUENCY="weekly"
DEFAULT_LANGUAGE="en"
SUPPORTED_LANGUAGES=("en" "es" "fr" "de" "it" "pt_BR" "ru" "zh" "ja" "ko")
SELECTED_LANGUAGES=("en")
ENABLE_CUSTOM_PAGES=true
CUSTOM_PAGES_DIR="/usr/local/share/tldr-custom"
ENABLE_STATISTICS=false
ENABLE_OFFLINE_MODE=true
FORCE=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Help function
show_help() {
    cat << 'EOF'
TLDR (Too Long; Didn't Read) Installation

DESCRIPTION:
    Install and configure TLDR community-driven manual pages system.
    Provides simplified, practical examples for command-line tools with
    support for multiple languages, custom pages, and automatic updates.

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    Installation Configuration:
    --install-method METHOD     Installation method: tealdeer, node, c-client, python [tealdeer]
    --client-type TYPE          Client installation type: binary, source, package [binary]
    --force                     Force reinstallation even if TLDR exists
    
    Language & Localization:
    --language LANG             Default language for TLDR pages [en]
    --languages LANG1,LANG2     Comma-separated list of languages to install [en]
    --list-languages            Show available languages and exit
    
    Features & Configuration:
    --enable-completion         Enable shell completion (bash, zsh, fish) [default]
    --disable-completion        Disable shell completion
    --enable-syntax-highlighting Enable syntax highlighting in output [default]
    --disable-syntax-highlighting Disable syntax highlighting
    --enable-custom-pages       Enable custom pages support [default]
    --disable-custom-pages      Disable custom pages support
    --custom-pages-dir DIR      Custom pages directory [/usr/local/share/tldr-custom]
    
    Updates & Caching:
    --auto-update               Enable automatic page updates [default]
    --disable-auto-update       Disable automatic page updates
    --cache-frequency FREQ      Cache update frequency: daily, weekly, monthly [weekly]
    --enable-offline-mode       Enable offline mode support [default]
    --disable-offline-mode      Disable offline mode support
    
    Statistics & Analytics:
    --enable-statistics         Enable usage statistics collection
    --disable-statistics        Disable usage statistics [default]
    
    Execution Control:
    --dry-run                   Show what would be installed without executing
    --verbose                   Enable verbose output
    --quiet                     Suppress non-essential output
    --help                      Show this help message

INSTALLATION METHODS:
    tealdeer                    Fast Rust implementation (recommended)
                               - Fastest performance
                               - Best shell integration
                               - Syntax highlighting support
    
    node                        Node.js implementation
                               - Rich features
                               - Good cross-platform support
                               - Requires Node.js runtime
    
    c-client                    Original C implementation
                               - Lightweight and fast
                               - Minimal dependencies
                               - Good for resource-constrained systems
    
    python                      Python implementation
                               - Feature-rich
                               - Easy to extend
                               - Requires Python runtime

SUPPORTED LANGUAGES:
    en          English (default)
    es          Spanish
    fr          French
    de          German
    it          Italian
    pt_BR       Portuguese (Brazil)
    ru          Russian
    zh          Chinese
    ja          Japanese
    ko          Korean

EXAMPLES:
    # Install with default settings (Tealdeer Rust client)
    sudo ./install.sh

    # Install Node.js client with multiple languages
    sudo ./install.sh --install-method node --languages "en,es,fr"

    # Install C client from source with custom configuration
    sudo ./install.sh --install-method c-client --client-type source --enable-custom-pages

    # Install with daily cache updates and shell completion
    sudo ./install.sh --cache-frequency daily --enable-completion

    # Quiet installation for automation
    sudo ./install.sh --quiet --disable-statistics

    # Dry run to preview installation
    sudo ./install.sh --dry-run --verbose

POST-INSTALLATION:
    After installation, update the page cache:
    $ tldr --update

    Example usage:
    $ tldr tar              # Show examples for tar command
    $ tldr git commit       # Show examples for git commit
    $ tldr -l es curl       # Show examples in Spanish

    Custom pages can be added to: /usr/local/share/tldr-custom/

EOF
}

# Function to show available languages
show_languages() {
    echo "Available TLDR Languages:"
    echo "========================"
    echo
    printf "%-8s %s\n" "Code" "Language"
    echo "$(printf '%.0s-' {1..30})"
    printf "%-8s %s\n" "en" "English (default)"
    printf "%-8s %s\n" "es" "Spanish"
    printf "%-8s %s\n" "fr" "French"
    printf "%-8s %s\n" "de" "German"
    printf "%-8s %s\n" "it" "Italian"
    printf "%-8s %s\n" "pt_BR" "Portuguese (Brazil)"
    printf "%-8s %s\n" "ru" "Russian"
    printf "%-8s %s\n" "zh" "Chinese"
    printf "%-8s %s\n" "ja" "Japanese"
    printf "%-8s %s\n" "ko" "Korean"
    echo
    echo "Usage: --languages \"en,es,fr\" or --language \"de\""
}

# Function to validate language codes
validate_language() {
    local lang="$1"
    for supported in "${SUPPORTED_LANGUAGES[@]}"; do
        if [[ "$lang" == "$supported" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to parse language list
parse_languages() {
    local lang_string="$1"
    IFS=',' read -ra langs <<< "$lang_string"
    SELECTED_LANGUAGES=()
    
    for lang in "${langs[@]}"; do
        lang=$(echo "$lang" | xargs)  # Trim whitespace
        if validate_language "$lang"; then
            SELECTED_LANGUAGES+=("$lang")
        else
            print_error "Invalid language code: $lang"
            show_languages
            exit 1
        fi
    done
    
    if [[ ${#SELECTED_LANGUAGES[@]} -eq 0 ]]; then
        print_error "No valid languages specified"
        exit 1
    fi
}

# Function to check system requirements
check_requirements() {
    print_info "Checking system requirements..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check available disk space (minimum 100MB)
    local available_space=$(df /usr/local | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 102400 ]]; then  # 100MB in KB
        print_warning "Low disk space available. TLDR installation requires at least 100MB."
    fi
    
    # Check internet connectivity
    if ! ping -c 1 github.com >/dev/null 2>&1; then
        print_warning "No internet connectivity detected. Some installation methods may fail."
    fi
    
    # Method-specific requirements
    case "$INSTALL_METHOD" in
        "tealdeer")
            if ! command -v curl >/dev/null 2>&1; then
                print_info "Installing curl for Tealdeer installation..."
                apt-get update -qq && apt-get install -y curl
            fi
            ;;
        "node")
            if ! command -v node >/dev/null 2>&1; then
                print_info "Node.js is required for Node.js client installation"
                print_info "Installing Node.js..."
                install_nodejs
            fi
            if ! command -v npm >/dev/null 2>&1; then
                print_error "npm is required but not found"
                exit 1
            fi
            ;;
        "c-client")
            if [[ "$CLIENT_TYPE" == "source" ]]; then
                print_info "Installing build dependencies for C client..."
                apt-get update -qq && apt-get install -y build-essential git libcurl4-openssl-dev libzip-dev pkg-config
            fi
            ;;
        "python")
            if ! command -v python3 >/dev/null 2>&1; then
                print_info "Installing Python3..."
                apt-get update -qq && apt-get install -y python3 python3-pip
            fi
            ;;
    esac
}

# Function to install Node.js if needed
install_nodejs() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install Node.js"
        return 0
    fi
    
    print_info "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs
}

# Function to create system user and directories
create_system_structure() {
    print_info "Creating system structure..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create TLDR user and directories"
        return 0
    fi
    
    # Create TLDR user if it doesn't exist
    if ! id "$TLDR_USER" >/dev/null 2>&1; then
        print_info "Creating TLDR system user..."
        useradd --system --home-dir "$TLDR_HOME" --shell /bin/false --user-group "$TLDR_USER"
    fi
    
    # Create directories
    local dirs=(
        "$TLDR_HOME"
        "$TLDR_CONFIG_DIR"
        "$BASHMIN_TLDR_DIR"
        "$TLDR_CACHE_DIR"
        "/usr/local/share/man/man1"
    )
    
    if [[ "$ENABLE_CUSTOM_PAGES" == true ]]; then
        dirs+=("$CUSTOM_PAGES_DIR")
    fi
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        if [[ "$dir" == "$TLDR_CACHE_DIR" || "$dir" == "$BASHMIN_TLDR_DIR" ]]; then
            chown "$TLDR_USER:$TLDR_GROUP" "$dir"
        fi
    done
    
    print_success "System structure created"
}

# Function to install Tealdeer (Rust implementation)
install_tealdeer() {
    print_info "Installing Tealdeer (Rust TLDR client)..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install Tealdeer from GitHub releases"
        return 0
    fi
    
    # Get latest release URL
    local release_info
    release_info=$(curl -s "$TEALDEER_RELEASES_URL")
    
    # Detect architecture
    local arch
    case "$(uname -m)" in
        x86_64) arch="x86_64-unknown-linux-musl" ;;
        aarch64) arch="aarch64-unknown-linux-musl" ;;
        armv7l) arch="armv7-unknown-linux-musleabihf" ;;
        *) 
            print_error "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac
    
    # Extract download URL
    local download_url
    download_url=$(echo "$release_info" | jq -r ".assets[] | select(.name | contains(\"$arch\")) | .browser_download_url")
    
    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        print_error "Could not find Tealdeer binary for architecture: $arch"
        return 1
    fi
    
    print_info "Downloading Tealdeer binary..."
    local temp_file="/tmp/tldr-tealdeer"
    curl -L -o "$temp_file" "$download_url"
    
    # Install binary
    install -m 755 "$temp_file" /usr/local/bin/tldr
    rm "$temp_file"
    
    # Create man page
    /usr/local/bin/tldr --gen-manual > /usr/local/share/man/man1/tldr.1
    
    print_success "Tealdeer installed successfully"
}

# Function to install Node.js client
install_node_client() {
    print_info "Installing Node.js TLDR client..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install Node.js TLDR client via npm"
        return 0
    fi
    
    npm install -g "$TLDR_NODE_CLIENT"
    
    print_success "Node.js TLDR client installed successfully"
}

# Function to install C client
install_c_client() {
    print_info "Installing C TLDR client..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install C TLDR client from source"
        return 0
    fi
    
    if [[ "$CLIENT_TYPE" == "package" ]] && command -v apt-get >/dev/null 2>&1; then
        # Try package installation first
        if apt-get update -qq && apt-get install -y tldr 2>/dev/null; then
            print_success "C TLDR client installed from package"
            return 0
        else
            print_warning "Package installation failed, falling back to source compilation"
        fi
    fi
    
    # Install from source
    local build_dir="/tmp/tldr-c-client"
    rm -rf "$build_dir"
    
    print_info "Cloning C client repository..."
    git clone "$TLDR_CLIENT_REPO" "$build_dir"
    
    cd "$build_dir"
    
    print_info "Compiling C client..."
    make
    
    print_info "Installing C client..."
    make install
    
    # Cleanup
    cd /
    rm -rf "$build_dir"
    
    print_success "C TLDR client installed successfully"
}

# Function to install Python client
install_python_client() {
    print_info "Installing Python TLDR client..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install Python TLDR client via pip"
        return 0
    fi
    
    pip3 install tldr
    
    print_success "Python TLDR client installed successfully"
}

# Function to install TLDR client based on method
install_tldr_client() {
    case "$INSTALL_METHOD" in
        "tealdeer")
            install_tealdeer
            ;;
        "node")
            install_node_client
            ;;
        "c-client")
            install_c_client
            ;;
        "python")
            install_python_client
            ;;
        *)
            print_error "Unknown installation method: $INSTALL_METHOD"
            return 1
            ;;
    esac
}

# Function to configure TLDR
configure_tldr() {
    print_info "Configuring TLDR..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure TLDR settings"
        return 0
    fi
    
    # Create configuration file for Tealdeer
    if [[ "$INSTALL_METHOD" == "tealdeer" ]]; then
        local config_file="$TLDR_CONFIG_DIR/config.toml"
        cat > "$config_file" << EOF
[display]
compact = false
use_pager = false

[style]
description.foreground = "white"
command_name.foreground = "green"
example_text.foreground = "blue"
example_code.foreground = "yellow"

[updates]
auto_update = $AUTO_UPDATE
auto_update_interval_hours = 168  # Weekly

[directories]
cache_dir = "$TLDR_CACHE_DIR"
EOF

        if [[ "$ENABLE_CUSTOM_PAGES" == true ]]; then
            echo "custom_pages_dir = \"$CUSTOM_PAGES_DIR\"" >> "$config_file"
        fi
        
        chown root:root "$config_file"
        chmod 644 "$config_file"
    fi
    
    # Set default language environment variable
    if [[ "$DEFAULT_LANGUAGE" != "en" ]]; then
        echo "export TLDR_LANGUAGE=$DEFAULT_LANGUAGE" > /etc/environment.d/tldr.conf
    fi
    
    print_success "TLDR configuration completed"
}

# Function to setup shell completion
setup_completion() {
    if [[ "$ENABLE_COMPLETION" != true ]]; then
        return 0
    fi
    
    print_info "Setting up shell completion..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would setup shell completion for bash, zsh, and fish"
        return 0
    fi
    
    # Bash completion
    if [[ "$INSTALL_METHOD" == "tealdeer" ]]; then
        /usr/local/bin/tldr --gen-completion bash > /etc/bash_completion.d/tldr
    fi
    
    # Zsh completion
    if [[ -d /usr/share/zsh/vendor-completions ]]; then
        if [[ "$INSTALL_METHOD" == "tealdeer" ]]; then
            /usr/local/bin/tldr --gen-completion zsh > /usr/share/zsh/vendor-completions/_tldr
        fi
    fi
    
    # Fish completion
    if [[ -d /usr/share/fish/vendor_completions.d ]]; then
        if [[ "$INSTALL_METHOD" == "tealdeer" ]]; then
            /usr/local/bin/tldr --gen-completion fish > /usr/share/fish/vendor_completions.d/tldr.fish
        fi
    fi
    
    print_success "Shell completion configured"
}

# Function to create custom pages directory structure
setup_custom_pages() {
    if [[ "$ENABLE_CUSTOM_PAGES" != true ]]; then
        return 0
    fi
    
    print_info "Setting up custom pages support..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would setup custom pages directory structure"
        return 0
    fi
    
    # Create language directories for custom pages
    for lang in "${SELECTED_LANGUAGES[@]}"; do
        local lang_dir="$CUSTOM_PAGES_DIR/pages.$lang"
        mkdir -p "$lang_dir"
        
        # Create example custom page
        if [[ ! -f "$lang_dir/example.md" ]]; then
            cat > "$lang_dir/example.md" << 'EOF'
# example

> Custom example command for TLDR.
> More information: <https://example.com>.

- Example usage:
  `example {{argument}}`

- Example with option:
  `example --option {{value}}`

- Example with multiple arguments:
  `example {{arg1}} {{arg2}}`
EOF
        fi
    done
    
    # Set permissions
    chown -R "$TLDR_USER:$TLDR_GROUP" "$CUSTOM_PAGES_DIR"
    chmod -R 755 "$CUSTOM_PAGES_DIR"
    
    print_success "Custom pages directory configured"
}

# Function to update TLDR cache
update_cache() {
    print_info "Updating TLDR page cache..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would update TLDR page cache"
        return 0
    fi
    
    # Update cache for each selected language
    for lang in "${SELECTED_LANGUAGES[@]}"; do
        print_info "Updating cache for language: $lang"
        if [[ "$lang" == "en" ]]; then
            sudo -u "$TLDR_USER" tldr --update 2>/dev/null || true
        else
            sudo -u "$TLDR_USER" TLDR_LANGUAGE="$lang" tldr --update 2>/dev/null || true
        fi
    done
    
    print_success "TLDR cache updated"
}

# Function to setup automatic updates
setup_auto_updates() {
    if [[ "$AUTO_UPDATE" != true ]]; then
        return 0
    fi
    
    print_info "Setting up automatic cache updates..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would setup automatic cache updates"
        return 0
    fi
    
    # Create update script
    local update_script="/usr/local/bin/tldr-update-cache"
    cat > "$update_script" << 'EOF'
#!/bin/bash
#
# TLDR Cache Update Script
# Automatically updates TLDR page cache
#

set -euo pipefail

TLDR_USER="tldr"
LOG_FILE="/var/log/bashmin/development/tldr/cache-update.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

echo "$(date): Starting TLDR cache update" >> "$LOG_FILE"

# Update cache
if sudo -u "$TLDR_USER" tldr --update >> "$LOG_FILE" 2>&1; then
    echo "$(date): TLDR cache updated successfully" >> "$LOG_FILE"
else
    echo "$(date): TLDR cache update failed" >> "$LOG_FILE"
    exit 1
fi
EOF
    
    chmod +x "$update_script"
    
    # Create cron job
    local cron_schedule
    case "$CACHE_UPDATE_FREQUENCY" in
        "daily") cron_schedule="0 2 * * *" ;;
        "weekly") cron_schedule="0 2 * * 0" ;;
        "monthly") cron_schedule="0 2 1 * *" ;;
        *) cron_schedule="0 2 * * 0" ;;  # Default to weekly
    esac
    
    cat > /etc/cron.d/tldr-cache-update << EOF
# TLDR Cache Update
# Update TLDR page cache automatically
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

$cron_schedule root /usr/local/bin/tldr-update-cache
EOF
    
    print_success "Automatic updates configured ($CACHE_UPDATE_FREQUENCY)"
}

# Function to create management script
create_management_script() {
    print_info "Creating TLDR management script..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create TLDR management script"
        return 0
    fi
    
    local mgmt_script="/usr/local/bin/tldr-manage"
    cat > "$mgmt_script" << 'SCRIPT_EOF'
#!/bin/bash
#
# TLDR Management Script
# Manage TLDR installation and configuration
#

set -euo pipefail

TLDR_USER="tldr"
TLDR_CACHE_DIR="/var/cache/tldr"
CUSTOM_PAGES_DIR="/usr/local/share/tldr-custom"
LOG_FILE="/var/log/bashmin/development/tldr/management.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

show_help() {
    cat << 'HELP_EOF'
TLDR Management Script

USAGE:
    tldr-manage [COMMAND] [OPTIONS]

COMMANDS:
    update                      Update TLDR page cache
    update-all                  Update cache for all languages
    clear-cache                 Clear TLDR cache
    show-stats                  Show TLDR usage statistics
    list-languages              List installed languages
    add-language LANG           Add language support
    remove-language LANG        Remove language support
    create-custom-page NAME     Create custom page template
    list-custom-pages           List custom pages
    validate-custom-pages       Validate custom page syntax
    backup-config               Backup TLDR configuration
    restore-config FILE         Restore TLDR configuration
    health-check                Check TLDR installation health
    version                     Show TLDR version information

OPTIONS:
    --verbose                   Enable verbose output
    --quiet                     Suppress non-essential output
    --help                      Show this help message

EXAMPLES:
    tldr-manage update
    tldr-manage add-language es
    tldr-manage create-custom-page mycommand
    tldr-manage health-check
HELP_EOF
}

log_action() {
    echo "$(date): $*" >> "$LOG_FILE"
}

update_cache() {
    echo "Updating TLDR cache..."
    log_action "Cache update started"
    
    if sudo -u "$TLDR_USER" tldr --update; then
        echo "Cache updated successfully"
        log_action "Cache update completed successfully"
    else
        echo "Cache update failed"
        log_action "Cache update failed"
        exit 1
    fi
}

clear_cache() {
    echo "Clearing TLDR cache..."
    log_action "Cache clear started"
    
    rm -rf "$TLDR_CACHE_DIR"/*
    mkdir -p "$TLDR_CACHE_DIR"
    chown "$TLDR_USER:$TLDR_USER" "$TLDR_CACHE_DIR"
    
    echo "Cache cleared successfully"
    log_action "Cache cleared successfully"
}

show_stats() {
    echo "TLDR Statistics:"
    echo "================"
    
    if [[ -d "$TLDR_CACHE_DIR" ]]; then
        local cache_size=$(du -sh "$TLDR_CACHE_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
        echo "Cache size: $cache_size"
        
        local page_count=$(find "$TLDR_CACHE_DIR" -name "*.md" 2>/dev/null | wc -l || echo "0")
        echo "Total pages: $page_count"
        
        local last_update=$(stat -c %y "$TLDR_CACHE_DIR" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")
        echo "Last update: $last_update"
    fi
    
    if [[ -d "$CUSTOM_PAGES_DIR" ]]; then
        local custom_count=$(find "$CUSTOM_PAGES_DIR" -name "*.md" 2>/dev/null | wc -l || echo "0")
        echo "Custom pages: $custom_count"
    fi
}

create_custom_page() {
    local page_name="$1"
    local page_file="$CUSTOM_PAGES_DIR/pages.en/$page_name.md"
    
    if [[ -f "$page_file" ]]; then
        echo "Custom page already exists: $page_file"
        return 1
    fi
    
    mkdir -p "$(dirname "$page_file")"
    
    cat > "$page_file" << PAGE_EOF
# $page_name

> Description of $page_name command.
> More information: <https://example.com>.

- Basic usage:
  \`$page_name\`

- Usage with argument:
  \`$page_name {{argument}}\`

- Usage with option:
  \`$page_name --option {{value}}\`
PAGE_EOF
    
    echo "Custom page created: $page_file"
    echo "Edit the file to add your command examples"
}

health_check() {
    echo "TLDR Health Check:"
    echo "=================="
    
    # Check if TLDR is installed
    if command -v tldr >/dev/null 2>&1; then
        echo "✓ TLDR binary is available"
        echo "  Version: $(tldr --version 2>/dev/null || echo 'Unknown')"
    else
        echo "✗ TLDR binary not found"
        return 1
    fi
    
    # Check cache directory
    if [[ -d "$TLDR_CACHE_DIR" ]]; then
        echo "✓ Cache directory exists"
        
        local cache_files=$(find "$TLDR_CACHE_DIR" -name "*.md" 2>/dev/null | wc -l)
        if [[ $cache_files -gt 0 ]]; then
            echo "✓ Cache contains $cache_files pages"
        else
            echo "⚠ Cache is empty - run 'tldr-manage update'"
        fi
    else
        echo "✗ Cache directory missing"
    fi
    
    # Check custom pages
    if [[ -d "$CUSTOM_PAGES_DIR" ]]; then
        echo "✓ Custom pages directory exists"
    fi
    
    # Check permissions
    if [[ -O "$TLDR_CACHE_DIR" ]] || [[ "$(stat -c %U "$TLDR_CACHE_DIR" 2>/dev/null)" == "$TLDR_USER" ]]; then
        echo "✓ Cache permissions are correct"
    else
        echo "⚠ Cache permissions may be incorrect"
    fi
    
    echo "Health check completed"
}

# Main command dispatcher
case "${1:-help}" in
    "update") update_cache ;;
    "clear-cache") clear_cache ;;
    "show-stats") show_stats ;;
    "create-custom-page") 
        if [[ -n "${2:-}" ]]; then
            create_custom_page "$2"
        else
            echo "Error: Page name required"
            echo "Usage: tldr-manage create-custom-page PAGE_NAME"
            exit 1
        fi
        ;;
    "health-check") health_check ;;
    "version") tldr --version 2>/dev/null || echo "TLDR version information not available" ;;
    "help"|"--help") show_help ;;
    *)
        echo "Unknown command: ${1:-}"
        echo "Use 'tldr-manage help' for usage information"
        exit 1
        ;;
esac
SCRIPT_EOF
    
    chmod +x "$mgmt_script"
    
    print_success "Management script created: /usr/local/bin/tldr-manage"
}

# Function to run installation tests
run_tests() {
    print_info "Running installation tests..."
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would run installation tests"
        return 0
    fi
    
    local test_failed=false
    
    # Test 1: Check if TLDR binary is available
    if command -v tldr >/dev/null 2>&1; then
        print_success "✓ TLDR binary is available"
    else
        print_error "✗ TLDR binary not found"
        test_failed=true
    fi
    
    # Test 2: Check if cache directory exists
    if [[ -d "$TLDR_CACHE_DIR" ]]; then
        print_success "✓ Cache directory exists"
    else
        print_error "✗ Cache directory missing"
        test_failed=true
    fi
    
    # Test 3: Test basic functionality
    if tldr --version >/dev/null 2>&1; then
        print_success "✓ TLDR responds to version command"
    else
        print_error "✗ TLDR version command failed"
        test_failed=true
    fi
    
    # Test 4: Test cache functionality (if cache exists)
    local cache_files=$(find "$TLDR_CACHE_DIR" -name "*.md" 2>/dev/null | wc -l)
    if [[ $cache_files -gt 0 ]]; then
        print_success "✓ Cache contains $cache_files pages"
        
        # Test a common command
        if tldr tar >/dev/null 2>&1; then
            print_success "✓ Basic command lookup works"
        else
            print_warning "⚠ Command lookup test failed (cache may need updating)"
        fi
    else
        print_warning "⚠ Cache is empty - pages need to be downloaded"
    fi
    
    if [[ "$test_failed" == true ]]; then
        print_error "Some tests failed. Check the installation."
        return 1
    else
        print_success "All tests passed successfully"
        return 0
    fi
}

# Function to show installation summary
show_summary() {
    echo
    print_info "TLDR Installation Summary"
    echo "========================="
    echo
    echo "Installation Method: $INSTALL_METHOD"
    echo "Languages: ${SELECTED_LANGUAGES[*]}"
    echo "Cache Directory: $TLDR_CACHE_DIR"
    echo "Custom Pages: $ENABLE_CUSTOM_PAGES"
    if [[ "$ENABLE_CUSTOM_PAGES" == true ]]; then
        echo "Custom Pages Directory: $CUSTOM_PAGES_DIR"
    fi
    echo "Auto Updates: $AUTO_UPDATE"
    if [[ "$AUTO_UPDATE" == true ]]; then
        echo "Update Frequency: $CACHE_UPDATE_FREQUENCY"
    fi
    echo "Shell Completion: $ENABLE_COMPLETION"
    echo
    echo "Next Steps:"
    echo "----------"
    echo "1. Update the page cache: tldr --update"
    echo "2. Try a command: tldr tar"
    echo "3. For management tasks: tldr-manage help"
    if [[ "$ENABLE_CUSTOM_PAGES" == true ]]; then
        echo "4. Create custom pages: tldr-manage create-custom-page mycommand"
    fi
    echo
    echo "Log file: $BASHMIN_TLDR_DIR/install.log"
    echo "Management script: /usr/local/bin/tldr-manage"
    echo
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install-method)
                if [[ -n "${2:-}" ]]; then
                    INSTALL_METHOD="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --client-type)
                if [[ -n "${2:-}" ]]; then
                    CLIENT_TYPE="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --language)
                if [[ -n "${2:-}" ]]; then
                    DEFAULT_LANGUAGE="$2"
                    SELECTED_LANGUAGES=("$2")
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --languages)
                if [[ -n "${2:-}" ]]; then
                    parse_languages "$2"
                    if [[ ${#SELECTED_LANGUAGES[@]} -gt 0 ]]; then
                        DEFAULT_LANGUAGE="${SELECTED_LANGUAGES[0]}"
                    fi
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --list-languages)
                show_languages
                exit 0
                ;;
            --enable-completion)
                ENABLE_COMPLETION=true
                shift
                ;;
            --disable-completion)
                ENABLE_COMPLETION=false
                shift
                ;;
            --enable-syntax-highlighting)
                ENABLE_SYNTAX_HIGHLIGHTING=true
                shift
                ;;
            --disable-syntax-highlighting)
                ENABLE_SYNTAX_HIGHLIGHTING=false
                shift
                ;;
            --enable-custom-pages)
                ENABLE_CUSTOM_PAGES=true
                shift
                ;;
            --disable-custom-pages)
                ENABLE_CUSTOM_PAGES=false
                shift
                ;;
            --custom-pages-dir)
                if [[ -n "${2:-}" ]]; then
                    CUSTOM_PAGES_DIR="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --auto-update)
                AUTO_UPDATE=true
                shift
                ;;
            --disable-auto-update)
                AUTO_UPDATE=false
                shift
                ;;
            --cache-frequency)
                if [[ -n "${2:-}" ]]; then
                    CACHE_UPDATE_FREQUENCY="$2"
                    shift 2
                else
                    print_error "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --enable-offline-mode)
                ENABLE_OFFLINE_MODE=true
                shift
                ;;
            --disable-offline-mode)
                ENABLE_OFFLINE_MODE=false
                shift
                ;;
            --enable-statistics)
                ENABLE_STATISTICS=true
                shift
                ;;
            --disable-statistics)
                ENABLE_STATISTICS=false
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Function to validate configuration
validate_configuration() {
    # Validate installation method
    case "$INSTALL_METHOD" in
        "tealdeer"|"node"|"c-client"|"python") ;;
        *)
            print_error "Invalid installation method: $INSTALL_METHOD"
            echo "Valid methods: tealdeer, node, c-client, python"
            exit 1
            ;;
    esac
    
    # Validate client type
    case "$CLIENT_TYPE" in
        "binary"|"source"|"package") ;;
        *)
            print_error "Invalid client type: $CLIENT_TYPE"
            echo "Valid types: binary, source, package"
            exit 1
            ;;
    esac
    
    # Validate cache frequency
    case "$CACHE_UPDATE_FREQUENCY" in
        "daily"|"weekly"|"monthly") ;;
        *)
            print_error "Invalid cache frequency: $CACHE_UPDATE_FREQUENCY"
            echo "Valid frequencies: daily, weekly, monthly"
            exit 1
            ;;
    esac
    
    # Validate languages
    for lang in "${SELECTED_LANGUAGES[@]}"; do
        if ! validate_language "$lang"; then
            print_error "Invalid language: $lang"
            show_languages
            exit 1
        fi
    done
}

# Main execution function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate configuration
    validate_configuration
    
    # Show header
    if [[ "$QUIET" != true ]]; then
        show_script_header "TLDR Installation Script" 60
        print_info "Installation method: $INSTALL_METHOD"
        print_info "Languages: ${SELECTED_LANGUAGES[*]}"
        echo
    fi
    
    # Start logging
    mkdir -p "$BASHMIN_TLDR_DIR"
    exec 1> >(tee -a "$BASHMIN_TLDR_DIR/install.log")
    exec 2> >(tee -a "$BASHMIN_TLDR_DIR/install.log" >&2)
    
    # Log installation start
    echo "TLDR installation started at $(date)"
    echo "Method: $INSTALL_METHOD, Languages: ${SELECTED_LANGUAGES[*]}"
    echo
    
    # Check if TLDR is already installed
    if command -v tldr >/dev/null 2>&1 && [[ "$FORCE" != true ]]; then
        print_warning "TLDR is already installed"
        print_info "Version: $(tldr --version 2>/dev/null || echo 'Unknown')"
        print_info "Use --force to reinstall"
        exit 0
    fi
    
    # Execute installation steps
    check_requirements
    create_system_structure
    install_tldr_client
    configure_tldr
    setup_completion
    setup_custom_pages
    update_cache
    setup_auto_updates
    create_management_script
    
    # Run tests
    if run_tests; then
        print_success "TLDR installation completed successfully!"
    else
        print_error "Installation completed with some issues"
    fi
    
    # Show summary
    if [[ "$QUIET" != true ]]; then
        show_summary
    fi
    
    echo "TLDR installation completed at $(date)"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
