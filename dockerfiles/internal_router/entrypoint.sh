#!/bin/sh
# This script runs as root
set -e

# --- 1. Start Services ---
echo "Starting sshd service on port 3025..."
/usr/sbin/sshd

echo "Starting crond service for daily HIDS checks..."
# 'cron' is the Debian daemon name
/usr/sbin/cron

# A. Nftables (Firewall)
# Note: Container must run with --cap-add=NET_ADMIN
echo "Loading Nftables rules..."
if [ -f /etc/nftables.conf ]; then
    /usr/sbin/nft -f /etc/nftables.conf
else
    echo "WARNING: /etc/nftables.conf not found. No firewall rules loaded."
fi

# --- 2. AIDE (HIDS) Initialization ---
DB_PATH="/var/lib/aide/aide.db.gz"
echo "AIDE database not found. Initializing..."
/usr/bin/aide --init --config="/etc/aide.conf" > /dev/null
echo "AIDE database initialized. Copying to $DB_PATH..."
mv /var/lib/aide/aide.db.new "$DB_PATH"

echo "Running baseline AIDE check..."
/usr/bin/aide --check | jq -c . >> /var/log/aide.json || true

# # B. Fluent-bit (Logging)
# echo "Starting Fluent-bit..."
# # Official Debian package installs to /opt/fluent-bit/bin/
# if [ -f /opt/fluent-bit/bin/fluent-bit ]; then
#     /opt/fluent-bit/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &
# else
#     # Fallback for standard repo install
#     /usr/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &
# fi

# C. Suricata (IDS/IPS)
# echo "Starting Suricata on eth0..."
# # -D runs it as a daemon (background)
# # -i eth0 tells it which interface to listen on
# /usr/bin/suricata -c /etc/suricata/suricata.yaml -i eth0 -D

echo "Starting chrony..."
chronyd -f /etc/chrony/chrony.conf


# --- 3. Keep Container Alive ---
echo "Internal Router is running. Awaiting connections."
exec "$@"
