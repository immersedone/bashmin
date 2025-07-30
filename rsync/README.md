# Rsync Backup and Synchronization Script

## Overview

The `backup.sh` script provides a comprehensive backup and synchronization solution using rsync for both local and remote operations. It supports multiple sync modes, incremental backups, snapshots, and advanced configuration options suitable for enterprise environments.

## Features

### Sync Modes
- **backup**: One-way backup preserving destination files not in source
- **sync**: One-way synchronization making destination identical to source
- **mirror**: Exact mirror synchronization (bidirectional)
- **incremental**: Incremental backup with timestamped snapshots

### Sync Types
- **local**: Local filesystem synchronization
- **remote**: Remote synchronization via SSH
- **bidirectional**: Two-way synchronization (local or remote)

### Advanced Features
- Incremental backups with hard-linked snapshots
- SSH key generation and management
- Bandwidth limiting and transfer optimization
- Comprehensive exclude/include pattern support
- Email and Slack notifications
- Pre/post-sync script execution
- Daemon mode with cron scheduling
- Retry mechanisms with exponential backoff
- Comprehensive logging and statistics

## Installation

### Quick Install
```bash
# Navigate to rsync directory
cd /var/www/vhosts/bashmin/rsync

# Make executable
chmod +x backup.sh

# Create system structure
sudo ./backup.sh --source /tmp --destination /tmp --dry-run
```

### System Setup
The script automatically creates the following system structure:

```
/etc/bashmin/rsync/           # Configuration files
├── excludes.conf            # Default exclude patterns
└── targets.conf             # Backup targets (future)

/var/log/bashmin/rsync/       # Log directory
└── sync-YYYYMMDD_HHMMSS.log # Timestamped logs

/opt/bashmin/backups/         # Default backup directory

/var/lib/bashmin/rsync/       # State and metadata

/home/rsync-backup/.ssh/      # SSH keys for remote operations
├── id_rsa                   # Private key
└── id_rsa.pub               # Public key
```

## Usage Examples

### Basic Local Backup
```bash
# Simple local backup
./backup.sh --source /home/user --destination /backup/user

# With verbose output and progress
./backup.sh --source /var/www --destination /backup/www --verbose --progress
```

### Remote Backup Operations
```bash
# Remote backup with SSH key
./backup.sh --source /var/www --destination /backup/www \
            --remote-host server.example.com \
            --ssh-key ~/.ssh/backup_key

# Remote backup with specific user and port
./backup.sh --source /data --destination /backup/data \
            --remote-host backup.company.com \
            --remote-user backup-user \
            --remote-port 2022
```

### Incremental Backups with Snapshots
```bash
# Incremental backup with default snapshots
./backup.sh --source /data --destination /backup/data --incremental

# Incremental with custom snapshot directory
./backup.sh --source /srv/www --destination /backup/www \
            --incremental --snapshot-dir /backup/snapshots \
            --max-snapshots 14
```

### Sync with Exclusions
```bash
# Exclude patterns and file types
./backup.sh --source /home --destination /backup/home \
            --exclude "*.tmp" --exclude "*.log" --exclude ".git" \
            --bandwidth-limit 1000k

# Exclude from file
./backup.sh --source /var --destination /backup/var \
            --exclude-file /etc/bashmin/rsync/excludes.conf
```

### Bidirectional Synchronization
```bash
# Local bidirectional sync
./backup.sh --source /srv/data --destination /backup/data \
            --sync-type bidirectional --sync-mode mirror

# Remote bidirectional sync
./backup.sh --source /srv/shared --destination /backup/shared \
            --sync-type bidirectional --remote-host sync-server.com
```

### Automation and Notifications
```bash
# With email notifications
./backup.sh --source /data --destination /backup \
            --email admin@company.com

# With Slack notifications
./backup.sh --source /var/www --destination /backup/www \
            --slack-webhook "https://hooks.slack.com/services/..."

# With pre/post scripts
./backup.sh --source /database --destination /backup/db \
            --pre-sync-script /scripts/db-backup-prep.sh \
            --post-sync-script /scripts/cleanup.sh
```

