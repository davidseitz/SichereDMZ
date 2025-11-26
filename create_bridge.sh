#!/bin/bash

# --- CONFIGURATION ---
# AUTOMATICALLY DETECT INTERFACE
# This asks the kernel: "Which interface would you use to reach 8.8.8.8?"
PHY_IFACE=$(ip route get 8.8.8.8 | sed -n 's/.*dev \([^\ ]*\).*/\1/p')

BRIDGE="network_bridge"          # Name of the new lab bridge
GATEWAY_IP="172.20.1.1/24"       # The IP address for the Bridge (Gateway for lab nodes)

# Safety check to ensure we found an interface
if [ -z "$PHY_IFACE" ]; then
    echo ">>> Error: Could not detect internet-facing interface. Exiting."
    exit 1
fi

echo ">>> Setting up NAT Bridge: $BRIDGE"
echo ">>> Detected Internet Interface: $PHY_IFACE"

# 0. CHECK & INSTALL PREREQUISITES
if ! command -v iptables &> /dev/null; then
    echo ">>> iptables not found. Installing..."
    # Update package list and install iptables without prompts
    sudo apt-get update -qq && sudo apt-get install -y iptables
fi

# 1. Create the standalone bridge (No physical interface attached)
sudo ip link add name $BRIDGE type bridge
sudo ip link set $BRIDGE up

# 2. Assign the Gateway IP to the bridge
sudo ip addr add $GATEWAY_IP dev $BRIDGE

# 3. Enable IP Forwarding (Allows host to act as router)
echo ">>> Enabling IP Forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null

# 4. Configure NAT (Masquerade)
echo ">>> Applying NAT rules..."
# Use -I (Insert) for POSTROUTING ensures it sits at the top, though -A usually works for NAT tables.
# We will stick to -A here as NAT usually isn't the blocker, Filter is.
sudo iptables -t nat -A POSTROUTING -s ${GATEWAY_IP%\.*}.0/24 -o $PHY_IFACE -j MASQUERADE

# 5. Allow traffic forwarding
# We use -I FORWARD 1 to insert this rule at the very TOP of the chain.
echo ">>> Allowing Forwarding (Inserting at top of chain)..."
sudo iptables -I FORWARD 1 -i $BRIDGE -j ACCEPT
sudo iptables -I FORWARD 1 -o $BRIDGE -j ACCEPT

echo ">>> Done. Bridge $BRIDGE is up at $GATEWAY_IP"

# 6. Add route for host browser access to lab nodes [Optional]
echo ">>> Adding route to access lab nodes from host..."
sudo ip route add 10.10.0.0/16 via 172.20.1.9 dev network_bridge

echo ">>> Your lab nodes should use ${GATEWAY_IP%/*} as their default gateway."