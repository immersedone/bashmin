#!/bin/bash
#
# Script: servers/elasticsearch/install.sh
# Description: Install and configure Elasticsearch with bashmin integration
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
readonly DEFAULT_ES_VERSION="8.15.0"
readonly ES_USER="elasticsearch"
readonly ES_GROUP="elasticsearch"
readonly ES_HOME="/usr/share/elasticsearch"
readonly ES_CONF_DIR="/etc/elasticsearch"
readonly ES_DATA_DIR="/var/lib/elasticsearch"
readonly ES_LOG_DIR="/var/log/elasticsearch"
readonly ES_WORK_DIR="/tmp/elasticsearch"
readonly ES_SERVICE="elasticsearch"
readonly ES_CONFIG_FILE="$ES_CONF_DIR/elasticsearch.yml"
readonly ES_JVM_OPTIONS="$ES_CONF_DIR/jvm.options"
readonly ES_LOG4J_CONFIG="$ES_CONF_DIR/log4j2.properties"
readonly DEFAULT_CLUSTER_NAME="bashmin-cluster"
readonly DEFAULT_NODE_NAME="bashmin-node-1"
readonly DEFAULT_HTTP_PORT="9200"
readonly DEFAULT_TRANSPORT_PORT="9300"
readonly MIN_HEAP_SIZE="1g"
readonly MAX_HEAP_SIZE="1g"

# Configuration variables
INSTALL_MODE="standard"
ES_VERSION="$DEFAULT_ES_VERSION"
CLUSTER_NAME="$DEFAULT_CLUSTER_NAME"
NODE_NAME="$DEFAULT_NODE_NAME"
HTTP_PORT="$DEFAULT_HTTP_PORT"
TRANSPORT_PORT="$DEFAULT_TRANSPORT_PORT"
HEAP_SIZE="$MIN_HEAP_SIZE"
ENABLE_SECURITY=true
ENABLE_MONITORING=true
ENABLE_INGEST=true
NETWORK_HOST="localhost"
DISCOVERY_TYPE="single-node"
SETUP_PASSWORD=""
FORCE_INSTALL=false
VERBOSE=false
DRY_RUN=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            INSTALL_MODE="$2"
            shift 2
            ;;
        --version)
            ES_VERSION="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --node-name)
            NODE_NAME="$2"
            shift 2
            ;;
        --http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --transport-port)
            TRANSPORT_PORT="$2"
            shift 2
            ;;
        --heap-size)
            HEAP_SIZE="$2"
            shift 2
            ;;
        --network-host)
            NETWORK_HOST="$2"
            shift 2
            ;;
        --discovery-type)
            DISCOVERY_TYPE="$2"
            shift 2
            ;;
        --password)
            SETUP_PASSWORD="$2"
            shift 2
            ;;
        --no-security)
            ENABLE_SECURITY=false
            shift
            ;;
        --no-monitoring)
            ENABLE_MONITORING=false
            shift
            ;;
        --no-ingest)
            ENABLE_INGEST=false
            shift
            ;;
        --force)
            FORCE_INSTALL=true
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

Install and configure Elasticsearch with security and monitoring features.

OPTIONS:
    --mode MODE                 Installation mode: minimal, standard, cluster (default: standard)
    --version VERSION           Elasticsearch version to install (default: $DEFAULT_ES_VERSION, use 'latest' for newest)
    --cluster-name NAME         Elasticsearch cluster name (default: $DEFAULT_CLUSTER_NAME)
    --node-name NAME           Node name for this instance (default: $DEFAULT_NODE_NAME)
    --http-port PORT           HTTP API port (default: $DEFAULT_HTTP_PORT)
    --transport-port PORT      Transport port for cluster communication (default: $DEFAULT_TRANSPORT_PORT)
    --heap-size SIZE           JVM heap size (default: $MIN_HEAP_SIZE)
    --network-host HOST        Network host binding (default: localhost)
    --discovery-type TYPE      Discovery type: single-node, zen (default: single-node)
    --password PASS            Setup password for elastic user
    --no-security             Disable security features
    --no-monitoring           Disable monitoring features
    --no-ingest               Disable ingest node capabilities
    --force                   Force reinstall even if already installed
    --quiet                   Suppress non-essential output
    --verbose                 Enable verbose output
    --dry-run                 Show what would be installed without executing
    -h, --help                Show this help message

