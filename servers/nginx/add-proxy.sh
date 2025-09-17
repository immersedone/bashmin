#!/bin/bash
#
# Script: servers/nginx/add-proxy.sh
# Description: Generate Nginx proxy configuration with A/B testing capabilities
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
readonly DEFAULT_SSL_CERT_PATH="/etc/letsencrypt/live"

# Configuration variables
DOMAIN=""
AB_TEST_ENABLED=false
AB_SPLIT_PERCENTAGE=50
PRODUCTION_SERVERS=()
STAGING_SERVERS=()
CANARY_SERVERS=()
LOAD_BALANCING_METHOD="round_robin"
HEALTH_CHECK_ENABLED=true
SSL_CERT_PATH=""
SSL_KEY_PATH=""
CREATE_SSL_REDIRECT=true
ENABLE_WEBSOCKETS=false
ENABLE_STATIC_CACHING=true
MAX_BODY_SIZE="100M"
FORCE=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] DOMAIN

Create an Nginx proxy configuration with A/B testing capabilities.

ARGUMENTS:
    DOMAIN                      Domain name for the proxy (required)

OPTIONS:
    --production SERVERS        Comma-separated list of production backend servers
                               Format: ip:port or hostname:port
    --staging SERVERS          Comma-separated list of staging backend servers
    --canary SERVERS           Comma-separated list of canary backend servers
    --ab-test                  Enable A/B testing between production and staging
    --ab-split PERCENTAGE      A/B test split percentage for staging (default: 50)
    --load-balancing METHOD    Load balancing method: round_robin, least_conn,
                               ip_hash, hash, random (default: round_robin)
    --ssl-cert PATH            Custom SSL certificate path
    --ssl-key PATH             Custom SSL private key path
    --no-ssl-redirect          Don't redirect HTTP to HTTPS
    --enable-websockets        Enable WebSocket support
    --no-static-caching        Disable static file caching
    --max-body-size SIZE       Maximum request body size (default: 100M)
    --no-health-check          Disable health checking
    --force                    Overwrite existing configuration
    --quiet                    Suppress non-essential output
    --verbose                  Enable verbose output
    --dry-run                  Show what would be created without executing
    -h, --help                 Show this help message

LOAD BALANCING METHODS:
    round_robin                Default method, requests distributed evenly
    least_conn                 Route to server with least active connections
    ip_hash                    Route based on client IP hash (sticky sessions)
    hash                       Route based on custom key hash
    random                     Route requests randomly

A/B TESTING:
    When A/B testing is enabled, traffic is split between production and staging
    pools based on the specified percentage. The split is deterministic based
    on client IP or custom criteria.

EXAMPLES:
    # Basic proxy to single backend
    $0 api.local --production 127.0.0.1:8080

    # Load balanced proxy with multiple backends
    $0 app.local --production 127.0.0.1:8080,127.0.0.1:8081,127.0.0.1:8082

    # A/B testing between production and staging
    $0 test.local --production 127.0.0.1:8080 --staging 127.0.0.1:8090 --ab-test --ab-split 30

    # Advanced configuration with canary deployment
    $0 web.local --production 10.0.1.10:80,10.0.1.11:80 \\
                 --staging 10.0.2.10:80 \\
                 --canary 10.0.3.10:80 \\
                 --load-balancing least_conn \\
                 --enable-websockets

NOTES:
    - Requires sudo privileges
    - Automatically enables site configuration
    - Updates /etc/hosts with 127.0.0.1 entry
    - Creates SSL configuration if certificates exist
    - Includes health monitoring and failover

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --production)
            IFS=',' read -ra PRODUCTION_SERVERS <<< "$2"
            shift 2
            ;;
        --staging)
            IFS=',' read -ra STAGING_SERVERS <<< "$2"
            shift 2
            ;;
        --canary)
            IFS=',' read -ra CANARY_SERVERS <<< "$2"
            shift 2
            ;;
        --ab-test)
            AB_TEST_ENABLED=true
            shift
            ;;
        --ab-split)
            AB_SPLIT_PERCENTAGE="$2"
            AB_TEST_ENABLED=true
            shift 2
            ;;
        --load-balancing)
            LOAD_BALANCING_METHOD="$2"
            shift 2
            ;;
        --ssl-cert)
            SSL_CERT_PATH="$2"
            shift 2
            ;;
        --ssl-key)
            SSL_KEY_PATH="$2"
            shift 2
            ;;
        --no-ssl-redirect)
            CREATE_SSL_REDIRECT=false
            shift
            ;;
        --enable-websockets)
            ENABLE_WEBSOCKETS=true
            shift
            ;;
        --no-static-caching)
            ENABLE_STATIC_CACHING=false
            shift
            ;;
        --max-body-size)
            MAX_BODY_SIZE="$2"
            shift 2
            ;;
        --no-health-check)
            HEALTH_CHECK_ENABLED=false
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

