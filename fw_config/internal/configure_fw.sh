#!/bin/sh

# === FW1 (Edge) NFTABLES SCRIPT (V45) ===
# Verwendung von absoluten Pfaden (/usr/sbin/nft)

NFT="/usr/sbin/nft"

$NFT flush ruleset
$NFT add table inet filter

# Policies
$NFT add chain inet filter INPUT   { type filter hook input priority 0\; policy drop\; }
$NFT add chain inet filter OUTPUT  { type filter hook output priority 0\; policy accept\; }
$NFT add chain inet filter FORWARD { type filter hook forward priority 0\; policy accept\; }

# 1. Erlaube etablierte Verbindungen
$NFT add rule inet filter FORWARD ct state established,related accept
$NFT add rule inet filter INPUT   ct state established,related accept

# 2. 'Least Privilege' ACCEPT-Regeln
$NFT add rule inet filter FORWARD iifname "eth1" oifname "eth2" \
    ip daddr 10.10.1.10 tcp dport { 80, 443 } accept

# 3. Explizites 'Log & Drop' am Ende
$NFT add rule inet filter FORWARD log prefix \"FW1_DENIED_FWD: \" drop