#!/bin/sh
# This script runs as root
set -e

# --- 1. AIDE (HIDS) Initialization ---
# Check if the AIDE database exists. If not, create it.
# This is the "first-run" task you correctly identified.
echo "AIDE database. Initializing..."
echo "This may take a minute..."
/usr/bin/aide --init > /dev/null
echo "AIDE database initialized. Copyingm..."
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db.gz

echo "Running baseline AIDE check..."
/usr/bin/aide --check | jq -c . >> /var/log/aide.json || true

# --- 2. Start Services ---
echo "Starting sshd service on port 3025..."
/usr/sbin/sshd

echo "Starting crond service for daily HIDS checks..."
/usr/sbin/crond

echo "Starting chronyd (NTP) service..."
/usr/sbin/chronyd -f /etc/chrony/chrony.conf

echo "Starting CoreDNS service..."
/usr/bin/coredns -conf /etc/coredns/Corefile &

#    This runs it in the background using a config file we will provide.
echo "Starting fluent-bit service..."
/usr/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &

# --- 3. Keep Container Alive ---
echo "DNS/NTP server is running. Awaiting connections."
exec "$@"
