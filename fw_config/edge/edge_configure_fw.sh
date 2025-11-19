#!/bin/sh

# === FWE (Edge) NFTABLES SCRIPT (V45) ===
# Verwendung von absoluten Pfaden (/usr/sbin/nft)

NFT="/usr/sbin/nft"

$NFT flush ruleset
$NFT add table inet filter

# Policies
$NFT add chain inet filter INPUT   { type filter hook input priority 0\; policy accept\; }
$NFT add chain inet filter OUTPUT  { type filter hook output priority 0\; policy accept\; }
$NFT add chain inet filter FORWARD { type filter hook forward priority 0\; policy accept\; }

# 1. Erlaube etablierte Verbindungen
$NFT add rule inet filter FORWARD ct state established,related accept
$NFT add rule inet filter INPUT   ct state established,related accept

# F1 Attacker 1 (192.168.1.2) -> Rev Proxy (10.10.10.3) HTTP/HTTPS via ethwan -> ethdmz
$NFT add rule inet filter FORWARD iifname "ethwan" oifname "ethdmz" \
    ip saddr 192.168.1.2 ip daddr 10.10.10.3 meta l4proto { tcp, udp } th dport { 80, 443} \
    log prefix \"FWE_ALLOW_ATT1_WAF_PROXY: \" accept

# F(2,5,7,14,15) Internal Router (ALL Subnets) (10.10.0.0/16) -> Internet HTTP/HTTPS via ethwan -> ethdmz
$NFT add rule inet filter FORWARD iifname "ethtransit" oifname "ethwan" \
    ip saddr 10.10.0.0/16 meta l4proto { tcp, udp } th dport { 80, 443 } \
    log prefix "FWE_ALLOW_INTERNEL_TO_INTERNET: " accept

# F34 DNS Time Server -> Internet HTTP/HTTPS via ethwan -> ethdmz
$NFT add rule inet filter FORWARD iifname "ethtransit" oifname "ethwan" \
    ip saddr 10.10.30.4 udp dport { 53, 123 } \
    log prefix "FWE_ALLOW_INTERNEL_DNS: " accept

# F(TBD) Edge Router (10.10.50.1) -> Internet HTTP/HTTPS OUTBOUND -> ethwan
$NFT add rule inet filter OUTPUT oifname "ethwan" \
    meta l4proto { tcp, udp } th dport {80,443} \
    log prefix "FWI_ALLOW_EAGE_ROUTER_INTERNET: " accept

# 3. Explizites 'Log & Drop' am Ende
$NFT add rule inet filter FORWARD log prefix \"FWE_DENIED_FWD: \" drop