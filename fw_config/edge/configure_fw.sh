#!/bin/sh
set -e 

# === FW1 (Edge) NFTABLES SCRIPT (V37) ===
# KORREKTUR: Syntaxfehler in 'add chain' behoben

nft flush ruleset

nft add table inet filter

# KORRIGIERTE SYNTAX: Policy wird direkt beim Erstellen gesetzt
nft add chain inet filter INPUT   { type filter hook input priority 0\; policy drop\; }
nft add chain inet filter OUTPUT  { type filter hook output priority 0\; policy accept\; }
nft add chain inet filter FORWARD { type filter hook forward priority 0\; policy accept\; }

# 1. Erlaube etablierte Verbindungen
nft add rule inet filter FORWARD ct state established,related accept
nft add rule inet filter INPUT   ct state established,related accept

# 2. Erlaube 'Least Privilege'-Verkehr
nft add rule inet filter FORWARD iifname "eth1" oifname "eth2" \
    ip daddr 10.10.1.10 tcp dport {80, 443} accept

# 3. Explizite 'Drop & Log'-Regel am Ende
nft add rule inet filter FORWARD log prefix \"FW1_DENIED_FWD: \" drop