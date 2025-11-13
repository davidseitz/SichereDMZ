#!/bin/sh
# This script runs as root
set -e

# 1. Generate SSH host keys
ssh-keygen -A

# 2. Start the OpenSSH server daemon
echo "Starting sshd service on port 3025..."
/usr/sbin/sshd

# 3. [NEW] Start the Fluent Bit service
#    This runs it in the background using a config file we will provide.
echo "Starting fluent-bit service..."
/usr/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.conf &

# 4. [FINAL] Start the Loki service (in the foreground)
#    'exec' ensures it becomes the main container process.
echo "Starting Loki service as user 'loki'..."
exec su-exec loki /usr/bin/loki "$@"
