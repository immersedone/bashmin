#!/bin/bash
#
# File: optimize.sh
# Description: Optimize MariaDB configuration based on system hardware
# Author: Bashmin Project
# Usage: ./optimize.sh [OPTIONS]
#
# This script analyzes system resources (RAM, CPU, disk) and generates
# an optimized MariaDB configuration tailored to the hardware capabilities.
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source helper functions
source "$PROJECT_ROOT/_helpers/common.sh"
source "$PROJECT_ROOT/_helpers/system.sh"

# Constants
readonly MARIADB_SERVICE="mariadb"
readonly CONFIG_TEMPLATE="$PROJECT_ROOT/system/etc/mysql/mariadb.conf.d/50-server.cnf"
readonly CONFIG_TARGET="/etc/mysql/mariadb.conf.d/50-server.cnf"
readonly CONFIG_BACKUP="/etc/mysql/mariadb.conf.d/50-server.cnf.backup.$(date +%Y%m%d_%H%M%S)"
readonly TEMP_CONFIG="/tmp/mariadb_optimized.cnf"

# Configuration
VERBOSE=false
DRY_RUN=false
AUTO_APPLY=false
WORKLOAD_TYPE="mixed"
RESTART_SERVICE=true
MAX_RAM_MB=0
MAX_CPU_CORES=0
INTERACTIVE_LIMITS=false

# System information variables
TOTAL_RAM_MB=0
TOTAL_RAM_GB=0
CPU_CORES=0
DISK_TYPE=""
AVAILABLE_RAM_FOR_MYSQL=0

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Optimize MariaDB configuration based on system hardware.

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -n, --dry-run           Generate config without applying
    -a, --auto-apply        Apply configuration automatically without prompts
    -w, --workload TYPE     Workload type: web|oltp|mixed|analytical|development|multiservice (default: mixed)
    --no-restart           Don't restart MariaDB service after applying config
    -i, --interactive      Prompt for custom RAM and CPU limits
    --max-ram MB           Set maximum RAM usage in MB (overrides automatic calculation)
    --max-cpu CORES        Set maximum CPU cores to use (overrides automatic detection)

Workload Types:
    web         - Optimized for web applications (WordPress, etc.)
    oltp        - Online Transaction Processing (high concurrency, small transactions)
    mixed       - Balanced configuration for mixed workloads
    analytical  - Data warehousing and analytical queries
    development - Conservative settings for local development environments
    multiservice- Optimized for servers running multiple services (shared resources)

Examples:
    $0                      Generate optimized config with prompts
    $0 -v -w web           Generate web-optimized config with verbose output
    $0 -a --no-restart     Auto-apply without service restart
    $0 -n                  Dry run to preview optimizations
    $0 -w development      Optimize for local development environment
    $0 -w multiservice -a  Auto-apply multi-service optimization
    $0 -i                  Interactive mode with custom resource limits
    $0 --max-ram 4096 --max-cpu 4    Limit to 4GB RAM and 4 CPU cores

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -a|--auto-apply)
                AUTO_APPLY=true
                shift
                ;;
            -w|--workload)
                WORKLOAD_TYPE="$2"
                shift 2
                ;;
            --no-restart)
                RESTART_SERVICE=false
                shift
                ;;
            -i|--interactive)
                INTERACTIVE_LIMITS=true
                shift
                ;;
            --max-ram)
                MAX_RAM_MB="$2"
                shift 2
                ;;
            --max-cpu)
                MAX_CPU_CORES="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate numeric inputs
    if [[ $MAX_RAM_MB -gt 0 ]]; then
        if ! [[ "$MAX_RAM_MB" =~ ^[0-9]+$ ]]; then
            print_error "Invalid RAM value: $MAX_RAM_MB (must be a positive integer)"
            exit 1
        fi
    fi
    
    if [[ $MAX_CPU_CORES -gt 0 ]]; then
        if ! [[ "$MAX_CPU_CORES" =~ ^[0-9]+$ ]]; then
            print_error "Invalid CPU cores value: $MAX_CPU_CORES (must be a positive integer)"
            exit 1
        fi
    fi
    
    # Validate workload type
    case "$WORKLOAD_TYPE" in
        web|oltp|mixed|analytical|development|multiservice)
            ;;
        *)
            print_error "Invalid workload type: $WORKLOAD_TYPE"
            print_error "Valid types: web, oltp, mixed, analytical, development, multiservice"
            exit 1
            ;;
    esac
}

