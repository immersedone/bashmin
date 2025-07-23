#!/bin/bash
#
# Script: install.sh
# Description: Install FrankenPHP Server
# Usage: ./install.sh [OPTIONS]
#

set -e

echo "🚀 Installing FrankenPHP..."

# Install dependencies
apt update
apt install -y curl unzip php-cli php-curl php-mbstring php-xml php-mysql php-pgsql php-sqlite3 php-bcmath php-gd

# Create directories
mkdir -p /etc/frankenphp/vhosts
mkdir -p /var/www/vhosts

# Download FrankenPHP binary
curl -Lo /usr/local/bin/frankenphp https://github.com/dunglas/frankenphp/releases/latest/download/frankenphp-linux-amd64
chmod +x /usr/local/bin/frankenphp

# Create main Caddyfile
cat <<EOF > /etc/frankenphp/Caddyfile
import vhosts/*
EOF

# Create systemd service
cat <<EOF > /etc/systemd/system/frankenphp.service
[Unit]
Description=FrankenPHP Web Server
After=network.target

[Service]
ExecStart=/usr/local/bin/frankenphp run --config /etc/frankenphp/Caddyfile
WorkingDirectory=/var/www
Restart=on-failure
User=www-data
Group=www-data
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecReload=/bin/kill -USR1 \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable frankenphp
systemctl start frankenphp

echo "✅ FrankenPHP installed and started."