### Configuration File Usage
```bash
# Using configuration file
./backup.sh --config-file /etc/bashmin/rsync/web-backup.conf

# Configuration file example
cat > /etc/bashmin/rsync/web-backup.conf << 'EOF'
SOURCE_PATH="/var/www"
DESTINATION_PATH="/backup/www"
REMOTE_HOST="backup.example.com"
EXCLUDE_PATTERNS=("*.tmp" "*.log" ".git" "cache/*")
EMAIL_NOTIFICATIONS=true
NOTIFICATION_EMAIL="admin@company.com"
COMPRESS=true
VERIFY_CHECKSUMS=true
MAX_SNAPSHOTS=7
EOF
```

### Dry Run and Testing
```bash
# Preview changes without executing
./backup.sh --source /data --destination /backup --dry-run --verbose

# Test SSH connectivity
./backup.sh --source /tmp --destination /tmp \
            --remote-host server.com --dry-run
```

## Configuration Options

### Source and Destination
| Option | Description | Example |
|--------|-------------|---------|
| `--source PATH` | Source directory/file path | `/var/www` |
| `--destination PATH` | Destination directory path | `/backup/www` |
| `--remote-host HOST` | Remote host for SSH sync | `backup.example.com` |
| `--remote-user USER` | Remote SSH username | `backup-user` |
| `--remote-port PORT` | Remote SSH port | `2022` |
| `--ssh-key PATH` | SSH private key path | `~/.ssh/backup_key` |

### Sync Configuration
| Option | Description | Values |
|--------|-------------|--------|
| `--sync-mode MODE` | Synchronization mode | `backup`, `sync`, `mirror`, `incremental` |
| `--sync-type TYPE` | Synchronization type | `local`, `remote`, `bidirectional` |
| `--exclude PATTERN` | Exclude pattern | `"*.tmp"`, `".git"` |
| `--include PATTERN` | Include pattern | `"*.conf"` |
| `--exclude-file FILE` | File with exclude patterns | `/etc/rsync-excludes` |

### Transfer Options
| Option | Description | Example |
|--------|-------------|---------|
| `--bandwidth-limit RATE` | Bandwidth limitation | `1000k`, `2m` |
| `--parallel NUM` | Parallel transfers | `4` |
| `--timeout SECONDS` | Transfer timeout | `3600` |
| `--retry-count NUM` | Retry attempts | `3` |
| `--retry-delay SEC` | Retry delay | `30` |

### Backup Features
| Option | Description | Example |
|--------|-------------|---------|
| `--incremental` | Enable incremental mode | - |
| `--snapshot-dir DIR` | Snapshot directory | `/backup/snapshots` |
| `--max-snapshots NUM` | Maximum snapshots | `14` |
| `--backup-suffix SUFFIX` | Backup file suffix | `.bak` |

## Incremental Backups

### How It Works
Incremental backups create timestamped snapshots while using hard links for unchanged files, providing:
- Space efficiency (unchanged files share inodes)
- Fast incremental operations
- Point-in-time recovery options
- Automatic cleanup of old snapshots

### Snapshot Structure
```
/backup/snapshots/
├── snapshot_20241201_020000/   # Full backup structure
├── snapshot_20241202_020000/   # Incremental changes
├── snapshot_20241203_020000/   # Incremental changes
└── latest -> snapshot_20241203_020000  # Symlink to latest
```

### Recovery Examples
```bash
# Restore from latest snapshot
cp -al /backup/snapshots/latest/data /restore/data

# Restore from specific date
cp -al /backup/snapshots/snapshot_20241201_020000/data /restore/data

# Compare snapshots
diff -r /backup/snapshots/snapshot_20241201_020000 \
        /backup/snapshots/snapshot_20241202_020000
```

## SSH Configuration

### Automatic Key Generation
The script automatically generates SSH keys if none exist:
```bash
# Generated key location
/home/rsync-backup/.ssh/id_rsa
/home/rsync-backup/.ssh/id_rsa.pub
```