# Function to prompt for resource limits
prompt_resource_limits() {
    if [[ "$INTERACTIVE_LIMITS" == true ]] || [[ $MAX_RAM_MB -gt 0 ]] || [[ $MAX_CPU_CORES -gt 0 ]]; then
        print_info "Resource Limit Configuration"
        echo "============================="
        echo "Detected system resources:"
        echo "  Total RAM: ${TOTAL_RAM_MB}MB (${TOTAL_RAM_GB}GB)"
        echo "  Total CPU cores: $CPU_CORES"
        echo ""
        
        # Prompt for RAM limit if interactive and not already set
        if [[ "$INTERACTIVE_LIMITS" == true ]] && [[ $MAX_RAM_MB -eq 0 ]]; then
            while true; do
                echo "RAM Allocation Options:"
                echo "  1) Use automatic calculation (recommended)"
                echo "  2) Set custom maximum RAM for MariaDB"
                echo ""
                read -p "Choose option (1-2): " -r ram_choice
                
                case $ram_choice in
                    1)
                        print_info "Using automatic RAM calculation"
                        break
                        ;;
                    2)
                        read -p "Enter maximum RAM for MariaDB in MB (1-${TOTAL_RAM_MB}): " -r MAX_RAM_MB
                        if [[ "$MAX_RAM_MB" =~ ^[0-9]+$ ]] && [[ $MAX_RAM_MB -gt 0 ]] && [[ $MAX_RAM_MB -le $TOTAL_RAM_MB ]]; then
                            print_success "Custom RAM limit set to ${MAX_RAM_MB}MB"
                            break
                        else
                            print_error "Invalid input. Please enter a number between 1 and $TOTAL_RAM_MB"
                            MAX_RAM_MB=0
                        fi
                        ;;
                    *)
                        print_error "Invalid choice. Please select 1 or 2."
                        ;;
                esac
            done
        fi
        
        # Prompt for CPU limit if interactive and not already set
        if [[ "$INTERACTIVE_LIMITS" == true ]] && [[ $MAX_CPU_CORES -eq 0 ]]; then
            echo ""
            while true; do
                echo "CPU Allocation Options:"
                echo "  1) Use all available CPU cores (recommended)"
                echo "  2) Set custom maximum CPU cores for MariaDB"
                echo ""
                read -p "Choose option (1-2): " -r cpu_choice
                
                case $cpu_choice in
                    1)
                        print_info "Using all available CPU cores"
                        break
                        ;;
                    2)
                        read -p "Enter maximum CPU cores for MariaDB (1-${CPU_CORES}): " -r MAX_CPU_CORES
                        if [[ "$MAX_CPU_CORES" =~ ^[0-9]+$ ]] && [[ $MAX_CPU_CORES -gt 0 ]] && [[ $MAX_CPU_CORES -le $CPU_CORES ]]; then
                            print_success "Custom CPU limit set to $MAX_CPU_CORES cores"
                            break
                        else
                            print_error "Invalid input. Please enter a number between 1 and $CPU_CORES"
                            MAX_CPU_CORES=0
                        fi
                        ;;
                    *)
                        print_error "Invalid choice. Please select 1 or 2."
                        ;;
                esac
            done
        fi
        
        # Validate command line limits
        if [[ $MAX_RAM_MB -gt $TOTAL_RAM_MB ]]; then
            print_warning "Specified RAM limit (${MAX_RAM_MB}MB) exceeds system RAM (${TOTAL_RAM_MB}MB). Using system maximum."
            MAX_RAM_MB=$TOTAL_RAM_MB
        fi
        
        if [[ $MAX_CPU_CORES -gt $CPU_CORES ]]; then
            print_warning "Specified CPU limit ($MAX_CPU_CORES) exceeds system cores ($CPU_CORES). Using system maximum."
            MAX_CPU_CORES=$CPU_CORES
        fi
        
        echo ""
    fi
}

