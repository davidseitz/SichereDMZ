#!/bin/sh
set -e

# NOTE: Using the specific IP found in your logs for increased stability, 
# but it should still work with the hostname if defined in the environment.
DB_HOST=${DB_HOST:-10.10.40.2}
DB_PORT=${DB_PORT:-3306}
MAX_RETRIES=30
RETRY_INTERVAL=2
count=0

sleep 20
#--- SSHD Setup ---
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
echo "INFO: Starte /usr/sbin/sshd"
/usr/sbin/sshd -D -e 2>> /var/log/ssh-custom.log &

#    This runs it in the background using a config file we will provide.
echo "Starting fluent-bit service..."
/usr/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &


#--- Main Web Server Startup ---
echo "--- Starting Gunicorn Only Web Server Setup ---"


# --- 1. Wait for MariaDB ---
echo "Waiting for MariaDB server at $DB_HOST:$DB_PORT..."

# Use the netcat utility to check if the port is open
while ! nc -z $DB_HOST $DB_PORT; do
  if [ $count -ge $MAX_RETRIES ]; then
    echo "🚨 MariaDB server still unavailable after $MAX_RETRIES attempts. Exiting."
    exit 1
  fi
  echo "MariaDB not available. Retrying in $RETRY_INTERVAL seconds..."
  sleep $RETRY_INTERVAL
  count=$((count + 1))
done

echo "✅ MariaDB server is now available."

# --- 2. Initialize Database ---
cd /app
echo "Initializing Database..."
# Execute the Python script to set up the database structure
python -c "from app import init_db; init_db()"

# --- 3. Start Gunicorn on port 80 (Foreground) ---
echo "Starting Gunicorn (Backend) on port 80..."
# 'exec' replaces the current shell process with Gunicorn, ensuring Gunicorn is PID 1
# and listening directly on the external port 80.
exec gunicorn -b 10.10.10.4:80 app:app --workers 2 --timeout 120
