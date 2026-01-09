#!/bin/bash
#
# Script: servers/nginx/add-proxy.sh
# Description: Add reverse proxy configuration for Nginx
# Usage: ./add-proxy.sh [OPTIONS] DOMAIN
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/cli.sh"

# Constants
readonly NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
readonly NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
readonly PROXY_TEMPLATE="$SCRIPT_DIR/proxy.config.example"
readonly VHOST_TEMPLATE="$SCRIPT_DIR/vhost.config.example"

# Configuration variables
DOMAIN=""
BACKEND_TYPE=""  # apache2, frankenphp, custom
BACKEND_HOST="127.0.0.1"
BACKEND_PORT=""
ENABLE_SSL=true
SSL_CERT_PATH="/etc/letsencrypt/live"
SSL_EMAIL=""
ENABLE_AB_TESTING=false
AB_SPLIT_PERCENT=50
PRODUCTION_POOL=""
STAGING_POOL=""
CANARY_POOL=""
LOAD_BALANCE_METHOD="least_conn"  # round_robin, least_conn, ip_hash
UPDATE_HOSTS=true
FORCE=false
VERBOSE=false
DRY_RUN=false
QUIET=false
TEMPLATE_MODE="simple"  # simple or advanced

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -b|--backend)
            BACKEND_TYPE="$2"
            shift 2
            ;;
        --backend-host)
            BACKEND_HOST="$2"
            shift 2
            ;;
        --backend-port)
            BACKEND_PORT="$2"
            shift 2
            ;;
        --no-ssl)
            ENABLE_SSL=false
            shift
            ;;
        --ssl-email)
            SSL_EMAIL="$2"
            ENABLE_SSL=true
            shift 2
            ;;
        --ab-testing)
            ENABLE_AB_TESTING=true
            TEMPLATE_MODE="advanced"
            shift
            ;;
        --ab-split)
            AB_SPLIT_PERCENT="$2"
            ENABLE_AB_TESTING=true
            TEMPLATE_MODE="advanced"
            shift 2
            ;;
        --production-pool)
            PRODUCTION_POOL="$2"
            TEMPLATE_MODE="advanced"
            shift 2
            ;;
        --staging-pool)
            STAGING_POOL="$2"
            TEMPLATE_MODE="advanced"
            shift 2
            ;;
        --canary-pool)
            CANARY_POOL="$2"
            TEMPLATE_MODE="advanced"
            shift 2
            ;;
        --load-balance)
            LOAD_BALANCE_METHOD="$2"
            shift 2
            ;;
        --no-hosts)
            UPDATE_HOSTS=false
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
        -*)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$DOMAIN" ]]; then
                DOMAIN="$1"
            else
                print_error "Multiple domains specified: $DOMAIN and $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Function to show help
show_help() {
    cat << 'EOF'
Usage: ./add-proxy.sh [OPTIONS] DOMAIN

Add reverse proxy configuration for Nginx to proxy requests to backend servers
(Apache2 or FrankenPHP).

ARGUMENTS:
    DOMAIN                  Domain name for the proxy (required)

OPTIONS:
    -d, --domain DOMAIN         Domain name (alternative to positional arg)
    -b, --backend TYPE          Backend type: apache2, frankenphp, custom
    --backend-host HOST         Backend host (default: 127.0.0.1)
    --backend-port PORT         Backend port (auto-detected if not specified)
    --no-ssl                    Disable SSL/TLS configuration
    --ssl-email EMAIL           Email for Let's Encrypt SSL certificate
    --ab-testing                Enable A/B testing with multiple backend pools
    --ab-split PERCENT          A/B testing split percentage (default: 50)
    --production-pool SERVERS   Production pool servers (comma-separated)
    --staging-pool SERVERS      Staging pool servers (comma-separated)
    --canary-pool SERVERS       Canary pool servers (comma-separated)
    --load-balance METHOD       Load balancing: round_robin, least_conn, ip_hash
    --no-hosts                  Don't update /etc/hosts file
    --force                     Overwrite existing configuration
    --quiet                     Suppress non-essential output
    --verbose                   Enable verbose output
    --dry-run                   Show what would be created without executing
    -h, --help                  Show this help message

BACKEND TYPES:
    apache2                 Proxy to Apache2 (ports 8080-8082)
    frankenphp              Proxy to FrankenPHP (ports 8100-8199)
    custom                  Custom backend (requires --backend-port)

EXAMPLES:
    # Simple proxy to Apache2 on default port 8080
    ./add-proxy.sh example.local --backend apache2

    # Proxy to FrankenPHP on port 8100
    ./add-proxy.sh app.local --backend frankenphp --backend-port 8100

    # Custom backend with specific port
    ./add-proxy.sh api.local --backend custom --backend-port 3000

    # A/B testing with production and staging pools
    ./add-proxy.sh test.local --backend apache2 \
        --ab-testing --ab-split 80 \
        --production-pool "127.0.0.1:8080,127.0.0.1:8081" \
        --staging-pool "127.0.0.1:8082"

    # Advanced load balancing
    ./add-proxy.sh balanced.local --backend frankenphp \
        --production-pool "127.0.0.1:8100,127.0.0.1:8101,127.0.0.1:8102" \
        --load-balance least_conn

    # Without SSL
    ./add-proxy.sh dev.local --backend apache2 --no-ssl

NOTES:
    - Requires sudo privileges and Nginx to be installed
    - Creates reverse proxy with modern security headers
    - Supports WebSocket connections
    - Includes rate limiting and DDoS protection
    - SSL certificates must exist or use --no-ssl for development
    - To remove proxy: sudo rm /etc/nginx/sites-{available,enabled}/DOMAIN.conf

DEFAULT PORTS:
    Apache2:    8080 (PHP 8.5), 8081 (PHP 8.4), 8082 (PHP 8.3)
    FrankenPHP: 8100-8199 (HTTP), 8443-8543 (HTTPS)

EOF
}

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
        print_info "Domain must contain only letters, numbers, hyphens, and dots"
        exit 1
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Domain validation passed: $DOMAIN"
    fi
}