# Function to gather system information
gather_system_info() {
    print_info "Analyzing system hardware..."
    
    # Get total RAM in MB
    TOTAL_RAM_MB=$(free -m | awk 'NR==2{print $2}')
    TOTAL_RAM_GB=$((TOTAL_RAM_MB / 1024))
    
    # Get CPU cores
    CPU_CORES=$(nproc)
    
    # Detect disk type (SSD vs HDD)
    if [[ -f /sys/block/sda/queue/rotational ]]; then
        if [[ $(cat /sys/block/sda/queue/rotational) -eq 0 ]]; then
            DISK_TYPE="SSD"
        else
            DISK_TYPE="HDD"
        fi
    else
        DISK_TYPE="Unknown"
    fi
    
    # Prompt for resource limits if needed
    prompt_resource_limits
    
    # Apply user-defined limits
    local effective_ram_mb=$TOTAL_RAM_MB
    local effective_cpu_cores=$CPU_CORES
    
    if [[ $MAX_RAM_MB -gt 0 ]]; then
        effective_ram_mb=$MAX_RAM_MB
        print_info "Using custom RAM limit: ${MAX_RAM_MB}MB (of ${TOTAL_RAM_MB}MB available)"
    fi
    
    if [[ $MAX_CPU_CORES -gt 0 ]]; then
        effective_cpu_cores=$MAX_CPU_CORES
        CPU_CORES=$MAX_CPU_CORES  # Update global variable for calculations
        print_info "Using custom CPU limit: $MAX_CPU_CORES cores (of $(nproc) available)"
    fi
    
    # Calculate available RAM for MySQL (conservative approach)
    # Leave room for OS and other services
    if [[ $effective_ram_mb -le 1024 ]]; then
        # Small systems: leave 512MB for OS
        AVAILABLE_RAM_FOR_MYSQL=$((effective_ram_mb - 512))
    elif [[ $effective_ram_mb -le 4096 ]]; then
        # Medium systems: leave 1GB for OS
        AVAILABLE_RAM_FOR_MYSQL=$((effective_ram_mb - 1024))
    elif [[ $effective_ram_mb -le 8192 ]]; then
        # Large systems: leave 2GB for OS
        AVAILABLE_RAM_FOR_MYSQL=$((effective_ram_mb - 2048))
    else
        # Very large systems: use 75% of total RAM
        AVAILABLE_RAM_FOR_MYSQL=$((effective_ram_mb * 75 / 100))
    fi
    
    # Adjust for specific workload types
    case "$WORKLOAD_TYPE" in
        development)
            # Development: Very conservative, leave lots of RAM for IDE, browser, etc.
            if [[ $effective_ram_mb -le 8192 ]]; then
                AVAILABLE_RAM_FOR_MYSQL=$((effective_ram_mb * 20 / 100))  # Only 20% on smaller dev machines
            else
                AVAILABLE_RAM_FOR_MYSQL=$((effective_ram_mb * 30 / 100))  # 30% on larger dev machines
            fi
            ;;
        multiservice)
            # Multi-service: Very conservative allocation, assume other services need RAM
            if [[ $effective_ram_mb -le 2048 ]]; then
                AVAILABLE_RAM_FOR_MYSQL=$((effective_ram_mb * 25 / 100))  # 25% on small servers
            elif [[ $effective_ram_mb -le 8192 ]]; then
                AVAILABLE_RAM_FOR_MYSQL=$((effective_ram_mb * 35 / 100))  # 35% on medium servers
            else
                AVAILABLE_RAM_FOR_MYSQL=$((effective_ram_mb * 45 / 100))  # 45% on large servers
            fi
            ;;
    esac
    
    # Ensure minimum available RAM
    if [[ $AVAILABLE_RAM_FOR_MYSQL -lt 256 ]]; then
        AVAILABLE_RAM_FOR_MYSQL=256
    fi
    
    # Apply hard RAM cap if user specified one
    if [[ $MAX_RAM_MB -gt 0 ]] && [[ $AVAILABLE_RAM_FOR_MYSQL -gt $MAX_RAM_MB ]]; then
        AVAILABLE_RAM_FOR_MYSQL=$MAX_RAM_MB
        print_warning "Available RAM for MySQL capped at user limit: ${MAX_RAM_MB}MB"
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        print_info "System Analysis Results:"
        echo "  Total RAM: ${TOTAL_RAM_MB}MB (${TOTAL_RAM_GB}GB)"
        if [[ $MAX_RAM_MB -gt 0 ]]; then
            echo "  RAM Limit: ${MAX_RAM_MB}MB (user-defined)"
        fi
        echo "  CPU Cores: $effective_cpu_cores"
        if [[ $MAX_CPU_CORES -gt 0 ]]; then
            echo "  CPU Limit: $MAX_CPU_CORES cores (user-defined)"
        fi
        echo "  Disk Type: $DISK_TYPE"
        echo "  Available RAM for MySQL: ${AVAILABLE_RAM_FOR_MYSQL}MB"
        echo "  Workload Type: $WORKLOAD_TYPE"
    fi
    
    print_success "System analysis completed"
}

