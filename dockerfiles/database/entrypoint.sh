#!/bin/sh
set -e

# --- 1. AIDE (HIDS) Initialization ---
# OPTIMIZATION: Only run init if the DB doesn't exist.
if [ ! -f /var/lib/aide/aide.db.gz ] || [ ! -s /var/lib/aide/aide.db.gz ]; then
    echo "AIDE database not found. Initializing (this will take time)..."
    /usr/bin/aide --init > /dev/null
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db.gz
    echo "AIDE initialized."
else
    echo "AIDE database exists. Skipping init."
fi

# --- 2. Start Auxiliary Services ---
# We start these in the background. They will die when the main process (MariaDB) dies.
echo "Starting Sidecars: SSHD, Chrony, Fluent-bit, Crond..."

/usr/sbin/sshd -D -e 2>> /var/log/ssh-custom.log &
chronyd -f /etc/chrony/chrony.conf &
/usr/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &
/usr/sbin/crond -b -l 8

# --- 3. MariaDB Initialization & Bootstrap ---

# Ensure permissions are correct
chown -R mysql:mysql /var/lib/mysql /run/mysqld

if [ -z "$(ls -A /var/lib/mysql)" ]; then
    echo "MariaDB data directory is empty. Installing system tables..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db > /dev/null

    echo "Starting temporary MariaDB for user creation..."
    # Start MariaDB in "maintenance mode" (no networking) for setup
    /usr/bin/mariadbd --user=mysql --datadir=/var/lib/mysql --skip-networking --socket=/run/mysqld/mysqld.sock &
    TEMP_PID=$!

    # Wait for the socket to be ready
    for i in {30..0}; do
        if echo 'SELECT 1' | mariadb --socket=/run/mysqld/mysqld.sock --connect-timeout=1 > /dev/null 2>&1; then
            break
        fi
        echo "Waiting for temp DB init... $i"
        sleep 1
    done

    if [ "$i" = 0 ]; then
        echo "Temp DB failed to start."
        exit 1
    fi

    echo "Applying security settings and creating users..."
    
    # Use strict SQL for the init
    cat << EOF | mariadb --socket=/run/mysqld/mysqld.sock
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS webapp;
CREATE USER IF NOT EXISTS 'webuser'@'%' IDENTIFIED BY 'VerySecureP@ssword123!';
GRANT ALL PRIVILEGES ON webapp.* TO 'webuser'@'%';
-- Optional: Lockdown root (remove remote access if present)
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
ALTER USER 'root'@'localhost' IDENTIFIED BY 'MaiVeariSegureBasword0912!';
FLUSH PRIVILEGES;
EOF
    
    echo "Initialization complete. Stopping temp DB..."
    kill -TERM "$TEMP_PID"
    wait "$TEMP_PID"
    echo "Temp DB stopped."
else
    echo "MariaDB data directory already populated. Skipping setup."
fi

# --- 4. Final Baseline Check ---
# Only run if needed, don't let it block startup too long
echo "Running baseline AIDE check (backgrounded)..."
(/usr/bin/aide --check | jq -c . >> /var/log/aide.json) &

# --- 5. Main Execution ---
echo "Starting MariaDB in Foreground..."

# "exec" replaces the current shell process with the command passed in CMD.
# This makes MariaDB PID 1.
exec "$@"