# Function to detect or validate backend configuration
setup_backend_config() {
    # Auto-detect backend port if not specified
    if [[ -z "$BACKEND_PORT" ]]; then
        case "$BACKEND_TYPE" in
            apache2)
                BACKEND_PORT=8080
                print_info "Using default Apache2 port: $BACKEND_PORT"
                ;;
            frankenphp)
                BACKEND_PORT=8100
                print_info "Using default FrankenPHP port: $BACKEND_PORT"
                ;;
            custom)
                print_error "Backend port required for custom backend type"
                print_info "Use --backend-port PORT"
                exit 1
                ;;
            *)
                print_error "Unknown backend type: $BACKEND_TYPE"
                print_info "Valid types: apache2, frankenphp, custom"
                exit 1
                ;;
        esac
    fi
    
    # Validate backend port
    if [[ ! "$BACKEND_PORT" =~ ^[0-9]+$ ]] || [[ "$BACKEND_PORT" -lt 1 ]] || [[ "$BACKEND_PORT" -gt 65535 ]]; then
        print_error "Invalid backend port: $BACKEND_PORT"
        exit 1
    fi
    
    # Warn if backend port doesn't match expected ranges
    if [[ "$BACKEND_TYPE" == "apache2" ]] && [[ ! "$BACKEND_PORT" =~ ^808[0-2]$ ]]; then
        print_warning "Apache2 typically uses ports 8080-8082"
    fi
    
    if [[ "$BACKEND_TYPE" == "frankenphp" ]] && [[ ! "$BACKEND_PORT" =~ ^81[0-9]{2}$ ]]; then
        print_warning "FrankenPHP typically uses ports 8100-8199"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Backend configuration: $BACKEND_TYPE at $BACKEND_HOST:$BACKEND_PORT"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Checking prerequisites..."
    fi
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root"
    elif ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. Please enter your password when prompted."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges"
            exit 1
        fi
    fi
    
    # Check if Nginx is installed
    if ! command -v nginx &> /dev/null; then
        print_error "Nginx is not installed"
        print_info "Install with: sudo apt install nginx"
        exit 1
    fi
    
    # Check if sites directories exist
    if [[ ! -d "$NGINX_SITES_AVAILABLE" ]]; then
        print_error "Nginx sites-available directory not found: $NGINX_SITES_AVAILABLE"
        exit 1
    fi
    
    if [[ ! -d "$NGINX_SITES_ENABLED" ]]; then
        execute_command "sudo mkdir -p '$NGINX_SITES_ENABLED'" "Creating sites-enabled directory"
    fi
    
    # Check if template exists (for simple mode)
    if [[ "$TEMPLATE_MODE" == "simple" && ! -f "$VHOST_TEMPLATE" ]]; then
        print_warning "Vhost template not found, will use inline configuration"
    fi
    
    # Check if advanced template exists (for A/B testing)
    if [[ "$TEMPLATE_MODE" == "advanced" && ! -f "$PROXY_TEMPLATE" ]]; then
        print_warning "Proxy template not found, will use inline configuration"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Prerequisites check completed"
    fi
}

