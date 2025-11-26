#!/bin/bash

# --- 1. Host-Keys generieren (nur falls nötig) ---
if [ ! -f "/etc/ssh/ssh_host_rsa_key" ]; then
    echo "INFO: SSH host keys not found (empty /etc/ssh volume?)."
    echo "INFO: Initializing SSHD..."
    mkdir -p /etc/ssh
    ssh-keygen -A
fi

# --- 2. AIDE Initialization (HIDS) ---
# We check if the DB exists. If not, we generate it.
if [ ! -f "/var/lib/aide/aide.db" ]; then
    echo "INFO: AIDE Database not found. Initializing..."
    echo "INFO: This may take a minute..."
    
    # Initialize the database (creates aide.db.new)
    /usr/bin/aide --init
    
    # Move it to the live database name
    cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    
    echo "INFO: AIDE initialized successfully."
else
    echo "INFO: AIDE Database already exists."
fi

# --- 3. Start Background Services ---

# Start Cron (Required for AIDE checks)
echo "INFO: Starting Cron daemon..."
# In Debian, cron runs in background by default, but we ensure it starts
service cron start

# Start SSH
#sleep 2
echo "INFO: Starte /usr/sbin/sshd"
/usr/sbin/sshd -D -e 2>> /var/log/ssh-custom.log &

# --- 4. Rufe das originale Entrypoint-Skript für Nginx auf ---
echo "INFO: Übergebe an Nginx-Entrypoint..."
exec /docker-entrypoint.sh nginx -g 'daemon off;'