# Function to calculate InnoDB buffer pool size
calculate_innodb_buffer_pool() {
    local buffer_pool_mb
    
    case "$WORKLOAD_TYPE" in
        web|mixed)
            # 60-70% of available RAM for web/mixed workloads
            buffer_pool_mb=$((AVAILABLE_RAM_FOR_MYSQL * 65 / 100))
            ;;
        oltp)
            # 70-80% for OLTP workloads (more caching needed)
            buffer_pool_mb=$((AVAILABLE_RAM_FOR_MYSQL * 75 / 100))
            ;;
        analytical)
            # 80-90% for analytical workloads
            buffer_pool_mb=$((AVAILABLE_RAM_FOR_MYSQL * 85 / 100))
            ;;
        development)
            # Development: Very conservative buffer pool
            buffer_pool_mb=$((AVAILABLE_RAM_FOR_MYSQL * 50 / 100))
            ;;
        multiservice)
            # Multi-service: Conservative but efficient
            buffer_pool_mb=$((AVAILABLE_RAM_FOR_MYSQL * 60 / 100))
            ;;
    esac
    
    # Minimum 128MB, maximum based on available RAM
    if [[ $buffer_pool_mb -lt 128 ]]; then
        buffer_pool_mb=128
    fi
    
    echo $buffer_pool_mb
}

# Function to calculate buffer pool instances
calculate_buffer_pool_instances() {
    local buffer_pool_mb=$1
    local instances
    
    # Rule: 1 instance per GB, minimum 1, maximum equal to CPU cores
    instances=$((buffer_pool_mb / 1024))
    
    if [[ $instances -lt 1 ]]; then
        instances=1
    elif [[ $instances -gt $CPU_CORES ]]; then
        instances=$CPU_CORES
    fi
    
    echo $instances
}

# Function to calculate connection limits
calculate_max_connections() {
    local connections
    
    case "$WORKLOAD_TYPE" in
        web)
            # Web applications typically need more connections
            connections=$((CPU_CORES * 50))
            ;;
        oltp)
            # OLTP needs many concurrent connections
            connections=$((CPU_CORES * 75))
            ;;
        mixed)
            # Balanced approach
            connections=$((CPU_CORES * 40))
            ;;
        analytical)
            # Analytical workloads need fewer but more resource-intensive connections
            connections=$((CPU_CORES * 25))
            ;;
        development)
            # Development: Low connection count, usually single developer
            connections=$((CPU_CORES * 10))
            if [[ $connections -lt 20 ]]; then connections=20; fi
            ;;
        multiservice)
            # Multi-service: Moderate connections, shared with other services
            connections=$((CPU_CORES * 20))
            ;;
    esac
    
    # Apply reasonable bounds
    if [[ $connections -lt 50 ]] && [[ "$WORKLOAD_TYPE" != "development" ]]; then
        connections=50
    elif [[ $connections -gt 1000 ]]; then
        connections=1000
    fi
    
    echo $connections
}

# Function to calculate query cache size
calculate_query_cache_size() {
    local cache_size_mb
    
    case "$WORKLOAD_TYPE" in
        web)
            # Web applications benefit from query caching
            cache_size_mb=$((AVAILABLE_RAM_FOR_MYSQL * 8 / 100))
            ;;
        oltp)
            # OLTP may benefit from moderate caching
            cache_size_mb=$((AVAILABLE_RAM_FOR_MYSQL * 5 / 100))
            ;;
        mixed)
            # Balanced approach
            cache_size_mb=$((AVAILABLE_RAM_FOR_MYSQL * 6 / 100))
            ;;
        analytical)
            # Analytical workloads rarely benefit from query cache
            cache_size_mb=$((AVAILABLE_RAM_FOR_MYSQL * 2 / 100))
            ;;
        development)
            # Development: Small cache for testing, frequent schema changes
            cache_size_mb=$((AVAILABLE_RAM_FOR_MYSQL * 3 / 100))
            ;;
        multiservice)
            # Multi-service: Conservative caching
            cache_size_mb=$((AVAILABLE_RAM_FOR_MYSQL * 4 / 100))
            ;;
    esac
    
    # Apply bounds: 16MB to 512MB
    if [[ $cache_size_mb -lt 16 ]]; then
        cache_size_mb=16
    elif [[ $cache_size_mb -gt 512 ]]; then
        cache_size_mb=512
    fi
    
    echo $cache_size_mb
}