# Function to check if site already exists
check_existing_site() {
    local site_config="$NGINX_SITES_AVAILABLE/$DOMAIN.conf"
    
    if [[ -f "$site_config" && "$FORCE" == false ]]; then
        print_error "Site configuration already exists: $site_config"
        print_info "Use --force to overwrite"
        exit 1
    fi
}

# Function to setup SSL paths
setup_ssl_config() {
    if [[ "$ENABLE_SSL" == true ]]; then
        SSL_CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        SSL_KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
        
        # Check if SSL certificates exist
        if [[ ! -f "$SSL_CERT_PATH" || ! -f "$SSL_KEY_PATH" ]]; then
            print_warning "SSL certificates not found for $DOMAIN"
            print_info "Certificate path: $SSL_CERT_PATH"
            print_info "Run certbot or use --no-ssl for development"
            
            if ! confirm_action "Continue without SSL?"; then
                exit 1
            fi
            ENABLE_SSL=false
        fi
    fi
}

# Function to generate simple proxy configuration
generate_simple_proxy_config() {
    local site_config="$NGINX_SITES_AVAILABLE/$DOMAIN.conf"
    
    print_info "Generating simple proxy configuration..."
    
    local ssl_server_block=""
    if [[ "$ENABLE_SSL" == true ]]; then
        ssl_server_block=$(cat <<'SSLBLOCK'

#### --- HTTPS: Port 443 Block --- ####
server {
    # Port Listeners
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    # Server Names/Aliases
    server_name {DOMAIN_NAME};

    # SSL Configuration
    ssl_certificate {SSL_CERT_PATH};
    ssl_certificate_key {SSL_KEY_PATH};
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE+AESGCM:ECDHE+AES256:ECDHE+AES128:!aNULL:!MD5:!DSS;
    ssl_prefer_server_ciphers off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Rate Limiting (requires rate limit zone in nginx.conf)
    # limit_req zone=borderforce burst=300 nodelay;

    # Location Block
    location / {
        # Proxy Configuration
        proxy_http_version 1.1;
        proxy_buffering off;
        chunked_transfer_encoding off;

        # Timeouts
        proxy_connect_timeout 300;
        proxy_send_timeout 100;
        proxy_read_timeout 100;

        # Upload Configuration
        client_max_body_size 512M;
        client_body_buffer_size 128M;

        # Proxy Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # WebSocket Support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # Proxy Pass
        proxy_pass http://{BACKEND_HOST}:{BACKEND_PORT};
    }

    # Logging
    access_log /var/log/nginx/{DOMAIN_NAME}-access.log combined;
    error_log /var/log/nginx/{DOMAIN_NAME}-error.log warn;
}
#### --- END HTTPS: Port 443 Block --- ####

# WebSocket upgrade handling
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
SSLBLOCK
)
    fi
    
    local http_redirect=""
    if [[ "$ENABLE_SSL" == true ]]; then
        http_redirect="return 301 https://\$host\$request_uri;"
    else
        http_redirect=$(cat <<'HTTPBLOCK'

        # Proxy Configuration
        proxy_http_version 1.1;
        proxy_buffering off;
        chunked_transfer_encoding off;

        # Timeouts
        proxy_connect_timeout 300;
        proxy_send_timeout 100;
        proxy_read_timeout 100;

        # Upload Configuration
        client_max_body_size 512M;
        client_body_buffer_size 128M;

        # Proxy Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # WebSocket Support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # Proxy Pass
        proxy_pass http://{BACKEND_HOST}:{BACKEND_PORT};
HTTPBLOCK
)
    fi
    
    # Generate configuration
    execute_command "sudo tee '$site_config' > /dev/null" "Creating proxy configuration" <<EOF
#####
#
#   File: $site_config
#   Domain: $DOMAIN
#   Backend: $BACKEND_TYPE ($BACKEND_HOST:$BACKEND_PORT)
#   Created: $(date)
#   Type: Reverse Proxy (Simple)
#
##

#### --- HTTP: Port 80 Block --- ####
server {
    # Port Listeners
    listen 80;
    listen [::]:80;

    # Server Names/Aliases
    server_name $DOMAIN;

    # Location Block
    location / {
        $http_redirect
    }
}
#### --- END HTTP: Port 80 Block --- ####
$ssl_server_block
EOF
    
    # Replace placeholders
    sudo sed -i "s|{DOMAIN_NAME}|$DOMAIN|g" "$site_config"
    sudo sed -i "s|{BACKEND_HOST}|$BACKEND_HOST|g" "$site_config"
    sudo sed -i "s|{BACKEND_PORT}|$BACKEND_PORT|g" "$site_config"
    sudo sed -i "s|{SSL_CERT_PATH}|$SSL_CERT_PATH|g" "$site_config"
    sudo sed -i "s|{SSL_KEY_PATH}|$SSL_KEY_PATH|g" "$site_config"
    
    print_success "Proxy configuration created: $site_config"
}

