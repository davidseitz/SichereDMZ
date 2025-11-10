#!/bin/sh

# === FW1 (Edge) NFTABLES SCRIPT (V47) ===
# Verwendung von absoluten Pfaden (/usr/sbin/nft)

NFT="/usr/sbin/nft"

# --- Reset & create table ---
$NFT flush ruleset
$NFT add table inet filter

# --- Chains & policies ---
$NFT add chain inet filter INPUT   { type filter hook input priority 0\; policy drop\; }
$NFT add chain inet filter OUTPUT  { type filter hook output priority 0\; policy accept\; }
$NFT add chain inet filter FORWARD { type filter hook forward priority 0\; policy accept\; }

# --- 1. Allow established/related traffic ---
$NFT add rule inet filter FORWARD ct state established,related accept
$NFT add rule inet filter INPUT   ct state established,related accept

# --- 2. Explicit 'Least Privilege' rules with logging ---

# (1) Client (10.10.2.10) -> Webserver (10.10.1.10) HTTP/HTTPS via eth2 -> eth1
$NFT add rule inet filter FORWARD iifname "eth2" oifname "eth1" \
    ip saddr 10.10.2.10 ip daddr 10.10.1.10 tcp dport { 80, 443 } \
    log prefix \"FW1_ALLOW_WEB_CLIENT: \" accept

# (2) IDS (10.10.1.20) -> SIEM (10.10.3.10) Port 1514 via eth1 -> eth3
$NFT add rule inet filter FORWARD iifname "eth1" oifname "eth3" \
    ip saddr 10.10.1.20 ip daddr 10.10.3.10 tcp dport 1514 \
    log prefix \"FW1_ALLOW_IDS_SIEM: \" accept

# (3) Webserver (10.10.1.100) -> SIEM (10.10.3.10) Port 1514 via eth1 -> eth3
$NFT add rule inet filter FORWARD iifname "eth1" oifname "eth3" \
    ip saddr 10.10.1.100 ip daddr 10.10.3.10 tcp dport 1514 \
    log prefix \"FW1_ALLOW_WEBLOG_SIEM: \" accept

# (4) WAF (10.10.1.10) -> SIEM (10.10.3.10) Port 1514 via eth1 -> eth3
$NFT add rule inet filter FORWARD iifname "eth1" oifname "eth3" \
    ip saddr 10.10.1.10 ip daddr 10.10.3.10 tcp dport 1514 \
    log prefix \"FW1_ALLOW_WAF_SIEM: \" accept

# --- 3. Log & Drop remaining forward traffic ---
$NFT add rule inet filter FORWARD log prefix \"FW1_DENIED_FWD: \" drop