# Function to validate domain and inputs
validate_inputs() {
    if [[ -z "$DOMAIN" ]]; then
        print_error "Domain name is required"
        show_help
        exit 1
    fi
    
    # Basic domain validation
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        print_error "Invalid domain name: $DOMAIN"
        exit 1
    fi
    
    # Check if at least production servers are specified
    if [[ ${#PRODUCTION_SERVERS[@]} -eq 0 ]]; then
        print_error "At least one production server must be specified"
        print_info "Use --production to specify backend servers"
        exit 1
    fi
    
    # Validate A/B split percentage
    if [[ "$AB_SPLIT_PERCENTAGE" -lt 0 || "$AB_SPLIT_PERCENTAGE" -gt 100 ]]; then
        print_error "A/B split percentage must be between 0 and 100"
        exit 1
    fi
    
    # If A/B testing is enabled, staging servers are required
    if [[ "$AB_TEST_ENABLED" == true && ${#STAGING_SERVERS[@]} -eq 0 ]]; then
        print_error "A/B testing requires staging servers"
        print_info "Use --staging to specify staging backend servers"
        exit 1
    fi
    
    # Set SSL paths if not specified
    if [[ -z "$SSL_CERT_PATH" ]]; then
        SSL_CERT_PATH="$DEFAULT_SSL_CERT_PATH/$DOMAIN/fullchain.pem"
    fi
    
    if [[ -z "$SSL_KEY_PATH" ]]; then
        SSL_KEY_PATH="$DEFAULT_SSL_CERT_PATH/$DOMAIN/privkey.pem"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Checking prerequisites..."
    fi
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. Please enter your password when prompted."
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges"
            exit 1
        fi
    fi
    
    # Check if Nginx is installed
    if ! command -v nginx >/dev/null 2>&1; then
        print_error "Nginx is not installed"
        print_info "Run the Nginx install script first: $PROJECT_ROOT/servers/nginx/install.sh"
        exit 1
    fi
    
    # Check if template exists
    if [[ ! -f "$PROXY_TEMPLATE" ]]; then
        print_error "Proxy template not found: $PROXY_TEMPLATE"
        exit 1
    fi
    
    # Check if site already exists
    local site_config="$NGINX_SITES_AVAILABLE/$DOMAIN.conf"
    if [[ -f "$site_config" && "$FORCE" == false ]]; then
        print_error "Site configuration already exists: $site_config"
        print_info "Use --force to overwrite existing configuration"
        exit 1
    fi
}

# Function to generate upstream pools
generate_upstream_pools() {
    local upstream_config=""
    
    # Production pool
    if [[ ${#PRODUCTION_SERVERS[@]} -gt 0 ]]; then
        upstream_config+="# Production Backend Pool\n"
        upstream_config+="upstream production_pool {\n"
        
        # Add load balancing method
        case "$LOAD_BALANCING_METHOD" in
            least_conn)
                upstream_config+="    least_conn;\n"
                ;;
            ip_hash)
                upstream_config+="    ip_hash;\n"
                ;;
            hash)
                upstream_config+="    hash \$remote_addr consistent;\n"
                ;;
            random)
                upstream_config+="    random;\n"
                ;;
        esac
        
        # Add servers
        for server in "${PRODUCTION_SERVERS[@]}"; do
            local health_check=""
            if [[ "$HEALTH_CHECK_ENABLED" == true ]]; then
                health_check=" max_fails=3 fail_timeout=30s"
            fi
            upstream_config+="    server $server$health_check;\n"
        done
        
        # Add keepalive connections
        upstream_config+="    keepalive 32;\n"
        upstream_config+="    keepalive_requests 100;\n"
        upstream_config+="    keepalive_timeout 60s;\n"
        upstream_config+="}\n\n"
    fi
    
    # Staging pool
    if [[ ${#STAGING_SERVERS[@]} -gt 0 ]]; then
        upstream_config+="# Staging Backend Pool\n"
        upstream_config+="upstream staging_pool {\n"
        
        # Add load balancing method
        case "$LOAD_BALANCING_METHOD" in
            least_conn)
                upstream_config+="    least_conn;\n"
                ;;
            ip_hash)
                upstream_config+="    ip_hash;\n"
                ;;
            hash)
                upstream_config+="    hash \$remote_addr consistent;\n"
                ;;
            random)
                upstream_config+="    random;\n"
                ;;
        esac
        
        # Add servers
        for server in "${STAGING_SERVERS[@]}"; do
            local health_check=""
            if [[ "$HEALTH_CHECK_ENABLED" == true ]]; then
                health_check=" max_fails=3 fail_timeout=30s"
            fi
            upstream_config+="    server $server$health_check;\n"
        done
        
        upstream_config+="    keepalive 32;\n"
        upstream_config+="}\n\n"
    fi
    
    # Canary pool
    if [[ ${#CANARY_SERVERS[@]} -gt 0 ]]; then
        upstream_config+="# Canary Backend Pool\n"
        upstream_config+="upstream canary_pool {\n"
        
        # Add servers
        for server in "${CANARY_SERVERS[@]}"; do
            local health_check=""
            if [[ "$HEALTH_CHECK_ENABLED" == true ]]; then
                health_check=" max_fails=3 fail_timeout=30s"
            fi
            upstream_config+="    server $server$health_check;\n"
        done
        
        upstream_config+="    keepalive 32;\n"
        upstream_config+="}\n\n"
    fi
    
    echo -e "$upstream_config"
}

# Function to generate A/B testing logic
generate_ab_logic() {
    if [[ "$AB_TEST_ENABLED" == false ]]; then
        echo "# A/B Testing: Disabled"
        return
    fi
    
    local ab_logic=""
    
    ab_logic+="# A/B Testing Configuration\n"
    ab_logic+="# Split: ${AB_SPLIT_PERCENTAGE}% to staging, $((100 - AB_SPLIT_PERCENTAGE))% to production\n\n"
    
    ab_logic+="# Generate consistent hash for A/B testing\n"
    ab_logic+="map \$remote_addr \$ab_test_bucket {\n"
    ab_logic+="    default 0;\n"
    ab_logic+="    ~(?P<ip>.*) \$ip;\n"
    ab_logic+="}\n\n"
    
    ab_logic+="# A/B test decision based on IP hash\n"
    ab_logic+="map \$ab_test_bucket \$backend_pool {\n"
    ab_logic+="    default production_pool;\n"
    
    # Calculate hash ranges for staging
    local staging_range=$((AB_SPLIT_PERCENTAGE * 256 / 100))
    for ((i=0; i<staging_range; i++)); do
        ab_logic+="    ~.*$i\$ staging_pool;\n"
    done
    
    ab_logic+="}\n\n"
    
    ab_logic+="# Add A/B test headers\n"
    ab_logic+="map \$backend_pool \$ab_test_variant {\n"
    ab_logic+="    production_pool 'A';\n"
    ab_logic+="    staging_pool 'B';\n"
    ab_logic+="    canary_pool 'C';\n"
    ab_logic+="    default 'A';\n"
    ab_logic+="}\n"
    
    echo -e "$ab_logic"
}

# Function to generate location logic
generate_location_logic() {
    local location_logic=""
    
    if [[ "$AB_TEST_ENABLED" == true ]]; then
        location_logic+="        # A/B Testing Logic\n"
        location_logic+="        set \$target_pool \$backend_pool;\n"
        location_logic+="        \n"
        location_logic+="        # Override for canary testing (admin users, special headers, etc.)\n"
        location_logic+="        if (\$http_x_canary_user = \"true\") {\n"
        location_logic+="            set \$target_pool canary_pool;\n"
        location_logic+="        }\n"
        location_logic+="        \n"
        location_logic+="        # Add A/B test information to response\n"
        location_logic+="        add_header X-AB-Test-Variant \$ab_test_variant always;\n"
        location_logic+="        add_header X-Backend-Pool \$target_pool always;\n"
        location_logic+="        \n"
        location_logic+="        # Proxy to selected pool\n"
        location_logic+="        proxy_pass http://\$target_pool;\n"
    else
        location_logic+="        # Direct proxy to production pool\n"
        location_logic+="        proxy_pass http://production_pool;\n"
    fi
    
    echo -e "$location_logic"
}

# Function to create proxy configuration
create_proxy_config() {
    local domain="$1"
    local site_config="$NGINX_SITES_AVAILABLE/$domain.conf"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would create proxy configuration: $site_config"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Creating proxy configuration: $site_config"
    fi
    
    # Generate configuration components
    local upstream_pools
    local ab_logic
    local location_logic
    
    upstream_pools=$(generate_upstream_pools)
    ab_logic=$(generate_ab_logic)
    location_logic=$(generate_location_logic)
    
    # Create configuration from template
    sudo cp "$PROXY_TEMPLATE" "$site_config"
    
    # Replace placeholders
    sudo sed -i "s|{DOMAIN_NAME}|$domain|g" "$site_config"
    sudo sed -i "s|{SSL_CERT_PATH}|$SSL_CERT_PATH|g" "$site_config"
    sudo sed -i "s|{SSL_KEY_PATH}|$SSL_KEY_PATH|g" "$site_config"
    
    # Replace multi-line blocks
    sudo sed -i "/{UPSTREAM_POOLS}/c\\$upstream_pools" "$site_config"
    sudo sed -i "/{AB_LOGIC}/c\\$ab_logic" "$site_config"
    sudo sed -i "/{AB_LOCATION_LOGIC}/c\\$location_logic" "$site_config"
    
    # Update client_max_body_size
    sudo sed -i "s|client_max_body_size 100M|client_max_body_size $MAX_BODY_SIZE|g" "$site_config"
    
    # Handle SSL redirect
    if [[ "$CREATE_SSL_REDIRECT" == false ]]; then
        sudo sed -i '/return 301 https:/d' "$site_config"
    fi
    
    # Remove WebSocket handling if not needed
    if [[ "$ENABLE_WEBSOCKETS" == false ]]; then
        sudo sed -i '/proxy_set_header Upgrade/d' "$site_config"
        sudo sed -i '/proxy_set_header Connection/d' "$site_config"
        sudo sed -i '/map.*connection_upgrade/,+3d' "$site_config"
    fi
    
    # Remove static caching if disabled
    if [[ "$ENABLE_STATIC_CACHING" == false ]]; then
        sudo sed -i '/location ~.*\.(css|js|png/,+10d' "$site_config"
        sudo sed -i '/location @proxy_static/,+7d' "$site_config"
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Proxy configuration created: $site_config"
    fi
}

# Function to enable site
enable_site() {
    local domain="$1"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would enable site: $domain"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Enabling site: $domain"
    fi
    
    if sudo nginx -t >/dev/null 2>&1; then
        sudo ln -sf "$NGINX_SITES_AVAILABLE/$domain.conf" "$NGINX_SITES_ENABLED/"
        sudo systemctl reload nginx
        
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_success "Site enabled and Nginx reloaded"
        fi
    else
        print_error "Nginx configuration test failed"
        sudo nginx -t 2>&1 | head -5
        exit 1
    fi
}

# Function to update hosts file
update_hosts_file() {
    local domain="$1"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would update /etc/hosts with: 127.0.0.1 $domain"
        return 0
    fi
    
    # Use bashmin hosts script if available
    if [[ -x "$PROJECT_ROOT/hosts/update-hosts.sh" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Updating /etc/hosts file..."
        fi
        
        "$PROJECT_ROOT/hosts/update-hosts.sh" --quiet add 127.0.0.1 "$domain" || true
    fi
}

# Function to show completion summary
show_completion_summary() {
    if [[ "$QUIET" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo
    print_success "Nginx proxy configuration created successfully! 🚀"
    echo
    print_info "=== Proxy Configuration Details ==="
    cat << EOF
Domain:              $DOMAIN
Production Servers:  ${PRODUCTION_SERVERS[*]}
$(if [[ ${#STAGING_SERVERS[@]} -gt 0 ]]; then echo "Staging Servers:     ${STAGING_SERVERS[*]}"; fi)
$(if [[ ${#CANARY_SERVERS[@]} -gt 0 ]]; then echo "Canary Servers:      ${CANARY_SERVERS[*]}"; fi)
Load Balancing:      $LOAD_BALANCING_METHOD
A/B Testing:         $(if [[ "$AB_TEST_ENABLED" == true ]]; then echo "Enabled (${AB_SPLIT_PERCENTAGE}% to staging)"; else echo "Disabled"; fi)
Health Checks:       $(if [[ "$HEALTH_CHECK_ENABLED" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
WebSockets:          $(if [[ "$ENABLE_WEBSOCKETS" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
Max Body Size:       $MAX_BODY_SIZE
Config File:         $NGINX_SITES_AVAILABLE/$DOMAIN.conf

EOF

    print_info "=== Testing URLs ==="
    cat << EOF
Main Site:           https://$DOMAIN
Health Check:        https://$DOMAIN/health
Nginx Status:        https://$DOMAIN/nginx_status (localhost only)

EOF

    if [[ "$AB_TEST_ENABLED" == true ]]; then
        print_info "=== A/B Testing ==="
        cat << EOF
Traffic Split:       ${AB_SPLIT_PERCENTAGE}% → Staging Pool, $((100 - AB_SPLIT_PERCENTAGE))% → Production Pool
Test Headers:        X-AB-Test-Variant (A/B/C), X-Backend-Pool
Canary Access:       Add header 'X-Canary-User: true' to access canary pool

EOF
    fi

    print_info "=== Management Commands ==="
    cat << EOF
View logs:           sudo tail -f /var/log/nginx/$DOMAIN-*.log
Test config:         sudo nginx -t
Reload config:       sudo systemctl reload nginx
Disable site:        sudo rm $NGINX_SITES_ENABLED/$DOMAIN.conf && sudo systemctl reload nginx

EOF

    print_info "=== Monitoring ==="
    cat << EOF
Check upstream:      curl -H "Host: $DOMAIN" http://localhost/health
Test A/B split:      for i in {1..10}; do curl -s -H "Host: $DOMAIN" http://localhost | grep -o 'X-AB-Test-Variant: .' || true; done
Backend status:      curl -I https://$DOMAIN (check X-Upstream-Server header)

EOF
    
    print_info "🎯 Your A/B testing proxy is ready!"
}

# Main function
main() {
    # Validate inputs
    validate_inputs
    
    if [[ "$QUIET" == false ]]; then
        show_script_header "Nginx A/B Testing Proxy Generator"
        print_info "Creating proxy configuration for: $DOMAIN"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show creation plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Proxy configuration plan:"
        print_info "  Domain: $DOMAIN"
        print_info "  Production Servers: ${PRODUCTION_SERVERS[*]}"
        [[ ${#STAGING_SERVERS[@]} -gt 0 ]] && print_info "  Staging Servers: ${STAGING_SERVERS[*]}"
        [[ ${#CANARY_SERVERS[@]} -gt 0 ]] && print_info "  Canary Servers: ${CANARY_SERVERS[*]}"
        print_info "  Load Balancing: $LOAD_BALANCING_METHOD"
        print_info "  A/B Testing: $AB_TEST_ENABLED"
        [[ "$AB_TEST_ENABLED" == true ]] && print_info "  A/B Split: $AB_SPLIT_PERCENTAGE%"
        print_info "  Health Checks: $HEALTH_CHECK_ENABLED"
        print_info "  WebSockets: $ENABLE_WEBSOCKETS"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with proxy creation?" "Y"; then
            print_info "Proxy creation cancelled"
            exit 0
        fi
    fi
    
    # Create proxy configuration
    create_proxy_config "$DOMAIN"
    
    # Enable the site
    enable_site "$DOMAIN"
    
    # Update hosts file
    update_hosts_file "$DOMAIN"
    
    # Show completion summary
    show_completion_summary
}

# Run main function
main "$@"
