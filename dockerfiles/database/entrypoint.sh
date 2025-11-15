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

# Ensure data directory ownership
chown -R mysql:mysql /var/lib/mysql

# --- 4. Start services ---
echo "Starting sshd..."
/usr/sbin/sshd

echo "Starting crond..."
/usr/sbin/crond

echo "Starting MariaDB..."
su-exec mysql /usr/bin/mysqld_safe --datadir=/var/lib/mysql &

# Wait a few seconds to make sure it starts
sleep 5

# Initialize database & user if not exists
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS webapp;
CREATE USER IF NOT EXISTS 'webuser'@'%' IDENTIFIED BY 'VerySecureP@ssword123!';
GRANT ALL PRIVILEGES ON webapp.* TO 'webuser'@'%';
FLUSH PRIVILEGES;
EOF

# --- 5. Keep container alive (important!) ---
echo "Database server is running. Keeping container alive."
tail -f /dev/null