### Manual Key Setup
```bash
# Generate custom key
ssh-keygen -t rsa -b 4096 -f /home/rsync-backup/.ssh/backup_key

# Copy to remote server
ssh-copy-id -i /home/rsync-backup/.ssh/backup_key.pub user@remote-host

# Use with script
./backup.sh --ssh-key /home/rsync-backup/.ssh/backup_key \
            --remote-host remote-host --remote-user user
```

### SSH Configuration File
```bash
# Create SSH config for easier connections
cat > /home/rsync-backup/.ssh/config << 'EOF'
Host backup-server
    HostName backup.example.com
    User backup-user
    Port 2022
    IdentityFile ~/.ssh/backup_key
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
```

## Notifications

### Email Setup
```bash
# Install mail utilities
apt-get install mailutils

# Configure with email
./backup.sh --source /data --destination /backup \
            --email admin@company.com
```

### Slack Integration
```bash
# Get webhook URL from Slack app settings
SLACK_WEBHOOK="https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"

# Use with script
./backup.sh --source /var/www --destination /backup/www \
            --slack-webhook "$SLACK_WEBHOOK"
```

## Pre/Post Sync Scripts

### Pre-Sync Script Example
```bash
# Create database backup preparation script
cat > /scripts/db-backup-prep.sh << 'EOF'
#!/bin/bash
# Stop application services
systemctl stop apache2
systemctl stop mysql

# Create database dump
mysqldump --all-databases > /var/backup/mysql-dump.sql

# Create application backup
tar -czf /var/backup/app-backup.tar.gz /var/www
EOF

chmod +x /scripts/db-backup-prep.sh
```

### Post-Sync Script Example
```bash
# Create cleanup and notification script
cat > /scripts/post-backup.sh << 'EOF'
#!/bin/bash
# Restart services
systemctl start mysql
systemctl start apache2

# Clean old backups
find /var/backup -name "*.sql" -mtime +7 -delete

# Log completion
echo "Backup completed: $(date)" >> /var/log/backup-completion.log

# Send custom notification based on status
if [[ "$SYNC_STATUS" == "completed" ]]; then
    echo "Backup successful for $SYNC_SOURCE" | mail -s "Backup Success" admin@company.com
else
    echo "Backup failed for $SYNC_SOURCE" | mail -s "Backup Failed" admin@company.com
fi
EOF

chmod +x /scripts/post-backup.sh
```

### Environment Variables Available
Pre/post scripts receive these environment variables:
- `SYNC_SOURCE`: Source path
- `SYNC_DESTINATION`: Destination path  
- `SYNC_MODE`: Current sync mode
- `SYNC_STATUS`: `starting` (pre) or `completed`/`failed` (post)

## Automation and Scheduling

### Cron Integration
```bash
# Add to crontab for automated backups
crontab -e

# Daily backup at 2 AM
0 2 * * * /var/www/vhosts/bashmin/rsync/backup.sh --config-file /etc/bashmin/rsync/daily-backup.conf

# Weekly full backup on Sunday at 1 AM
0 1 * * 0 /var/www/vhosts/bashmin/rsync/backup.sh --config-file /etc/bashmin/rsync/weekly-backup.conf --incremental

# Hourly incremental backup during business hours
0 9-17 * * 1-5 /var/www/vhosts/bashmin/rsync/backup.sh --config-file /etc/bashmin/rsync/hourly-backup.conf
```

### Systemd Service
```bash
# Create systemd service for backup daemon
cat > /etc/systemd/system/bashmin-backup.service << 'EOF'
[Unit]
Description=Bashmin Backup Service
After=network.target

[Service]
Type=oneshot
User=rsync-backup
ExecStart=/var/www/vhosts/bashmin/rsync/backup.sh --config-file /etc/bashmin/rsync/default.conf
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create timer for regular execution
cat > /etc/systemd/system/bashmin-backup.timer << 'EOF'
[Unit]
Description=Run Bashmin Backup Service
Requires=bashmin-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start
systemctl daemon-reload
systemctl enable bashmin-backup.timer
systemctl start bashmin-backup.timer
```

## Troubleshooting

### Common Issues

