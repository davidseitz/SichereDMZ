#!/bin/bash

# --- 1. Host-Keys generieren (nur falls nötig) ---
if [ ! -f "/etc/ssh/ssh_host_rsa_key" ]; then
    echo "INFO: SSH host keys not found."
    mkdir -p /etc/ssh
    ssh-keygen -A
fi

# --- 2. AIDE Initialization (HIDS) ---
mkdir -p /var/lib/aide/
chmod 750 /var/lib/aide

# Check if the DB exists.
if [ ! -f "/var/lib/aide/aide.db" ]; then
    echo "INFO: AIDE Database not found. Initializing..."
    
    # Initialize the database (creates aide.db.new)
    /usr/bin/aide --init --config="/etc/aide.conf"
    
    # Simple rename
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    
    echo "INFO: AIDE initialized successfully."
else
    echo "INFO: AIDE Database already exists."
fi

# Run baseline check
echo "Running baseline AIDE check..."
/usr/bin/aide --check --config="/etc/aide.conf" | jq -c . >> /var/log/aide.json || true

# --- 3. Start Background Services ---
echo "INFO: Starting Cron daemon..."
service cron start

sleep 5
echo "INFO: Starte /usr/sbin/sshd"
/usr/sbin/sshd -D -e 2>> /var/log/ssh-custom.log &

echo "INFO: Starting Fluent-bit..."
if [ -f /opt/fluent-bit/bin/fluent-bit ]; then
    /opt/fluent-bit/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &
else
    /usr/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &
fi

# --- 4. Nginx Entrypoint ---
echo "INFO: Übergebe an Nginx-Entrypoint..."
exec /docker-entrypoint.sh nginx -g 'daemon off;'
