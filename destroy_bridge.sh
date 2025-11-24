#!/bin/bash

PHY_IFACE="eth0"
BRIDGE="network_bridge"
SUBNET="172.20.1.0/24"

echo ">>> Cleaning up NAT Bridge..."

# 1. Remove IPTables Rules
# (The -D flag deletes the rule we added with -A previously)
sudo iptables -t nat -D POSTROUTING -s $SUBNET -o $PHY_IFACE -j MASQUERADE
sudo iptables -D FORWARD -i $BRIDGE -j ACCEPT
sudo iptables -D FORWARD -o $BRIDGE -j ACCEPT

# 2. Delete the bridge
sudo ip link set $BRIDGE down
sudo ip link del $BRIDGE

echo ">>> Done."