#!/bin/sh
# This script runs as root
set -e

# --- 1. AIDE (HIDS) Initialization ---
# Check if the AIDE database exists. If not, create it.
# This is the "first-run" task you correctly identified.
echo "AIDE database. Initializing..."
echo "This may take a minute..."
/usr/bin/aide --init
echo "AIDE database initialized. Copyingm..."
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db.gz

# Start the OpenSSH server daemon
echo "Starting sshd service on port 3025..."
/usr/sbin/sshd

# Start the 'cron' daemon in the foreground (it forks itself)
# This will run our daily 'aide --check' script
echo "Starting crond service for daily HIDS checks..."
/usr/sbin/crond

#    This runs it in the background using a config file we will provide.
echo "Starting fluent-bit service..."
/usr/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &

echo "Starting chrony..."
chronyd -f /etc/chrony/chrony.conf


# --- 3. Keep Container Alive ---
echo "Bastion host is running. Awaiting connections."
exec "$@"
