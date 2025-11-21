#!/bin/bash

# --- 1. Host-Keys generieren (nur falls nötig) ---
#    Wir prüfen nur noch auf die Keys. Die Konfig ist jetzt im Image.
if [ ! -f "/etc/ssh/ssh_host_rsa_key" ]; then
    
    echo "INFO: SSH host keys not found (empty /etc/ssh volume?)."
    echo "INFO: Initializing SSHD..."
    
    # 1a. Stelle sicher, dass das Verzeichnis existiert
    mkdir -p /etc/ssh
    
    # 1b. Generiere die Host-Keys
    ssh-keygen -A
fi

# --- 2. Starte den SSH-Daemon ---
sleep 10
echo "INFO: Starte /usr/sbin/sshd (config is baked into image)..."
/usr/sbin/sshd

# --- 3. Rufe das originale Entrypoint-Skript für Nginx auf ---
echo "INFO: Übergebe an Nginx-Entrypoint..."
exec /docker-entrypoint.sh nginx -g 'daemon off;'
