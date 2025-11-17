#!/bin/sh

# === FWH Hosts NFTABLES SCRIPT (V3 – Blacklist Mode) ===
# This configuration allows all traffic by default,
# but blocks any *outgoing* traffic over the management interface.
# Verwendung von absoluten Pfaden (/usr/sbin/nft)

NFT="nft"

# --- Reset & create table ---
$NFT flush ruleset
$NFT add table inet filter

# --- Chains & policies ---
# Blacklist style → default policy: ACCEPT
$NFT add chain inet filter INPUT   { type filter hook input priority 0\; policy accept\; }
$NFT add chain inet filter OUTPUT  { type filter hook output priority 0\; policy accept\; }
$NFT add chain inet filter FORWARD { type filter hook forward priority 0\; policy accept\; }

# --- 1. Allow established/related traffic (redundant but good hygiene) ---
$NFT add rule inet filter INPUT   ct state established,related accept
$NFT add rule inet filter OUTPUT  ct state established,related accept
$NFT add rule inet filter FORWARD ct state established,related accept

# --- 2. Allow local traffic (loopback) ---
$NFT add rule inet filter INPUT iif lo accept
$NFT add rule inet filter OUTPUT oif lo accept

# --- 3. Prevent sending data over the management network ---
# Hosts may *receive* management traffic but not *send* it.
# Replace 'ethmgmt' with your actual management interface name if different.
$NFT add rule inet filter INPUT  iifname "ethmgmt" accept
$NFT add rule inet filter OUTPUT oifname "ethmgmt" log prefix \"FWH_MGMT_DENIED: \" drop

# --- 4. Optional logging for visibility (non-disruptive) ---
# These rules only log packets dropped by the mgmt restriction above.
# No additional drops are needed since policy = accept.
