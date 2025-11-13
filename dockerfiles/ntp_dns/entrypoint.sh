#!/bin/sh
# This script runs as root
set -e

# --- 1. AIDE (HIDS) Initialization ---
DB_PATH="/var/lib/aide/aide.db.gz"
if [ ! -f "$DB_PATH" ]; then
    echo "AIDE database not found. Initializing..."
    /usr/bin/aide --init
    echo "AIDE database initialized. Copying to $DB_PATH..."
    mv /var/lib/aide/aide.db.new.gz "$DB_PATH"
else
    echo "AIDE database already exists."
fi

# --- 2. Start Services ---
echo "Starting sshd service on port 3025..."
/usr/sbin/sshd

echo "Starting crond service for daily HIDS checks..."
/usr/sbin/crond

echo "Starting chronyd (NTP) service..."
/usr/sbin/chronyd -f /etc/chrony/chrony.conf

echo "Starting CoreDNS service..."
/usr/sbin/coredns -conf /etc/coredns/Corefile &

# (fluent-bit is installed but not started, per our plan)

# --- 3. Keep Container Alive ---
echo "DNS/NTP server is running. Awaiting connections."
exec "$@"
