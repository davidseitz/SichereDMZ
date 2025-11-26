#!/bin/bash

# AUTOMATICALLY DETECT INTERFACE
PHY_IFACE=$(ip route get 8.8.8.8 | sed -n 's/.*dev \([^\ ]*\).*/\1/p')
BRIDGE="network_bridge"
SUBNET="172.20.1.0/24"

# Safety check
if [ -z "$PHY_IFACE" ]; then
    echo ">>> Error: Could not detect internet-facing interface. Cannot verify iptables rules."
    exit 1
fi

echo ">>> Cleaning up NAT Bridge..."
echo ">>> Detected Internet Interface for cleanup: $PHY_IFACE"

# 1. Remove IPTables Rules
# (The -D flag deletes the rule we added with -A previously)
# We suppress errors (2>/dev/null) just in case the rule is already gone or the interface changed.
sudo iptables -t nat -D POSTROUTING -s $SUBNET -o $PHY_IFACE -j MASQUERADE 2>/dev/null || echo ">>> Note: NAT rule not found or already deleted."

sudo iptables -D FORWARD -i $BRIDGE -j ACCEPT 2>/dev/null
sudo iptables -D FORWARD -o $BRIDGE -j ACCEPT 2>/dev/null

# 2. Delete the bridge
# Check if bridge exists before trying to delete
if ip link show $BRIDGE > /dev/null 2>&1; then
    sudo ip link set $BRIDGE down
    sudo ip link del $BRIDGE
    echo ">>> Bridge deleted."
else
    echo ">>> Bridge $BRIDGE does not exist."
fi

# 3. Remove route for host browser access to lab nodes [Optional]
sudo ip route del 10.10.0.0/16 via 172.20.1.9 dev network_bridge 2>/dev/null || echo ">>> Note: Route not found or already deleted."

echo ">>> Done."