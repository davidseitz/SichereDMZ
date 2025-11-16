#!/bin/sh
# This script runs as root
set -e

# --- 0. Environment Setup (CRITICAL FOR ALPINE) ---
# MariaDB needs specific directories to exist for the lock/PID files
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

# --- 1. AIDE (HIDS) Initialization ---
echo "AIDE database. Initializing..."
if [ ! -f "/var/lib/aide/aide.db.gz" ]; then
    echo "Creating initial AIDE database. This may take a minute..."
    /usr/bin/aide --init
    echo "AIDE database initialized. Copying to final location..."
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db.gz
else
    echo "AIDE database already exists. Skipping initialization."
fi


# --- 2. MariaDB Initialization (FIXED PRIVILEGE) ---
if [ -z "$(ls -A /var/lib/mysql)" ]; then
    echo "MariaDB data directory is empty. Initializing database..."
    # FIX: Run mariadb-install-db as root (current user) so chown permissions work.
    # The --user=mysql flag ensures the resulting files are owned by 'mysql'.
    mariadb-install-db --datadir=/var/lib/mysql --user=mysql
    
    # Crucially, ensure the main data directory ownership is correct afterward:
    chown -R mysql:mysql /var/lib/mysql
else
    echo "MariaDB database already exists. Skipping initialization."
fi

# --- 3. Start BACKGROUND Services ---
# These services are designed to daemonize (run in the background)
echo "Starting sshd service on port 3025..."
/usr/sbin/sshd

echo "Starting crond service for daily HIDS checks..."
/usr/sbin/crond

# --- 4. Database User and Schema Setup (Conditional) ---
# Your database creation logic goes here once the server is available.
# Example:
#mysql -h 127.0.0.1 -u root -e "
#CREATE DATABASE IF NOT EXISTS webapp;
#CREATE USER IF NOT EXISTS 'webuser'@'%' IDENTIFIED BY 'VerySecureP@ssword123!';
#GRANT ALL PRIVILEGES ON webapp.* TO 'webuser'@'%';
#FLUSH PRIVILEGES;
#"

# --- Networking Fix: Ensure MariaDB listens on all interfaces (0.0.0.0) ---
echo "Applying networking fix to ensure 0.0.0.0 binding..."
# Aggressively comment out any existing 'bind-address' setting in the default config file
# This prevents the config file from overriding the command line argument.
if [ -f "/etc/my.cnf" ]; then
    sed -i 's/^bind-address/#bind-address/g' /etc/my.cnf
fi
# Also check common conf.d directory files
for f in /etc/my.cnf.d/*.cnf; do
    if [ -f "$f" ]; then
        sed -i 's/^bind-address/#bind-address/g' "$f"
    fi
done

# --- 4. Start MariaDB in the FOREGROUND (CRITICAL FIX) ---
echo "Starting MariaDB in the FOREGROUND (PID 1)..."

# FIX: Switch back to mariadbd-safe. Now that initialization permissions are fixed,
# this wrapper should handle the daemon startup and environment correctly.
exec su-exec mysql /usr/bin/mariadbd-safe --datadir='/var/lib/mysql' --bind-address=0.0.0.0 --skip-log-bin