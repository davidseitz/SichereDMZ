#!/bin/sh
# This script runs as root
set -e

# --- 1. AIDE (HIDS) Initialization ---
DB_PATH="/var/lib/aide/aide.db.gz"
echo "AIDE database not found. Initializing..."
/usr/bin/aide --init --config="/etc/aide.conf"
echo "AIDE database initialized. Copying to $DB_PATH..."
mv /var/lib/aide/aide.db.new "$DB_PATH"

# --- 2. Start Services ---
echo "Starting sshd service on port 3025..."
/usr/sbin/sshd

echo "Starting crond service for daily HIDS checks..."
# 'cron' is the Debian daemon name
/usr/sbin/cron

# (fluent-bit, suricata, nftables are installed but not started)

# --- 3. Keep Container Alive ---
echo "Edge-Router is running. Awaiting connections."
exec "$@"
