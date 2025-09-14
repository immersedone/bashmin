#!/bin/bash
#
# Script to set nginx user to www-data
#

echo "Setting Nginx User to www-data"
echo "==============================="
echo

echo "Current nginx user configuration:"
grep -n "^user" /etc/nginx/nginx.conf || echo "No user directive found"
echo

echo "Changing user from 'shadower' to 'www-data'..."
sudo sed -i 's/^user shadower;/user www-data;/' /etc/nginx/nginx.conf
sudo sed -i "s/# Modify Default User to 'shadower'/# Modify Default User to 'www-data'/" /etc/nginx/nginx.conf

echo
echo "Fixing duplicate keepalive_timeout directive..."
if [[ -f /etc/nginx/conf.d/bashmin-ratelimiting.conf ]]; then
    sudo sed -i '/^keepalive_timeout/d' /etc/nginx/conf.d/bashmin-ratelimiting.conf
    echo "✅ Removed duplicate keepalive_timeout from rate limiting config"
fi

echo
echo "Updated configuration:"
grep -A1 -B1 "^user" /etc/nginx/nginx.conf
echo

echo "Testing nginx configuration..."
if sudo nginx -t; then
    echo
    echo "✅ Nginx configuration test passed!"
    echo
    echo "Reloading nginx..."
    sudo systemctl reload nginx
    echo "✅ Nginx reloaded successfully!"
else
    echo
    echo "❌ Nginx configuration test failed!"
fi

echo
echo "Current nginx process user:"
ps aux | grep nginx | grep -v grep | head -3