#### SSH Connection Problems
```bash
# Test SSH connectivity manually
ssh -i /home/rsync-backup/.ssh/id_rsa user@remote-host

# Check SSH key permissions
ls -la /home/rsync-backup/.ssh/
chmod 600 /home/rsync-backup/.ssh/id_rsa
chmod 644 /home/rsync-backup/.ssh/id_rsa.pub

# Verify SSH agent
ssh-add -l
```

#### Permission Issues
```bash
# Check rsync user permissions
sudo -u rsync-backup rsync --version

# Fix ownership
chown -R rsync-backup:rsync-backup /home/rsync-backup
chown -R rsync-backup:rsync-backup /opt/bashmin/backups
```

#### Performance Issues
```bash
# Monitor bandwidth usage
./backup.sh --bandwidth-limit 500k --verbose

# Use compression for slow connections
./backup.sh --compress --bandwidth-limit 1000k

# Reduce I/O with ionice
ionice -c 3 ./backup.sh --source /data --destination /backup
```

### Debug Mode
```bash
# Enable verbose logging
./backup.sh --verbose --log-level DEBUG

# Dry run with full output
./backup.sh --dry-run --verbose --stats

# Check logs
tail -f /var/log/bashmin/rsync/sync-*.log
```

### Testing Connectivity
```bash
# Test local paths
./backup.sh --source /tmp --destination /tmp/test --dry-run

# Test remote connectivity
./backup.sh --source /tmp --destination /tmp \
            --remote-host server.com --dry-run

# Verify exclude patterns
./backup.sh --source /var --destination /backup \
            --exclude "*.log" --dry-run --verbose
```

## Performance Optimization

### Network Optimization
```bash
# Limit bandwidth for business hours
./backup.sh --bandwidth-limit 500k    # During business hours
./backup.sh --bandwidth-limit 5m      # During off-hours

# Use compression for slow connections
./backup.sh --compress --bandwidth-limit 1000k

# Optimize SSH connection
./backup.sh --ssh-key ~/.ssh/backup_key \
            --remote-host server.com \
            -o "Compression=yes" \
            -o "CompressionLevel=6"
```

### I/O Optimization
```bash
# Use ionice for lower I/O priority
ionice -c 3 nice -n 19 ./backup.sh --source /data --destination /backup

# Exclude unnecessary files
./backup.sh --exclude "*.tmp" --exclude "*.swp" \
            --exclude ".git" --exclude "node_modules"

# Use checksum only when necessary
./backup.sh --no-checksum  # Faster, relies on size and timestamp
```

### Large Dataset Handling
```bash
# Split large transfers
./backup.sh --source /data/part1 --destination /backup/part1
./backup.sh --source /data/part2 --destination /backup/part2

# Use incremental mode for large datasets
./backup.sh --incremental --snapshot-dir /backup/snapshots

# Parallel transfers (use with caution)
./backup.sh --parallel 2  # Limited benefit for single rsync
```

## Integration Examples

### Web Application Backup
```bash
# Complete web application backup
cat > /etc/bashmin/rsync/webapp-backup.conf << 'EOF'
SOURCE_PATH="/var/www/html"
DESTINATION_PATH="/backup/webapp"
REMOTE_HOST="backup.company.com"
EXCLUDE_PATTERNS=("cache/*" "tmp/*" "*.log" ".git")
EMAIL_NOTIFICATIONS=true
NOTIFICATION_EMAIL="webmaster@company.com"
PRE_SYNC_SCRIPT="/scripts/webapp-prep.sh"
POST_SYNC_SCRIPT="/scripts/webapp-cleanup.sh"
INCREMENTAL_BACKUP=true
MAX_SNAPSHOTS=14
EOF
```

### Database Server Backup
```bash
# Database backup with dump integration
cat > /scripts/db-backup.sh << 'EOF'
#!/bin/bash
# Database backup preparation
mysqldump --all-databases --single-transaction > /var/backup/mysql-$(date +%Y%m%d).sql
tar -czf /var/backup/mysql-data.tar.gz /var/lib/mysql

# Run rsync backup
/var/www/vhosts/bashmin/rsync/backup.sh \
  --source /var/backup \
  --destination /backup/database \
  --remote-host db-backup.company.com \
  --incremental \
  --email admin@company.com

# Cleanup local dumps older than 3 days
find /var/backup -name "mysql-*.sql" -mtime +3 -delete
EOF
```