# Function to generate advanced proxy configuration with A/B testing
generate_advanced_proxy_config() {
    local site_config="$NGINX_SITES_AVAILABLE/$DOMAIN.conf"
    
    print_info "Generating advanced proxy configuration with A/B testing..."
    
    # Parse pool configurations
    local upstream_pools=""
    local ab_logic=""
    local ab_location_logic=""
    
    # Production pool
    if [[ -n "$PRODUCTION_POOL" ]]; then
        upstream_pools+="upstream production_pool {\n"
        upstream_pools+="    $LOAD_BALANCE_METHOD;\n"
        IFS=',' read -ra SERVERS <<< "$PRODUCTION_POOL"
        for server in "${SERVERS[@]}"; do
            upstream_pools+="    server $server max_fails=3 fail_timeout=30s;\n"
        done
        upstream_pools+="    keepalive 32;\n"
        upstream_pools+="}\n\n"
    else
        upstream_pools+="upstream production_pool {\n"
        upstream_pools+="    server $BACKEND_HOST:$BACKEND_PORT max_fails=3 fail_timeout=30s;\n"
        upstream_pools+="    keepalive 32;\n"
        upstream_pools+="}\n\n"
    fi
    
    # Staging pool
    if [[ -n "$STAGING_POOL" ]]; then
        upstream_pools+="upstream staging_pool {\n"
        upstream_pools+="    $LOAD_BALANCE_METHOD;\n"
        IFS=',' read -ra SERVERS <<< "$STAGING_POOL"
        for server in "${SERVERS[@]}"; do
            upstream_pools+="    server $server max_fails=3 fail_timeout=30s;\n"
        done
        upstream_pools+="    keepalive 32;\n"
        upstream_pools+="}\n\n"
    fi
    
    # Canary pool
    if [[ -n "$CANARY_POOL" ]]; then
        upstream_pools+="upstream canary_pool {\n"
        upstream_pools+="    $LOAD_BALANCE_METHOD;\n"
        IFS=',' read -ra SERVERS <<< "$CANARY_POOL"
        for server in "${SERVERS[@]}"; do
            upstream_pools+="    server $server max_fails=3 fail_timeout=30s;\n"
        done
        upstream_pools+="    keepalive 32;\n"
        upstream_pools+="}\n\n"
    fi
    
    # A/B testing logic
    if [[ "$ENABLE_AB_TESTING" == true ]]; then
        ab_logic+="# A/B Testing Split Logic\n"
        ab_logic+="split_clients \"\${remote_addr}\${http_user_agent}\" \$backend_pool {\n"
        ab_logic+="    $AB_SPLIT_PERCENT% production_pool;\n"
        
        if [[ -n "$STAGING_POOL" ]]; then
            local staging_percent=$((100 - AB_SPLIT_PERCENT))
            ab_logic+="    $staging_percent% staging_pool;\n"
        elif [[ -n "$CANARY_POOL" ]]; then
            local canary_percent=$((100 - AB_SPLIT_PERCENT))
            ab_logic+="    $canary_percent% canary_pool;\n"
        fi
        
        ab_logic+="}\n"
        
        ab_location_logic="proxy_pass http://\$backend_pool;"
    else
        ab_location_logic="proxy_pass http://production_pool;"
    fi
    
    # Use template if available, otherwise inline
    if [[ -f "$PROXY_TEMPLATE" ]]; then
        execute_command "sudo cp '$PROXY_TEMPLATE' '$site_config'" "Copying proxy template"
        
        # Replace placeholders
        sudo sed -i "s|{DOMAIN_NAME}|$DOMAIN|g" "$site_config"
        sudo sed -i "s|{SSL_CERT_PATH}|$SSL_CERT_PATH|g" "$site_config"
        sudo sed -i "s|{SSL_KEY_PATH}|$SSL_KEY_PATH|g" "$site_config"
        
        # Replace upstream pools
        sudo sed -i "/{UPSTREAM_POOLS}/c\\$upstream_pools" "$site_config"
        
        # Replace A/B logic
        if [[ -n "$ab_logic" ]]; then
            sudo sed -i "/{AB_LOGIC}/c\\$ab_logic" "$site_config"
        else
            sudo sed -i "/{AB_LOGIC}/d" "$site_config"
        fi
        
        # Replace location logic
        sudo sed -i "s|{AB_LOCATION_LOGIC}|$ab_location_logic|g" "$site_config"
    else
        print_warning "Advanced template not available, using simple configuration"
        generate_simple_proxy_config
        return
    fi
    
    print_success "Advanced proxy configuration created: $site_config"
}

