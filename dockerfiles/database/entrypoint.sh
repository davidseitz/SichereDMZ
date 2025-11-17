#!/bin/sh
# This script runs as root
set -e

# --- 1. AIDE (HIDS) Initialization ---
# Check if the AIDE database exists. If not, create it.
# This is the "first-run" task you correctly identified.
echo "AIDE database. Initializing..."
echo "This may take a minute..."
/usr/bin/aide --init
echo "AIDE database initialized. Copyingm..."
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db.gz


# --- 2. MariaDB Initialization ---
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld
if [ -z "$(ls -A /var/lib/mysql)" ]; then
    echo "MariaDB data directory is empty. Initializing database..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql
else
    echo "MariaDB database already exists."
fi

# --- 3. Start Services ---
echo "Starting sshd service on port 3025..."
/usr/sbin/sshd

echo "Starting crond service for daily HIDS checks..."
/usr/sbin/crond

#    This runs it in the background using a config file we will provide.
echo "Starting fluent-bit service..."
/usr/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &

# --- Start MariaDB ---
echo "Starting MariaDB..."
exec /usr/bin/mariadbd \
  --user=mysql \
  --datadir=/var/lib/mysql \
  --skip-name-resolve \
  --bind-address=0.0.0.0 \
  --skip-networking=0 \
  --port=3306

# --- 4. Keep Container Alive ---
echo "Database server is running. Awaiting connections."
exec "$@"