# Function to calculate other memory settings
calculate_memory_settings() {
    local settings_array=()
    
    # Key buffer size (for MyISAM, keep moderate)
    local key_buffer_mb=$((AVAILABLE_RAM_FOR_MYSQL * 5 / 100))
    if [[ $key_buffer_mb -lt 32 ]]; then key_buffer_mb=32; fi
    if [[ $key_buffer_mb -gt 256 ]]; then key_buffer_mb=256; fi
    
    # Temporary table sizes
    local tmp_table_mb
    case "$WORKLOAD_TYPE" in
        analytical)
            tmp_table_mb=$((AVAILABLE_RAM_FOR_MYSQL * 10 / 100))
            ;;
        development)
            # Development: Small temp tables for testing
            tmp_table_mb=$((AVAILABLE_RAM_FOR_MYSQL * 3 / 100))
            ;;
        multiservice)
            # Multi-service: Conservative temp table sizing
            tmp_table_mb=$((AVAILABLE_RAM_FOR_MYSQL * 4 / 100))
            ;;
        *)
            tmp_table_mb=$((AVAILABLE_RAM_FOR_MYSQL * 5 / 100))
            ;;
    esac
    if [[ $tmp_table_mb -lt 64 ]]; then tmp_table_mb=64; fi
    if [[ $tmp_table_mb -gt 1024 ]]; then tmp_table_mb=1024; fi
    
    # Sort buffer and read buffer
    local sort_buffer_mb=4
    local read_buffer_mb=2
    case "$WORKLOAD_TYPE" in
        analytical)
            sort_buffer_mb=16
            read_buffer_mb=8
            ;;
        development)
            sort_buffer_mb=2
            read_buffer_mb=1
            ;;
        multiservice)
            sort_buffer_mb=3
            read_buffer_mb=2
            ;;
    esac
    
    # Table cache
    local table_cache
    case "$WORKLOAD_TYPE" in
        web|oltp)
            table_cache=$((CPU_CORES * 500))
            ;;
        development)
            # Development: Smaller table cache for testing
            table_cache=$((CPU_CORES * 200))
            ;;
        multiservice)
            # Multi-service: Moderate table cache
            table_cache=$((CPU_CORES * 250))
            ;;
        *)
            table_cache=$((CPU_CORES * 300))
            ;;
    esac
    if [[ $table_cache -lt 1000 ]]; then table_cache=1000; fi
    if [[ $table_cache -gt 8000 ]]; then table_cache=8000; fi
    
    settings_array+=(
        "key_buffer_size=${key_buffer_mb}M"
        "tmp_table_size=${tmp_table_mb}M"
        "max_heap_table_size=${tmp_table_mb}M"
        "sort_buffer_size=${sort_buffer_mb}M"
        "read_buffer_size=${read_buffer_mb}M"
        "table_open_cache=$table_cache"
    )
    
    printf '%s\n' "${settings_array[@]}"
}

# Function to calculate InnoDB settings
calculate_innodb_settings() {
    local settings_array=()
    local buffer_pool_mb
    buffer_pool_mb=$(calculate_innodb_buffer_pool)
    local buffer_pool_instances
    buffer_pool_instances=$(calculate_buffer_pool_instances "$buffer_pool_mb")
    
    # Log file size (25% of buffer pool, but reasonable bounds)
    local log_file_mb=$((buffer_pool_mb / 4))
    if [[ $log_file_mb -lt 64 ]]; then log_file_mb=64; fi
    if [[ $log_file_mb -gt 2048 ]]; then log_file_mb=2048; fi
    
    # Log buffer size
    local log_buffer_mb=$((log_file_mb / 8))
    if [[ $log_buffer_mb -lt 8 ]]; then log_buffer_mb=8; fi
    if [[ $log_buffer_mb -gt 64 ]]; then log_buffer_mb=64; fi
    
    # Thread concurrency
    local thread_concurrency=$((CPU_CORES * 2))
    
    # IO capacity based on disk type
    local io_capacity=200
    local read_io_threads=4
    local write_io_threads=4
    
    if [[ "$DISK_TYPE" == "SSD" ]]; then
        io_capacity=2000
        read_io_threads=8
        write_io_threads=8
    fi
    
    settings_array+=(
        "innodb_buffer_pool_size=${buffer_pool_mb}M"
        "innodb_buffer_pool_instances=$buffer_pool_instances"
        "innodb_log_file_size=${log_file_mb}M"
        "innodb_log_buffer_size=${log_buffer_mb}M"
        "innodb_thread_concurrency=$thread_concurrency"
        "innodb_io_capacity=$io_capacity"
        "innodb_read_io_threads=$read_io_threads"
        "innodb_write_io_threads=$write_io_threads"
    )
    
    # Workload-specific settings
    case "$WORKLOAD_TYPE" in
        oltp)
            settings_array+=(
                "innodb_flush_log_at_trx_commit=2"
                "innodb_flush_method=O_DIRECT"
            )
            ;;
        analytical)
            settings_array+=(
                "innodb_flush_log_at_trx_commit=0"
                "innodb_flush_method=O_DIRECT"
                "innodb_stats_on_metadata=0"
            )
            ;;
        development)
            settings_array+=(
                "innodb_flush_log_at_trx_commit=2"
                "innodb_file_format=Barracuda"
                "innodb_large_prefix=1"
            )
            ;;
        multiservice)
            settings_array+=(
                "innodb_flush_log_at_trx_commit=1"
                "innodb_flush_method=O_DIRECT"
                "innodb_adaptive_hash_index=0"
            )
            ;;
        *)
            settings_array+=(
                "innodb_flush_log_at_trx_commit=1"
            )
            ;;
    esac
    
    printf '%s\n' "${settings_array[@]}"
}

