#!/bin/sh
set -e

# NOTE: Using the specific IP found in your logs for increased stability, 
# but it should still work with the hostname if defined in the environment.
DB_HOST=${DB_HOST:-10.10.40.2}
DB_PORT=${DB_PORT:-3306}
MAX_RETRIES=30
RETRY_INTERVAL=2
count=0

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
exec gunicorn -b 0.0.0.0:80 app:app --workers 2 --timeout 120