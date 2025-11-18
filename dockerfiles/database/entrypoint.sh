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
    # Note: Initializing the DB creates the 'root'@'localhost' user, 
    # which is used below for initial setup.
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

# --- Start MariaDB (Temporary Background Start) ---
echo "Starting MariaDB in background for setup..."
# Start MariaDB in the background, allowing the script to continue.
/usr/bin/mariadbd \
  --user=mysql \
  --datadir=/var/lib/mysql \
  --skip-name-resolve \
  --bind-address=0.0.0.0 \
  --skip-networking=0 \
  --port=3306 &

# Wait for MariaDB to start up and listen on the socket
for i in {30..0}; do
    if mariadb-admin ping &>/dev/null; then
        break
    fi
    echo "Waiting for MariaDB to start... ($i)"
    sleep 1
done

if [ "$i" = 0 ]; then
    echo "MariaDB failed to start. Exiting."
    exit 1
fi
echo "MariaDB is up and running. Proceeding with database setup."
# --- NEW MariaDB Setup Commands ---
# Create a temporary SQL file
cat << EOF > /tmp/init.sql
# 1. Create the database
CREATE DATABASE IF NOT EXISTS webapp;

# 2. Create the user and set the password. Using '%' to allow connections 
# from any host (required for webserver in another container/host).
CREATE USER IF NOT EXISTS 'webuser'@'%' IDENTIFIED BY 'VerySecureP@ssword123!';

# 3. Grant privileges to the new user on the new database
GRANT ALL PRIVILEGES ON webapp.* TO 'webuser'@'%';

# 4. Apply changes
FLUSH PRIVILEGES;
EOF

# Execute the SQL file using the root user (which has no password by default
# in the initial installation setup for the socket connection).
mariadb < /tmp/init.sql
rm /tmp/init.sql
echo "Database 'webapp' and user 'webuser' created successfully."

# --- Stop MariaDB (for final exec) ---
# Stop the background MariaDB instance cleanly
echo "Stopping MariaDB for final foreground start..."
mariadb-admin shutdown

# Wait for MariaDB to fully stop
for i in {10..0}; do
    if ! mariadb-admin ping &>/dev/null; then
        break
    fi
    sleep 1
done

echo "Starting chrony..."
chronyd -f /etc/chrony/chrony.conf


# --- 4. Final Start MariaDB (Foreground) ---
echo "Starting MariaDB in the foreground..."
exec /usr/bin/mariadbd \
  --user=mysql \
  --datadir=/var/lib/mysql \
  --skip-name-resolve \
  --bind-address=0.0.0.0 \
  --skip-networking=0 \
  --port=3306

# The execution will never reach here if the above exec succeeds.
# If the container keeps running after exec, this line is executed.
echo "Database server is running. Awaiting connections."
exec "$@"
