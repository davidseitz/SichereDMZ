#!/bin/sh
# This script runs as root
set -e

# --- 1. AIDE (HIDS) Initialization ---
# Check if the AIDE database exists. If not, create it.
# This is the "first-run" task you correctly identified.
DB_PATH="/var/lib/aide/aide.db.gz"
if [ ! -f "$DB_PATH" ]; then
    echo "AIDE database not found. Initializing..."
    echo "This may take a minute..."
    /usr/bin/aide --init
    echo "AIDE database initialized. Copying to $DB_PATH..."
    mv /var/lib/aide/aide.db.new.gz "$DB_PATH"
else
    echo "AIDE database already exists."
fi

# --- 2. Start Services ---
# Start the OpenSSH server daemon
echo "Starting sshd service on port 3025..."
/usr/sbin/sshd

# Start the 'cron' daemon in the foreground (it forks itself)
# This will run our daily 'aide --check' script
echo "Starting crond service for daily HIDS checks..."
/usr/sbin/crond

# (When ready, we will add 'fluent-bit' here)

# --- 3. Keep Container Alive ---
echo "Bastion host is running. Awaiting connections."
exec "$@"