INSTALLATION MODES:
    minimal                   Basic Elasticsearch with minimal configuration
    standard                  Full installation with security and monitoring (default)
    cluster                   Multi-node cluster configuration

EXAMPLES:
    # Standard single-node installation
    $0

    # Install latest version
    $0 --version latest

    # Install specific version
    $0 --version 8.14.3

    # Development setup with custom heap size
    $0 --mode minimal --heap-size 512m --no-security

    # Production cluster node
    $0 --mode cluster --cluster-name prod-cluster --node-name prod-node-1 --heap-size 4g

    # Custom network configuration
    $0 --network-host 0.0.0.0 --discovery-type zen --heap-size 2g

NOTES:
    - Requires sudo privileges
    - Installs OpenJDK 17 if not present
    - Creates systemd service for automatic startup
    - Sets up proper file permissions and ownership
    - Configures log rotation automatically
    - Security features require password setup

EOF
}

# Function to detect system information
detect_system() {
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Detecting system information..."
    fi
    
    # Detect OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    # Check if Ubuntu/Debian
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_error "This script only supports Ubuntu and Debian systems"
        exit 1
    fi
    
    # Detect architecture
    ARCH=$(dpkg --print-architecture)
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Detected: $OS $VER ($ARCH)"
    fi
}

# Function to resolve Elasticsearch version
resolve_elasticsearch_version() {
    if [[ "$ES_VERSION" == "latest" ]]; then
        if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
            print_info "Resolving latest Elasticsearch version..."
        fi
        
        # Get latest version from Elastic API
        local latest_version
        latest_version=$(curl -s "https://api.github.com/repos/elastic/elasticsearch/releases/latest" | \
                        grep '"tag_name":' | \
                        sed -E 's/.*"([^"]+)".*/\1/' | \
                        sed 's/^v//' 2>/dev/null)
        
        if [[ -z "$latest_version" ]]; then
            # Fallback method using Elastic artifacts API
            latest_version=$(curl -s "https://artifacts.elastic.co/api/versions" | \
                           grep -o '"[0-9]\+\.[0-9]\+\.[0-9]\+"' | \
                           sed 's/"//g' | \
                           sort -V | \
                           tail -1 2>/dev/null)
        fi
        
        if [[ -z "$latest_version" ]]; then
            print_warning "Could not resolve latest version, using default: $DEFAULT_ES_VERSION"
            ES_VERSION="$DEFAULT_ES_VERSION"
        else
            ES_VERSION="$latest_version"
            if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
                print_success "Latest version resolved: $ES_VERSION"
            fi
        fi
    else
        # Validate version format
        if [[ ! "$ES_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            print_error "Invalid version format: $ES_VERSION"
            print_info "Use format like: 8.15.0 or 'latest'"
            exit 1
        fi
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
    
    # Check if Elasticsearch is already installed
    if systemctl is-active --quiet elasticsearch 2>/dev/null && [[ "$FORCE_INSTALL" == false ]]; then
        print_error "Elasticsearch is already installed and running"
        print_info "Use --force to reinstall"
        exit 1
    fi
    
    # Check available memory
    local available_memory
    available_memory=$(awk '/MemAvailable/{printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "0")
    
    if [[ "$available_memory" -lt 2 ]]; then
        print_warning "Less than 2GB RAM available. Elasticsearch may not perform well."
        print_info "Consider increasing heap size with --heap-size"
    fi
    
    # Check disk space
    local available_space
    available_space=$(df / | awk 'NR==2 {printf "%.0f", $4/1024/1024}')
    
    if [[ "$available_space" -lt 2 ]]; then
        print_warning "Less than 2GB disk space available"
    fi
}

# Function to install dependencies
install_dependencies() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install dependencies: openjdk-17-jdk, apt-transport-https, curl, gnupg"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installing dependencies..."
    fi
    
    # Update package cache
    sudo apt-get update -qq
    
    # Install required packages
    sudo apt-get install -y \
        openjdk-17-jdk \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        wget
    
    # Verify Java installation
    if ! java -version >/dev/null 2>&1; then
        print_error "Java installation failed"
        exit 1
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        local java_version
        java_version=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
        print_success "Java installed: $java_version"
    fi
}

# Function to add Elasticsearch repository
add_elasticsearch_repository() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would add Elasticsearch repository"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Adding Elasticsearch repository..."
    fi
    
    # Import GPG key
    curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    
    # Add repository
    echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | \
        sudo tee /etc/apt/sources.list.d/elastic-8.x.list
    
    # Update package cache
    sudo apt-get update -qq
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Elasticsearch repository added"
    fi
}

# Function to install Elasticsearch
install_elasticsearch() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would install Elasticsearch $ES_VERSION"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installing Elasticsearch $ES_VERSION..."
    fi
    
    # Install specific version or latest
    if [[ "$ES_VERSION" == "$DEFAULT_ES_VERSION" ]] || command -v apt-cache >/dev/null && apt-cache show "elasticsearch=$ES_VERSION" >/dev/null 2>&1; then
        # Install specific version if available
        if [[ "$ES_VERSION" != "$DEFAULT_ES_VERSION" ]]; then
            sudo apt-get install -y "elasticsearch=$ES_VERSION"
        else
            sudo apt-get install -y elasticsearch
        fi
    else
        # Install latest available version
        sudo apt-get install -y elasticsearch
    fi
    
    # Verify installation
    if [[ ! -f "/usr/share/elasticsearch/bin/elasticsearch" ]]; then
        print_error "Elasticsearch installation failed"
        exit 1
    fi
    
    # Get installed version
    local installed_version
    installed_version=$(/usr/share/elasticsearch/bin/elasticsearch --version | awk '{print $2}')
    
    # Update ES_VERSION to actual installed version for consistency
    ES_VERSION="$installed_version"
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Elasticsearch installed: $installed_version"
    fi
}

