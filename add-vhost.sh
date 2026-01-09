#!/bin/bash
#
# Script: add-vhost.sh
# Description: Generic virtual host creation script - creates nginx proxy to apache2 or frankenphp
# Usage: ./add-vhost.sh [OPTIONS] DOMAIN
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Configuration variables
DOMAIN=""
BACKEND=""  # apache2 or frankenphp
PROJECT_DIR=""
PHP_VERSION=""
ENABLE_SSL=true
FORCE=false
VERBOSE=false
DRY_RUN=false

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] DOMAIN

Generic virtual host creation - sets up nginx reverse proxy to apache2 or frankenphp.

ARGUMENTS:
    DOMAIN                  Domain name for the virtual host (required)

OPTIONS:
    -d, --domain DOMAIN     Domain name (alternative to positional arg)
    -b, --backend TYPE      Backend server type: apache2, frankenphp
    -p, --project-dir PATH  Project directory path (default: /var/www/vhosts/DOMAIN)
    --php-version VERSION   PHP version to use (auto-detected if not specified)
    --no-ssl                Disable SSL/TLS
    --force                 Force creation even if vhost exists
    --verbose               Enable verbose output
    --dry-run               Show what would be done without executing
    -h, --help              Show this help message

WORKFLOW:
    1. Prompts for backend selection (apache2 or frankenphp) if not specified
    2. Prompts for project directory if not specified
    3. Prompts for PHP version selection from installed versions
    4. Creates backend virtual host configuration
    5. Creates nginx reverse proxy configuration
    6. Updates /etc/hosts file
    7. Reloads services

EXAMPLES:
    $0 example.com                                  # Interactive mode
    $0 -b apache2 example.com                       # Apache2 backend
    $0 -b frankenphp -p /var/www/myapp example.com  # Custom path
    $0 --backend apache2 --php-version 8.4 api.com  # Specific PHP version
    $0 --dry-run --verbose test.com                 # Preview changes

NOTES:
    - Requires sudo privileges
    - Nginx must be installed for proxy
    - Backend server (apache2 or frankenphp) must be installed
    - Creates full stack: backend + nginx proxy + SSL
    - Automatically detects available PHP versions

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -b|--backend)
            BACKEND="$2"
            shift 2
            ;;
        -p|--project-dir)
            PROJECT_DIR="$2"
            shift 2
            ;;
        --php-version)
            PHP_VERSION="$2"
            shift 2
            ;;
        --no-ssl)
            ENABLE_SSL=false
            shift
            ;;
        --force)
            FORCE=true
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
        -*)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            # Positional argument (domain)
            if [[ -z "$DOMAIN" ]]; then
                DOMAIN="$1"
            else
                print_error "Multiple domains specified: $DOMAIN, $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Function to validate domain name
validate_domain() {
    if [[ -z "$DOMAIN" ]]; then
        print_error "No domain specified"
        show_help
        exit 1
    fi
    
    # Basic domain validation
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$ ]]; then
        print_error "Invalid domain name: $DOMAIN"
        exit 1
    fi
    
    print_success "Domain validation passed: $DOMAIN"
}

# Function to detect installed backend servers
detect_backends() {
    local backends=()
    
    if systemctl list-unit-files | grep -q "apache2.service"; then
        backends+=("apache2")
    fi
    
    if systemctl list-unit-files | grep -q "frankenphp.service"; then
        backends+=("frankenphp")
    fi
    
    echo "${backends[@]}"
}