# Function to generate optimized configuration
generate_optimized_config() {
    print_info "Generating optimized MariaDB configuration..."
    
    local max_connections
    max_connections=$(calculate_max_connections)
    local query_cache_size_mb
    query_cache_size_mb=$(calculate_query_cache_size)
    local thread_cache_size=$((max_connections / 8))
    if [[ $thread_cache_size -gt 100 ]]; then thread_cache_size=100; fi
    
    # Create optimized configuration
    cat > "$TEMP_CONFIG" << EOF
####
#
#    File: 50-server.cnf (Optimized)
#    Generated by: Bashmin MariaDB Optimizer
#    Generated on: $(date)
#    System specs: ${TOTAL_RAM_MB}MB RAM, ${CPU_CORES} CPU cores, ${DISK_TYPE} storage
$(if [[ $MAX_RAM_MB -gt 0 ]]; then echo "#    RAM limit: ${MAX_RAM_MB}MB (user-defined)"; fi)
$(if [[ $MAX_CPU_CORES -gt 0 ]]; then echo "#    CPU limit: $MAX_CPU_CORES cores (user-defined)"; fi)
#    Workload type: $WORKLOAD_TYPE
#    
#    This configuration has been automatically optimized based on
#    your system hardware and workload requirements.
#
##

[server]

[mysqld]

#
# * Basic Settings
#
user            = mysql
pid-file        = /var/run/mysqld/mysqld.pid
socket          = /var/run/mysqld/mysqld.sock
port            = 3306
basedir         = /usr
datadir         = /var/lib/mysql
tmpdir          = /tmp
lc-messages-dir = /usr/share/mysql
skip-external-locking
bind-address    = 127.0.0.1
skip-name-resolve

#
# * Connection and Thread Settings (Optimized)
#
max_connections         = $max_connections
thread_cache_size       = $thread_cache_size
thread_stack           = 256K
wait_timeout           = 1800
interactive_timeout    = 1800
connect_timeout        = 10
back_log              = 128

#
# * Memory Settings (Hardware Optimized)
#
$(calculate_memory_settings)

#
# * Query Cache Configuration (Workload Optimized)
#
query_cache_type        = 1
query_cache_size        = ${query_cache_size_mb}M
query_cache_limit       = 4M

#
# * InnoDB Settings (Performance Optimized)
#
default-storage-engine  = InnoDB
innodb_file_per_table   = 1
$(calculate_innodb_settings)

#
# * Logging Configuration
#
log_error = /var/log/mysql/error.log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mariadb-slow.log
long_query_time = 2
log_slow_verbosity = query_plan
expire_logs_days = 10
max_binlog_size = 100M

#
# * Security and Performance Features
#
local-infile = 0
performance-schema = 1
event_scheduler = ON
max_allowed_packet = 256M
open_files_limit = 65535

#
# * Character Sets
#
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci

#
# * Workload-Specific Optimizations
#
EOF

    # Add workload-specific settings
    case "$WORKLOAD_TYPE" in
        web)
            cat >> "$TEMP_CONFIG" << EOF
# Web application optimizations
query_cache_type = 1
concurrent_insert = 2
delay_key_write = ON
EOF
            ;;
        oltp)
            cat >> "$TEMP_CONFIG" << EOF
