#!/bin/sh
# This script runs as root
set -e

# 1. Generate SSH host keys
ssh-keygen -A

# ---  AIDE (HIDS) Initialization ---
# Check if the AIDE database exists. If not, create it.
# This is the "first-run" task you correctly identified.
echo "AIDE database. Initializing..."
echo "This may take a minute..."
/usr/bin/aide --init > /dev/null
echo "AIDE database initialized. Copyingm..."
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db.gz

echo "Running baseline AIDE check..."
/usr/bin/aide --check | jq -c . >> /var/log/aide.json || true

# Start the 'cron' daemon in the foreground (it forks itself)
# This will run our daily 'aide --check' script
echo "Starting crond service for daily HIDS checks..."
/usr/sbin/crond

echo "Starting chrony..."
chronyd -f /etc/chrony/chrony.conf

# 2. Start the OpenSSH server daemon
echo "Starting sshd service on port 3025..."
/usr/sbin/sshd

# 3. [NEW] Start the Fluent Bit service
#    This runs it in the background using a config file we will provide.
echo "Starting fluent-bit service..."
/usr/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &

# 4. [FINAL] Start the Loki service (in the foreground)
#    'exec' ensures it becomes the main container process.
echo "Starting Loki service as user 'loki'..."
exec su-exec loki /usr/bin/loki "$@"