# Function to configure JVM options
configure_jvm() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure JVM with heap size: $HEAP_SIZE"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring JVM options..."
    fi
    
    # Backup original configuration
    sudo cp "$ES_JVM_OPTIONS" "$ES_JVM_OPTIONS.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Set heap size
    sudo sed -i "s/^-Xms.*/-Xms$HEAP_SIZE/" "$ES_JVM_OPTIONS"
    sudo sed -i "s/^-Xmx.*/-Xmx$HEAP_SIZE/" "$ES_JVM_OPTIONS"
    
    # Add additional JVM options for better performance
    cat << EOF | sudo tee -a "$ES_JVM_OPTIONS" >/dev/null

# Bashmin JVM optimizations
-XX:+UseG1GC
-XX:G1HeapRegionSize=16m
-XX:+DisableExplicitGC
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=$ES_LOG_DIR
-XX:ErrorFile=$ES_LOG_DIR/hs_err_pid%p.log
EOF
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "JVM configured with heap size: $HEAP_SIZE"
    fi
}

# Function to configure Elasticsearch
configure_elasticsearch() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure Elasticsearch with cluster: $CLUSTER_NAME, node: $NODE_NAME"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring Elasticsearch..."
    fi
    
    # Backup original configuration
    sudo cp "$ES_CONFIG_FILE" "$ES_CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create new configuration
    cat << EOF | sudo tee "$ES_CONFIG_FILE" >/dev/null