# Function to prompt for backend selection
prompt_backend() {
    local available_backends=($(detect_backends))
    
    if [[ ${#available_backends[@]} -eq 0 ]]; then
        print_error "No backend servers detected (apache2 or frankenphp)"
        print_info "Install apache2: $PROJECT_ROOT/servers/apache2/install.sh"
        print_info "Install frankenphp: $PROJECT_ROOT/servers/frankenphp/install.sh"
        exit 1
    fi
    
    if [[ ${#available_backends[@]} -eq 1 ]]; then
        echo "${available_backends[0]}"
        return
    fi
    
    echo
    print_info "Available backend servers:"
    local i=1
    for backend in "${available_backends[@]}"; do
        echo "  $i) $backend"
        ((i++))
    done
    echo
    
    read -p "Select backend server [1-${#available_backends[@]}]: " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#available_backends[@]} ]]; then
        echo "${available_backends[$((selection-1))]}"
    else
        print_error "Invalid selection"
        exit 1
    fi
}

# Function to prompt for project directory
prompt_project_dir() {
    local default_dir="/var/www/vhosts/$DOMAIN"
    
    echo
    print_info "Project directory configuration"
    read -p "Enter project directory path (default: $default_dir): " input_dir
    
    if [[ -z "$input_dir" ]]; then
        echo "$default_dir"
    else
        # Expand tilde and resolve path
        input_dir="${input_dir/#\~/$HOME}"
        echo "$input_dir"
    fi
}

# Function to get backend port
get_backend_port() {
    local backend="$1"
    
    case "$backend" in
        apache2)
            echo "8080"
            ;;
        frankenphp)
            echo "8100"
            ;;
        *)
            echo "8080"
            ;;
    esac
}

# Function to create backend vhost
create_backend_vhost() {
    local backend="$1"
    
    print_info "Creating $backend virtual host configuration..."
    
    local backend_script="$PROJECT_ROOT/servers/$backend/add-vhost.sh"
    
    if [[ ! -x "$backend_script" ]]; then
        print_error "Backend script not found or not executable: $backend_script"
        exit 1
    fi
    
    local cmd="$backend_script"
    
    # Add common options
    if [[ -n "$PROJECT_DIR" ]]; then
        if [[ "$backend" == "apache2" ]]; then
            # Apache2 expects the webroot to be the public directory
            cmd="$cmd --webroot $PROJECT_DIR/public"
        else
            # FrankenPHP expects the base directory (it adds /public itself)
            cmd="$cmd --root $PROJECT_DIR"
        fi
    fi
    
    if [[ -n "$PHP_VERSION" ]]; then
        cmd="$cmd --php-version $PHP_VERSION"
    fi
    
    if [[ "$ENABLE_SSL" == false ]]; then
        cmd="$cmd --no-ssl"
    fi
    
    if [[ "$FORCE" == true ]]; then
        cmd="$cmd --force"
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        cmd="$cmd --verbose"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        cmd="$cmd --dry-run"
    fi
    
    # Add backend-specific options
    case "$backend" in
        apache2)
            local port=$(get_backend_port "$backend")
            cmd="$cmd --port $port --no-hosts"
            ;;
        frankenphp)
            cmd="$cmd --http-port 8100"
            ;;
    esac
    
    cmd="$cmd $DOMAIN"
    
    if [[ "$VERBOSE" == true ]]; then
        print_info "Running: $cmd"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would run: $cmd"
    else
        if ! eval "$cmd"; then
            print_error "Failed to create $backend virtual host"
            exit 1
        fi
    fi
    
    print_success "$backend virtual host created"
}

# Function to create nginx proxy
create_nginx_proxy() {
    local backend="$1"
    local backend_port=$(get_backend_port "$backend")
    
    print_info "Creating nginx reverse proxy configuration..."
    
    local nginx_script="$PROJECT_ROOT/servers/nginx/add-proxy.sh"
    
    if [[ ! -x "$nginx_script" ]]; then
        print_error "Nginx proxy script not found: $nginx_script"
        exit 1
    fi
    
    local cmd="$nginx_script"
    cmd="$cmd --backend $backend"
    cmd="$cmd --backend-port $backend_port"
    
    if [[ "$ENABLE_SSL" == false ]]; then
        cmd="$cmd --no-ssl"
    fi
    
    if [[ "$FORCE" == true ]]; then
        cmd="$cmd --force"
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        cmd="$cmd --verbose"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        cmd="$cmd --dry-run"
    fi
    
    cmd="$cmd $DOMAIN"
    
    if [[ "$VERBOSE" == true ]]; then
        print_info "Running: $cmd"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would run: $cmd"
    else
        if ! eval "$cmd"; then
            print_error "Failed to create nginx proxy"
            exit 1
        fi
    fi
    
    print_success "Nginx reverse proxy created"
}

# Function to show post-creation summary
show_summary() {
    echo
    print_info "=== Virtual Host Stack Created Successfully! ==="
    echo
    cat << EOF
Configuration Summary:
  Domain:          $DOMAIN
  Backend:         $BACKEND
  Project Dir:     $PROJECT_DIR
  PHP Version:     ${PHP_VERSION:-auto-detected}
  SSL Enabled:     $(if [[ "$ENABLE_SSL" == true ]]; then echo "Yes"; else echo "No"; fi)
  
Architecture:
  Internet → Nginx (80/443) → $BACKEND ($(get_backend_port $BACKEND)) → PHP-FPM

Quick Commands:
  Test site:       curl http://$DOMAIN
$(if [[ "$ENABLE_SSL" == true ]]; then echo "  Test SSL:        curl https://$DOMAIN"; fi)
  View nginx logs: sudo tail -f /var/log/nginx/$DOMAIN-*.log
  View backend:    sudo journalctl -u $BACKEND -f
  Edit project:    cd $PROJECT_DIR

Management:
  Restart nginx:   sudo systemctl restart nginx
  Restart backend: sudo systemctl restart $BACKEND
  Test nginx:      sudo nginx -t
  Disable site:    sudo rm /etc/nginx/sites-enabled/$DOMAIN

Next Steps:
1. Upload your application files to $PROJECT_DIR/public/
2. Configure your database connection
3. Point DNS A record for $DOMAIN to this server's IP
4. Test your site: http$(if [[ "$ENABLE_SSL" == true ]]; then echo "s"; fi)://$DOMAIN

EOF
    
    print_success "Virtual host stack setup completed! 🚀"
}

# Main function
main() {
    show_script_header "Generic Virtual Host Creator"
    
    # Validate domain
    validate_domain
    
    # Check prerequisites
    if ! command -v nginx &> /dev/null; then
        print_error "Nginx is not installed"
        print_info "Install with: $PROJECT_ROOT/servers/nginx/install.sh"
        exit 1
    fi
    
    # Prompt for backend if not specified
    if [[ -z "$BACKEND" ]]; then
        BACKEND=$(prompt_backend)
        print_success "Selected backend: $BACKEND"
    fi
    
    # Validate backend
    local available_backends=($(detect_backends))
    if [[ ! " ${available_backends[@]} " =~ " ${BACKEND} " ]]; then
        print_error "Backend server not available: $BACKEND"
        print_info "Available backends: ${available_backends[*]}"
        exit 1
    fi
    
    # Prompt for project directory if not specified
    if [[ -z "$PROJECT_DIR" ]]; then
        PROJECT_DIR=$(prompt_project_dir)
        print_success "Project directory: $PROJECT_DIR"
    fi
    
    # Show configuration summary
    echo
    print_info "=== Virtual Host Configuration ==="
    print_info "Domain: $DOMAIN"
    print_info "Backend: $BACKEND"
    print_info "Project Directory: $PROJECT_DIR"
    print_info "PHP Version: ${PHP_VERSION:-auto-detect}"
    print_info "SSL Enabled: $(if [[ "$ENABLE_SSL" == true ]]; then echo "Yes"; else echo "No"; fi)"
    
    if ! confirm_action "Create virtual host with these settings?" "Y"; then
        print_info "Virtual host creation cancelled"
        exit 0
    fi
    
    # Create backend virtual host
    create_backend_vhost "$BACKEND"
    
    # Create nginx proxy
    create_nginx_proxy "$BACKEND"
    
    # Show summary
    show_summary
}

# Run main function
main "$@"
