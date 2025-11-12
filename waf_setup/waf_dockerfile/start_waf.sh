#!/bin/bash

# --- Pfad zur Konfig-Datei ---
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"

# --- 1. Host-Keys generieren (nur falls nötig) ---
if [ ! -f "/etc/ssh/ssh_host_rsa_key" ]; then
    echo "INFO: Host keys not found. Generating new ones..."
    ssh-keygen -A
fi

# --- 2. Konfiguration erzwingen (UNCONDITIONALLY) ---
echo "INFO: Forcing SSH configuration..."
sed -i 's/^#*Port .*/Port 3025/' $SSHD_CONFIG_FILE
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' $SSHD_CONFIG_FILE
sed -i 's/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' $SSHD_CONFIG_FILE
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/' $SSHD_CONFIG_FILE

# --- 3. Starte den SSH-Daemon ---
echo "INFO: Starte /usr/sbin/sshd..."
/usr/sbin/sshd

# --- 4. Rufe das originale Entrypoint-Skript für Nginx auf ---
echo "INFO: Übergebe an Nginx-Entrypoint..."
exec /docker-entrypoint.sh nginx -g 'daemon off;'