# ======================== Elasticsearch Configuration =========================
#
# Generated by bashmin on $(date)
#

# ---------------------------------- Cluster -----------------------------------
cluster.name: $CLUSTER_NAME

# ------------------------------------ Node ------------------------------------
node.name: $NODE_NAME
EOF

    # Add node roles based on installation mode
    case "$INSTALL_MODE" in
        minimal)
            cat << EOF | sudo tee -a "$ES_CONFIG_FILE" >/dev/null
node.roles: [ master, data, ingest ]
EOF
            ;;
        standard)
            cat << EOF | sudo tee -a "$ES_CONFIG_FILE" >/dev/null
node.roles: [ master, data, ingest, ml, remote_cluster_client ]
EOF
            ;;
        cluster)
            cat << EOF | sudo tee -a "$ES_CONFIG_FILE" >/dev/null
node.roles: [ master, data, ingest, ml, remote_cluster_client ]
EOF
            ;;
    esac

    # Add paths configuration
    cat << EOF | sudo tee -a "$ES_CONFIG_FILE" >/dev/null

# ----------------------------------- Paths ------------------------------------
path.data: $ES_DATA_DIR
path.logs: $ES_LOG_DIR

# ----------------------------------- Memory -----------------------------------
bootstrap.memory_lock: true

# ---------------------------------- Network -----------------------------------
network.host: $NETWORK_HOST
http.port: $HTTP_PORT
transport.port: $TRANSPORT_PORT

# --------------------------------- Discovery ----------------------------------
discovery.type: $DISCOVERY_TYPE
EOF

    # Add cluster-specific discovery settings
    if [[ "$DISCOVERY_TYPE" == "zen" ]]; then
        cat << EOF | sudo tee -a "$ES_CONFIG_FILE" >/dev/null
cluster.initial_master_nodes: ["$NODE_NAME"]
EOF
    fi

    # Add security configuration
    if [[ "$ENABLE_SECURITY" == true && "$INSTALL_MODE" != "minimal" ]]; then
        cat << EOF | sudo tee -a "$ES_CONFIG_FILE" >/dev/null

# ---------------------------------- Security ----------------------------------
xpack.security.enabled: true
xpack.security.enrollment.enabled: true
xpack.security.http.ssl:
  enabled: false
xpack.security.transport.ssl:
  enabled: false
EOF
    else
        cat << EOF | sudo tee -a "$ES_CONFIG_FILE" >/dev/null

# ---------------------------------- Security ----------------------------------
xpack.security.enabled: false
EOF
    fi

    # Add monitoring configuration
    if [[ "$ENABLE_MONITORING" == true && "$INSTALL_MODE" != "minimal" ]]; then
        cat << EOF | sudo tee -a "$ES_CONFIG_FILE" >/dev/null

# --------------------------------- Monitoring ---------------------------------
xpack.monitoring.collection.enabled: true
EOF
    fi

    # Add machine learning configuration
    if [[ "$INSTALL_MODE" == "standard" || "$INSTALL_MODE" == "cluster" ]]; then
        cat << EOF | sudo tee -a "$ES_CONFIG_FILE" >/dev/null

# ----------------------------- Machine Learning -------------------------------
xpack.ml.enabled: true
EOF
    fi

    # Add additional performance settings
    cat << EOF | sudo tee -a "$ES_CONFIG_FILE" >/dev/null

# -------------------------------- Performance ----------------------------------
indices.memory.index_buffer_size: 20%
indices.queries.cache.size: 15%
indices.fielddata.cache.size: 20%
thread_pool.write.queue_size: 1000
thread_pool.search.queue_size: 1000

# ---------------------------------- Logging -----------------------------------
logger.level: INFO
logger.org.elasticsearch.transport: WARN
logger.org.elasticsearch.discovery: WARN

EOF

    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Elasticsearch configuration created"
    fi
}