# Function to enable site
enable_site() {
    local site_config="$NGINX_SITES_AVAILABLE/$DOMAIN.conf"
    local site_link="$NGINX_SITES_ENABLED/$DOMAIN.conf"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would enable site: $DOMAIN"
        return 0
    fi
    
    # Create symbolic link
    if [[ -L "$site_link" ]]; then
        execute_command "sudo rm '$site_link'" "Removing old symbolic link"
    fi
    
    execute_command "sudo ln -s '$site_config' '$site_link'" "Enabling site"
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Site enabled: $DOMAIN"
    fi
}

# Function to test nginx configuration
test_nginx_config() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would test Nginx configuration"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Testing Nginx configuration..."
    fi
    
    if sudo nginx -t 2>&1 | grep -q "successful"; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Nginx configuration test passed"
        fi
    else
        print_error "Nginx configuration test failed"
        sudo nginx -t
        exit 1
    fi
}

# Function to reload nginx
reload_nginx() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would reload Nginx"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Reloading Nginx..."
    fi
    
    execute_command "sudo systemctl reload nginx" "Reloading Nginx service"
    
    if [[ "$QUIET" == false ]]; then
        print_success "Nginx reloaded successfully"
    fi
}

# Function to update hosts file
update_hosts_file() {
    if [[ "$UPDATE_HOSTS" == false ]]; then
        return 0
    fi
    
    if [[ -x "$PROJECT_ROOT/hosts/update-hosts.sh" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY-RUN] Would update /etc/hosts with: 127.0.0.1 $DOMAIN"
        else
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_info "Updating /etc/hosts file..."
            fi
            "$PROJECT_ROOT/hosts/update-hosts.sh" --quiet add 127.0.0.1 "$DOMAIN"
        fi
    else
        print_warning "Hosts update script not found, skipping hosts file update"
    fi
}

# Function to display summary
display_summary() {
    if [[ "$QUIET" == true ]]; then
        return 0
    fi
    
    echo ""
    print_success "═══════════════════════════════════════════════════════════"
    print_success "  Nginx Reverse Proxy Configuration Complete"
    print_success "═══════════════════════════════════════════════════════════"
    echo ""
    echo "  Domain:        $DOMAIN"
    echo "  Backend:       $BACKEND_TYPE ($BACKEND_HOST:$BACKEND_PORT)"
    echo "  SSL:           $(if [[ "$ENABLE_SSL" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    if [[ "$ENABLE_AB_TESTING" == true ]]; then
        echo "  A/B Testing:   Enabled ($AB_SPLIT_PERCENT% split)"
    fi
    echo "  Config File:   $NGINX_SITES_AVAILABLE/$DOMAIN.conf"
    echo ""
    echo "  Access URLs:"
    echo "    HTTP:  http://$DOMAIN"
    if [[ "$ENABLE_SSL" == true ]]; then
        echo "    HTTPS: https://$DOMAIN"
    fi
    echo ""
    echo "  Useful Commands:"
    echo "    Test config:   sudo nginx -t"
    echo "    Reload Nginx:  sudo systemctl reload nginx"
    echo "    View logs:     sudo tail -f /var/log/nginx/$DOMAIN-*.log"
    echo "    Disable site:  sudo rm $NGINX_SITES_ENABLED/$DOMAIN.conf && sudo systemctl reload nginx"
    echo ""
    print_success "═══════════════════════════════════════════════════════════"
}

# Main execution
main() {
    # Validate inputs
    validate_domain
    
    # Check if backend type is specified
    if [[ -z "$BACKEND_TYPE" ]]; then
        print_error "Backend type is required"
        print_info "Use -b or --backend with: apache2, frankenphp, or custom"
        show_help
        exit 1
    fi
    
    # Setup backend configuration
    setup_backend_config
    
    # Check prerequisites
    check_prerequisites
    
    # Check for existing site
    check_existing_site
    
    # Setup SSL configuration
    setup_ssl_config
    
    # Generate configuration based on mode
    if [[ "$TEMPLATE_MODE" == "advanced" ]]; then
        generate_advanced_proxy_config
    else
        generate_simple_proxy_config
    fi
    
    # Enable site
    enable_site
    
    # Test nginx configuration
    test_nginx_config
    
    # Reload nginx
    reload_nginx
    
    # Update hosts file
    update_hosts_file
    
    # Display summary
    display_summary
}

# Run main function
main