### Multi-Server Sync
```bash
# Sync to multiple destinations
cat > /scripts/multi-sync.sh << 'EOF'
#!/bin/bash
SERVERS=("backup1.company.com" "backup2.company.com" "offsite.company.com")

for server in "${SERVERS[@]}"; do
    echo "Syncing to $server..."
    /var/www/vhosts/bashmin/rsync/backup.sh \
      --source /var/data \
      --destination /backup/data \
      --remote-host "$server" \
      --email "admin@company.com"
done
EOF
```

## Security Considerations

### SSH Security
```bash
# Use dedicated backup keys
ssh-keygen -t rsa -b 4096 -f /home/rsync-backup/.ssh/backup_key

# Restrict SSH key usage (add to authorized_keys)
command="/usr/bin/rsync --server --daemon .",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding ssh-rsa AAAAB3...

# Use SSH certificates for better key management
ssh-keygen -s ca_key -I backup-cert -V +52w /home/rsync-backup/.ssh/backup_key.pub
```

### Access Control
```bash
# Limit rsync user permissions
usermod -s /bin/rbash rsync-backup

# Restrict file access
chmod 750 /opt/bashmin/backups
chown rsync-backup:rsync-backup /opt/bashmin/backups

# Use sudo for specific operations only
echo "rsync-backup ALL=(root) NOPASSWD: /bin/systemctl start *, /bin/systemctl stop *" > /etc/sudoers.d/rsync-backup
```

### Network Security
```bash
# Use VPN for remote backups
./backup.sh --remote-host 10.0.1.100  # VPN address

# Firewall rules for backup traffic
ufw allow from backup-server.com to any port 22

# Monitor backup connections
tail -f /var/log/auth.log | grep rsync-backup
```

## Monitoring and Logging

### Log Analysis
```bash
# View recent backup logs
ls -la /var/log/bashmin/rsync/

# Monitor active transfers
tail -f /var/log/bashmin/rsync/sync-$(date +%Y%m%d)*.log

# Search for errors
grep -i error /var/log/bashmin/rsync/*.log

# Statistics summary
grep "Number of files" /var/log/bashmin/rsync/*.log
```

### Monitoring Scripts
```bash
# Create backup monitoring script
cat > /scripts/backup-monitor.sh << 'EOF'
#!/bin/bash
LOG_DIR="/var/log/bashmin/rsync"
ALERT_EMAIL="admin@company.com"

# Check for recent successful backups
if ! find "$LOG_DIR" -name "*.log" -mtime -1 -exec grep -l "completed successfully" {} \; | grep -q .; then
    echo "No successful backups in last 24 hours" | mail -s "Backup Alert" "$ALERT_EMAIL"
fi

# Check for errors
if find "$LOG_DIR" -name "*.log" -mtime -1 -exec grep -l "error\|failed" {} \; | grep -q .; then
    echo "Backup errors detected in last 24 hours" | mail -s "Backup Error Alert" "$ALERT_EMAIL"
fi
EOF

# Schedule monitoring
echo "0 8 * * * /scripts/backup-monitor.sh" | crontab -
```

## Best Practices

### Planning
- Test backup procedures regularly
- Document restore procedures  
- Monitor backup completion and errors
- Implement 3-2-1 backup strategy (3 copies, 2 different media, 1 offsite)

### Configuration
- Use configuration files for complex setups
- Implement proper exclude patterns
- Test with dry-run before production
- Use incremental backups for large datasets

### Security
- Use dedicated SSH keys for backups
- Implement proper access controls
- Monitor backup access and transfers
- Encrypt sensitive backup data

### Performance
- Schedule backups during off-peak hours
- Use bandwidth limiting during business hours
- Implement proper retry mechanisms
- Monitor and optimize transfer performance

This comprehensive backup solution provides enterprise-grade functionality while maintaining the simplicity and reliability expected from the bashmin suite. 🚀