# Function to configure system limits
configure_system_limits() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would configure system limits and kernel parameters"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Configuring system limits..."
    fi
    
    # Configure systemd service limits
    sudo mkdir -p /etc/systemd/system/elasticsearch.service.d
    cat << EOF | sudo tee /etc/systemd/system/elasticsearch.service.d/override.conf >/dev/null
[Service]
LimitNOFILE=65535
LimitNPROC=4096
LimitMEMLOCK=infinity
EOF
    
    # Configure user limits
    cat << EOF | sudo tee /etc/security/limits.d/elasticsearch.conf >/dev/null
elasticsearch soft nofile 65535
elasticsearch hard nofile 65535
elasticsearch soft nproc 4096
elasticsearch hard nproc 4096
elasticsearch soft memlock unlimited
elasticsearch hard memlock unlimited
EOF
    
    # Configure kernel parameters
    cat << EOF | sudo tee /etc/sysctl.d/elasticsearch.conf >/dev/null
# Elasticsearch system tuning
vm.max_map_count=262144
vm.swappiness=1
net.core.somaxconn=65535
EOF
    
    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.d/elasticsearch.conf >/dev/null
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "System limits configured"
    fi
}

# Function to setup log rotation
setup_log_rotation() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would setup log rotation"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Setting up log rotation..."
    fi
    
    # Create logrotate configuration
    cat << EOF | sudo tee /etc/logrotate.d/elasticsearch >/dev/null
$ES_LOG_DIR/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 elasticsearch elasticsearch
    postrotate
        systemctl reload elasticsearch > /dev/null 2>&1 || true
    endscript
}
EOF
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Log rotation configured"
    fi
}

# Function to setup security
setup_security() {
    if [[ "$ENABLE_SECURITY" == false || "$INSTALL_MODE" == "minimal" ]]; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would setup Elasticsearch security"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Setting up Elasticsearch security..."
    fi
    
    # Generate password if not provided
    if [[ -z "$SETUP_PASSWORD" ]]; then
        SETUP_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    fi
    
    # Start Elasticsearch temporarily to setup security
    sudo systemctl start elasticsearch
    
    # Wait for Elasticsearch to start
    for i in {1..30}; do
        if curl -s "http://localhost:$HTTP_PORT" >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
    
    # Setup passwords
    echo "y" | sudo -u elasticsearch /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto 2>/dev/null || {
        # If auto setup fails, set password manually
        sudo -u elasticsearch /usr/share/elasticsearch/bin/elasticsearch-users useradd elastic -p "$SETUP_PASSWORD" -r superuser 2>/dev/null || true
    }
    
    # Save credentials
    cat << EOF | sudo tee /etc/elasticsearch/credentials.txt >/dev/null
# Elasticsearch Credentials - Generated $(date)
# Keep this file secure!

Username: elastic
Password: $SETUP_PASSWORD

# Connection URL
http://elastic:$SETUP_PASSWORD@localhost:$HTTP_PORT

EOF
    
    sudo chmod 600 /etc/elasticsearch/credentials.txt
    sudo chown elasticsearch:elasticsearch /etc/elasticsearch/credentials.txt
    
    if [[ "$QUIET" == false ]]; then
        print_warning "Security credentials saved to: /etc/elasticsearch/credentials.txt"
        print_info "Username: elastic"
        print_info "Password: $SETUP_PASSWORD"
    fi
}

# Function to start and enable service
start_service() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would start and enable Elasticsearch service"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Starting Elasticsearch service..."
    fi
    
    # Reload systemd daemon
    sudo systemctl daemon-reload
    
    # Enable and start service
    sudo systemctl enable elasticsearch
    sudo systemctl restart elasticsearch
    
    # Wait for service to start
    for i in {1..60}; do
        if systemctl is-active --quiet elasticsearch; then
            break
        fi
        sleep 2
    done
    
    # Verify service is running
    if ! systemctl is-active --quiet elasticsearch; then
        print_error "Failed to start Elasticsearch service"
        print_info "Check logs: sudo journalctl -u elasticsearch -f"
        exit 1
    fi
    
    # Wait for HTTP endpoint to be available
    for i in {1..30}; do
        if curl -s "http://localhost:$HTTP_PORT" >/dev/null 2>&1; then
            break
        fi
        sleep 3
    done
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Elasticsearch service started and enabled"
    fi
}

