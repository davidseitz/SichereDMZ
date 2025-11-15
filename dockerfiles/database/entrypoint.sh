#!/bin/sh
set -e

# --- 1. AIDE Initialization ---
#echo "AIDE database. Initializing..."
#/usr/bin/aide --init
#mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db.gz

# --- 2. MariaDB Initialization ---
if [ -z "$(ls -A /var/lib/mysql)" ]; then
    echo "MariaDB data directory is empty. Initializing database..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql
else
    echo "MariaDB database already exists."
fi

# --- 3. SSH host key generation ---
if [ ! -f "/etc/ssh/ssh_host_rsa_key" ]; then
    echo "INFO: Initializing SSH host keys..."
    mkdir -p /etc/ssh
    ssh-keygen -A
fi

# --- 4. Start services ---
echo "Starting sshd..."
/usr/sbin/sshd

echo "Starting crond..."
/usr/sbin/crond

echo "Starting MariaDB..."
su-exec mysql /usr/bin/mysqld_safe --datadir=/var/lib/mysql &

# --- 5. Keep container alive (important!) ---
echo "Database server is running. Keeping container alive."
tail -f /dev/null