# OLTP optimizations
transaction-isolation = READ-COMMITTED
innodb_lock_wait_timeout = 10
EOF
            ;;
        analytical)
            cat >> "$TEMP_CONFIG" << EOF
# Analytical workload optimizations
max_join_size = 4294967295
tmp_disk_table_size = 2G
group_concat_max_len = 1048576
EOF
            ;;
        development)
            cat >> "$TEMP_CONFIG" << EOF
# Development environment optimizations
general_log = 0
slow_query_log = 1
long_query_time = 5
query_cache_type = 1
sql_mode = STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO
innodb_strict_mode = 1
EOF
            ;;
        multiservice)
            cat >> "$TEMP_CONFIG" << EOF
# Multi-service server optimizations
query_cache_type = 1
concurrent_insert = 2
low_priority_updates = 1
max_user_connections = 50
innodb_thread_sleep_delay = 10000
EOF
            ;;
    esac
    
    cat >> "$TEMP_CONFIG" << EOF

[embedded]

[mariadb]

[mariadb-10.1]

EOF
    
    print_success "Optimized configuration generated"
}

# Function to show configuration preview
show_config_preview() {
    print_info "Configuration Preview:"
    echo "=========================="
    
    local buffer_pool_mb
    buffer_pool_mb=$(calculate_innodb_buffer_pool)
    local max_connections
    max_connections=$(calculate_max_connections)
    local query_cache_mb
    query_cache_mb=$(calculate_query_cache_size)
    
    echo "System Resources:"
    echo "  Total RAM: ${TOTAL_RAM_MB}MB"
    if [[ $MAX_RAM_MB -gt 0 ]]; then
        echo "  RAM Limit: ${MAX_RAM_MB}MB (user-defined)"
    fi
    echo "  Available for MySQL: ${AVAILABLE_RAM_FOR_MYSQL}MB"
    echo "  CPU Cores: $CPU_CORES"
    if [[ $MAX_CPU_CORES -gt 0 ]]; then
        echo "  CPU Limit: $MAX_CPU_CORES cores (user-defined)"
    fi
    echo "  Storage Type: $DISK_TYPE"
    echo ""
    echo "Key Optimizations:"
    echo "  InnoDB Buffer Pool: ${buffer_pool_mb}MB"
    echo "  Max Connections: $max_connections"
    echo "  Query Cache: ${query_cache_mb}MB"
    echo "  Thread Cache: $((max_connections / 8))"
    echo "  Workload Type: $WORKLOAD_TYPE"
    echo ""
    
    if [[ $MAX_RAM_MB -gt 0 ]] || [[ $MAX_CPU_CORES -gt 0 ]]; then
        echo "Resource Limits Applied:"
        if [[ $MAX_RAM_MB -gt 0 ]]; then
            echo "  RAM capped at: ${MAX_RAM_MB}MB"
        fi
        if [[ $MAX_CPU_CORES -gt 0 ]]; then
            echo "  CPU capped at: $MAX_CPU_CORES cores"
        fi
        echo ""
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "Generated configuration:"
        echo "========================"
        cat "$TEMP_CONFIG"
    fi
}

# Function to backup current configuration
backup_current_config() {
    if [[ -f "$CONFIG_TARGET" ]]; then
        execute_command "sudo cp '$CONFIG_TARGET' '$CONFIG_BACKUP'" "Backing up current configuration"
        print_success "Current configuration backed up to: $CONFIG_BACKUP"
    fi
}

# Function to apply optimized configuration
apply_optimized_config() {
    print_info "Applying optimized configuration..."
    
    backup_current_config
    execute_command "sudo cp '$TEMP_CONFIG' '$CONFIG_TARGET'" "Installing optimized configuration"
    execute_command "sudo chown root:root '$CONFIG_TARGET'" "Setting configuration ownership"
    execute_command "sudo chmod 644 '$CONFIG_TARGET'" "Setting configuration permissions"
    
    print_success "Optimized configuration applied"
}

# Function to restart MariaDB service
restart_mariadb() {
    if [[ "$RESTART_SERVICE" == true ]]; then
        print_info "Restarting MariaDB service..."
        execute_command "sudo systemctl restart $MARIADB_SERVICE" "Restarting MariaDB service"
        
        # Wait for service to start
        sleep 3
        local status
        status=$(get_service_status "$MARIADB_SERVICE")
        if [[ "$status" == "active" ]]; then
            print_success "MariaDB service restarted successfully"
        else
            print_error "MariaDB service failed to restart. Status: $status"
            print_warning "Configuration backup available at: $CONFIG_BACKUP"
            return 1
        fi
    else
        print_warning "MariaDB service restart skipped. Manual restart required to apply changes."
    fi
}