# Function to verify installation
verify_installation() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would verify Elasticsearch installation"
        return 0
    fi
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Verifying installation..."
    fi
    
    # Check service status
    if ! systemctl is-active --quiet elasticsearch; then
        print_error "Elasticsearch service is not running"
        return 1
    fi
    
    # Check HTTP endpoint
    local auth_header=""
    if [[ "$ENABLE_SECURITY" == true && "$INSTALL_MODE" != "minimal" && -n "$SETUP_PASSWORD" ]]; then
        auth_header="-u elastic:$SETUP_PASSWORD"
    fi
    
    local response
    response=$(curl -s $auth_header "http://localhost:$HTTP_PORT" 2>/dev/null || echo "")
    
    if [[ -z "$response" ]]; then
        print_error "Cannot connect to Elasticsearch HTTP endpoint"
        return 1
    fi
    
    # Parse cluster info
    local cluster_name_check
    local version_check
    cluster_name_check=$(echo "$response" | grep -o '"cluster_name"[^,]*' | cut -d'"' -f4 || echo "unknown")
    version_check=$(echo "$response" | grep -o '"number"[^,]*' | cut -d'"' -f4 || echo "unknown")
    
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_success "Elasticsearch is responding"
        print_info "Cluster: $cluster_name_check"
        print_info "Version: $version_check"
    fi
    
    return 0
}

