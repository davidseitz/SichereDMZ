#!/usr/bin/env bash
set -euo pipefail

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

# Update system
apt update && apt upgrade -y

# Install dependencies
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

# Add docker GPG Key and Repository
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install docker and plugins
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Ask user if rootful docker daemon should be enabled and started
read -r -p "Enable and start rootful Docker (select 'no' if this will be a rootless installation)? [y/N] " answer1
case "$answer1" in
  [yY])
    # Enable and start docker rootful
    systemctl enable docker
    systemctl start docker
    echo "Rootful Docker enabled and started."
    ;;
  *)
    echo "Rootful Docker not enabled/started."
    ;;
esac

read -r -p "Should the Docker rootless installation be prepared? [y/N] " answer2
case "$answer2" in
  [yY])
    # Install rootless dependencies
    apt-get install -y uidmap dbus-user-session
    echo "Dependencies installed"
    ;;
  *)
    echo "Rootful Docker installation finished"
    exit 0
    ;;
esac


echo "Script finished"
