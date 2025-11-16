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
# Check if the data directory is empty (first run)
if [ -z "$(ls -A /var/lib/mysql)" ]; then
    echo "MariaDB data directory is empty. Initializing database..."
    # 'mysql_install_db' creates the default system tables
    mysql_install_db --user=mysql --datadir=/var/lib/mysql
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

# Start MariaDB. 'su-exec' drops privileges to the 'mysql' user.
echo "Starting MariaDB service..."
su-exec mysql /usr/bin/mysqld_safe --datadir=/var/lib/mysql &

# --- 4. Keep Container Alive ---
echo "Database server is running. Awaiting connections."
exec "$@"