# Function to show completion summary
show_completion_summary() {
    if [[ "$QUIET" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo
    print_success "Elasticsearch installation completed successfully! 🚀"
    echo
    print_info "=== Installation Summary ==="
    cat << EOF
Elasticsearch Version: $ES_VERSION
Installation Mode:     $INSTALL_MODE
Cluster Name:          $CLUSTER_NAME
Node Name:             $NODE_NAME
HTTP Port:             $HTTP_PORT
Transport Port:        $TRANSPORT_PORT
Heap Size:             $HEAP_SIZE
Network Host:          $NETWORK_HOST
Discovery Type:        $DISCOVERY_TYPE
Security:              $(if [[ "$ENABLE_SECURITY" == true && "$INSTALL_MODE" != "minimal" ]]; then echo "Enabled"; else echo "Disabled"; fi)
Monitoring:            $(if [[ "$ENABLE_MONITORING" == true && "$INSTALL_MODE" != "minimal" ]]; then echo "Enabled"; else echo "Disabled"; fi)

EOF

    print_info "=== Service Information ==="
    cat << EOF
Status:              $(systemctl is-active elasticsearch)
Enabled:             $(systemctl is-enabled elasticsearch)
Config File:         $ES_CONFIG_FILE
Data Directory:      $ES_DATA_DIR
Log Directory:       $ES_LOG_DIR

EOF

    print_info "=== Connection Details ==="
    cat << EOF
HTTP Endpoint:       http://localhost:$HTTP_PORT
Health Check:        http://localhost:$HTTP_PORT/_cluster/health
Node Info:           http://localhost:$HTTP_PORT/_nodes/_local

EOF

    if [[ "$ENABLE_SECURITY" == true && "$INSTALL_MODE" != "minimal" ]]; then
        print_info "=== Security Information ==="
        cat << EOF
Authentication:      Enabled
Credentials File:    /etc/elasticsearch/credentials.txt
Default User:        elastic
$(if [[ -n "$SETUP_PASSWORD" ]]; then echo "Generated Password:  $SETUP_PASSWORD"; fi)

EOF
    fi

    print_info "=== Management Commands ==="
    cat << EOF
Start service:       sudo systemctl start elasticsearch
Stop service:        sudo systemctl stop elasticsearch
Restart service:     sudo systemctl restart elasticsearch
View status:         sudo systemctl status elasticsearch
View logs:           sudo journalctl -u elasticsearch -f
Test connection:     curl -X GET "localhost:$HTTP_PORT"

EOF

    if [[ "$ENABLE_SECURITY" == true && "$INSTALL_MODE" != "minimal" ]]; then
        cat << EOF
Authenticated test:  curl -u elastic:password -X GET "localhost:$HTTP_PORT"
Change password:     /usr/share/elasticsearch/bin/elasticsearch-users passwd elastic

EOF
    fi

    print_info "=== Configuration Files ==="
    cat << EOF
Main config:         $ES_CONFIG_FILE
JVM options:         $ES_JVM_OPTIONS
Log config:          $ES_LOG4J_CONFIG
System limits:       /etc/systemd/system/elasticsearch.service.d/override.conf

EOF

    print_info "=== Next Steps ==="
    cat << EOF
1. Test connection: curl http://localhost:$HTTP_PORT
2. Check cluster health: curl http://localhost:$HTTP_PORT/_cluster/health
3. Create your first index: curl -X PUT http://localhost:$HTTP_PORT/test-index
4. Configure backup strategy if needed
5. Set up monitoring dashboards if using X-Pack

EOF

    if [[ "$INSTALL_MODE" == "cluster" ]]; then
        print_info "=== Cluster Setup ==="
        cat << EOF
For multi-node cluster:
1. Install Elasticsearch on other nodes
2. Update discovery settings in elasticsearch.yml
3. Set cluster.initial_master_nodes with all master-eligible nodes
4. Ensure network connectivity between nodes

EOF
    fi
    
    print_info "🔍 Your Elasticsearch cluster is ready for indexing!"
}

# Main function
main() {
    # Detect system
    detect_system
    
    # Resolve Elasticsearch version
    resolve_elasticsearch_version
    
    # Validate inputs (basic validation)
    if [[ ! "$HEAP_SIZE" =~ ^[0-9]+[gmGM]?$ ]]; then
        print_error "Invalid heap size format: $HEAP_SIZE"
        print_info "Use format like: 1g, 512m, 2G"
        exit 1
    fi
    
    if [[ ! "$HTTP_PORT" =~ ^[0-9]+$ ]] || [[ "$HTTP_PORT" -lt 1024 ]] || [[ "$HTTP_PORT" -gt 65535 ]]; then
        print_error "Invalid HTTP port: $HTTP_PORT"
        exit 1
    fi
    
    if [[ "$QUIET" == false ]]; then
        show_script_header "Elasticsearch Installation"
        print_info "Installing Elasticsearch $ES_VERSION in $INSTALL_MODE mode"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Show installation plan
    if [[ "$VERBOSE" == true && "$QUIET" == false ]]; then
        print_info "Installation plan:"
        print_info "  Version: $ES_VERSION"
        print_info "  Mode: $INSTALL_MODE"
        print_info "  Cluster: $CLUSTER_NAME"
        print_info "  Node: $NODE_NAME"
        print_info "  Heap: $HEAP_SIZE"
        print_info "  Security: $ENABLE_SECURITY"
        print_info "  Monitoring: $ENABLE_MONITORING"
        
        if [[ "$DRY_RUN" == false ]] && ! confirm_action "Proceed with installation?" "Y"; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Execute installation steps
    install_dependencies
    add_elasticsearch_repository
    install_elasticsearch
    configure_jvm
    configure_elasticsearch
    configure_system_limits
    setup_log_rotation
    start_service
    setup_security
    
    # Verify installation
    if verify_installation; then
        show_completion_summary
    else
        print_error "Installation verification failed"
        print_info "Check logs: sudo journalctl -u elasticsearch -f"
        exit 1
    fi
}

# Run main function
main "$@"