# Function to validate configuration
validate_configuration() {
    print_info "Validating optimized configuration..."
    
    # Test configuration syntax
    if sudo mysqld --help --verbose > /dev/null 2>&1; then
        print_success "Configuration syntax is valid"
    else
        print_error "Configuration syntax validation failed"
        return 1
    fi
    
    # If service is running, test connection
    local status
    status=$(get_service_status "$MARIADB_SERVICE")
    if [[ "$status" == "active" ]]; then
        if sudo mysql -e "SELECT 1;" > /dev/null 2>&1; then
            print_success "Database connection test passed"
        else
            print_error "Database connection test failed"
            return 1
        fi
        
        # Show some key variables
        print_info "Current configuration values:"
        sudo mysql -e "
            SELECT 
                @@innodb_buffer_pool_size / 1024 / 1024 as 'Buffer Pool (MB)',
                @@max_connections as 'Max Connections',
                @@query_cache_size / 1024 / 1024 as 'Query Cache (MB)',
                @@thread_cache_size as 'Thread Cache'
        " 2>/dev/null || true
    fi
    
    return 0
}

# Function to cleanup temporary files
cleanup() {
    if [[ -f "$TEMP_CONFIG" ]]; then
        rm -f "$TEMP_CONFIG"
    fi
}

# Function to show optimization summary
show_optimization_summary() {
    cat << EOF

${GREEN}=== MariaDB Optimization Complete ===${NC}

${BLUE}System Analysis:${NC}
- RAM: ${TOTAL_RAM_MB}MB total, ${AVAILABLE_RAM_FOR_MYSQL}MB allocated to MySQL
$(if [[ $MAX_RAM_MB -gt 0 ]]; then echo "- RAM Limit: ${MAX_RAM_MB}MB (user-defined)"; fi)
- CPU: $CPU_CORES cores
$(if [[ $MAX_CPU_CORES -gt 0 ]]; then echo "- CPU Limit: $MAX_CPU_CORES cores (user-defined)"; fi)
- Storage: ${DISK_TYPE}
- Workload: ${WORKLOAD_TYPE}

${BLUE}Key Optimizations Applied:${NC}
- InnoDB Buffer Pool: $(calculate_innodb_buffer_pool)MB
- Max Connections: $(calculate_max_connections)
- Query Cache: $(calculate_query_cache_size)MB
- Configuration optimized for ${WORKLOAD_TYPE} workload

${BLUE}Files:${NC}
- Active config: $CONFIG_TARGET
- Backup: $CONFIG_BACKUP

${BLUE}Next Steps:${NC}
1. Monitor database performance with tools like mytop or mysqladmin
2. Review slow query log: /var/log/mysql/mariadb-slow.log
3. Adjust settings if needed based on actual workload patterns
4. Consider periodic re-optimization as workload changes

${YELLOW}Monitoring Commands:${NC}
- Performance: sudo mysql -e "SHOW ENGINE INNODB STATUS\\G"
- Connections: sudo mysql -e "SHOW PROCESSLIST"
- Buffer usage: sudo mysql -e "SHOW ENGINE INNODB STATUS\\G" | grep -A 20 "BUFFER POOL"

EOF
}

# Main optimization function
main() {
    print_info "Starting MariaDB optimization..."
    
    parse_arguments "$@"
    
    # Validate prerequisites
    if ! is_package_installed "mariadb-server"; then
        print_error "MariaDB server is not installed. Please run the install script first."
        exit 1
    fi
    
    gather_system_info
    generate_optimized_config
    show_config_preview
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "Dry run completed. No changes were made."
        cleanup
        exit 0
    fi
    
    # Apply configuration
    if [[ "$AUTO_APPLY" == true ]]; then
        apply_optimized_config
        restart_mariadb
    else
        echo ""
        read -p "Apply this optimized configuration? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            apply_optimized_config
            restart_mariadb
        else
            print_info "Configuration not applied. Generated config saved to: $TEMP_CONFIG"
            exit 0
        fi
    fi
    
    # Validate and show results
    if validate_configuration; then
        show_optimization_summary
        print_success "MariaDB optimization completed successfully!"
    else
        print_error "Configuration validation failed"
        exit 1
    fi
    
    cleanup
}

# Cleanup on exit
trap cleanup EXIT

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
