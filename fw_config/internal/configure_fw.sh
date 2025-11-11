#!/bin/sh

# === FWI Internal NFTABLES SCRIPT (V47) ===
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

# F4 Webserver (10.10.10.4) -> Database (10.10.40.2) MariaDB via eth-dmz -> eth-resource
$NFT add rule inet filter FORWARD iifname "eth-dmz" oifname "eth-resource" \
    ip saddr 10.10.10.4 ip daddr 10.10.40.2 tcp dport 3306 \
    log prefix \"FWI_ALLOW_WEB_DATABASE: \" accept

# F6 Admin (10.10.20.2) -> Bastion (10.10.30.3) SSH via eth-client -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-security" \
    ip saddr 10.10.20.2 ip daddr 10.10.30.3 tcp dport 3025 \
    log prefix \"FWI_ALLOW_ADMIN_BASTION: \" accept

# F7 Admin (10.10.20.2) -> (Eage Router) Internet (10.10.50.1) HTTP/HTTPS via eth-client -> eth-transit
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-transit" \
    ip saddr 10.10.20.2 ip daddr 10.10.50.1 meta l4proto { tcp, udp } th dport { 80, 443} \
    log prefix \"FWI_ALLOW_ADMIN_EAGE_ROUTER: \" accept

# F2 Attacker 2 (10.10.20.3) -> (Eage Router) Internet (10.10.50.1) HTTP/HTTPS via eth-client -> eth-transit
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-transit" \
    ip saddr 10.10.20.2 ip daddr 10.10.50.1 meta l4proto { tcp, udp } th dport { 80, 443} \
    log prefix \"FWI_ALLOW_ATT2_EAGE_ROUTER: \" accept

# F8 Bastion (10.10.30.3) -> Internal Router (10.10.60.1) SSH via eth-client -> Internal Router
$NFT add rule inet filter INPUT iifname "eth-client" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.1 tcp dport 3025 \
    log prefix "FWI_ALLOW_BASTION_INTERNAL_ROUTER: " accept

# F9 Bastion (10.10.30.3) -> Database (10.10.60.4) SSH via eth-client -> eth-mgmt
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-mgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.4 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_DATABASE: \" accept

# F10 Bastion (10.10.30.3) -> SIEM (10.10.60.5) SSH via eth-client -> eth-mgmt
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-mgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.5 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_SIEM: \" accept

# F11 Bastion (10.10.30.3) -> Eage Router (10.10.60.6) SSH via eth-client -> eth-mgmt
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-mgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.6 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_EAGE_ROUTER: \" accept

# F12 Bastion (10.10.30.3) -> Web Server (10.10.60.3) SSH via eth-client -> eth-mgmt
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-mgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.3 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_WEB_SERVER: \" accept

# F13 Bastion (10.10.30.3) -> WAF/Rev Proxy (10.10.60.2) SSH via eth-client -> eth-mgmt
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-mgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.2 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_WAF_PROXY: \" accept

# F(TBD) Bastion (10.10.30.3) -> Time/DNS Server (10.10.60.7) SSH via eth-client -> eth-mgmt
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-mgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.7 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_TIME_DNS: \" accept

# F14 SIEM (10.10.30.2) -> (Eage Router) Internet (10.10.50.1) HTTP/HTTPS via eth-security -> eth-transit
$NFT add rule inet filter FORWARD iifname "eth-security" oifname "eth-transit" \
    ip saddr 10.10.30.2 ip daddr 10.10.50.1 meta l4proto { tcp, udp } th dport { 80, 443} \
    log prefix \"FWI_ALLOW_SIEM_EAGE_ROUTER: \" accept

# F15 Database (10.10.40.2) -> (Eage Router) Internet (10.10.50.1) HTTP/HTTPS via eth-resource -> eth-transit
$NFT add rule inet filter FORWARD iifname "eth-resource" oifname "eth-transit" \
    ip saddr 10.10.40.2 ip daddr 10.10.50.1 meta l4proto { tcp, udp } th dport { 80, 443} \
    log prefix \"FWI_ALLOW_DATABASE_EAGE_ROUTER: \" accept

# F16 Database (10.10.40.2) -> SIEM (10.10.30.2) HTTP/HTTPS via eth-resource -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-resource" oifname "eth-security" \
    ip saddr 10.10.40.2 ip daddr 10.10.30.2 meta l4proto { tcp, udp } th dport 3100 \
    log prefix \"FWI_ALLOW_DATABASE_SIEM: \" accept

# F18 Eage Router (10.10.50.1) -> SIEM (10.10.30.2) HTTP/HTTPS via eth-transit -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-transit" oifname "eth-security" \
    ip saddr 10.10.50.1 ip daddr 10.10.30.2 meta l4proto { tcp, udp } th dport 3100 \
    log prefix \"FWI_ALLOW_EAGE_ROUTER_SIEM: \" accept

# F19 Internal Router (10.10.30.1) -> SIEM (10.10.30.2) HTTP/HTTPS OUTBOUND -> eth-security
$NFT add rule inet filter OUTPUT oifname "eth-security" \
    ip daddr 10.10.30.2 meta l4proto { tcp, udp } th dport 3100 \
    log prefix "FWI_ALLOW_ROUTER_LOGS_SIEM: " accept

# F(TBD) Internal Router (10.10.50.2) -> Eage Router (Internet) (10.10.50.1) HTTP/HTTPS OUTBOUND -> eth-transit
$NFT add rule inet filter OUTPUT oifname "eth-transit" \
    ip daddr 10.10.50.1 meta l4proto { tcp, udp } th dport {80,443} \
    log prefix "FWI_ALLOW_INTERNAL_ROUTER_INTERNET: " accept

# F21 Web Server (10.10.10.4) -> SIEM (10.10.30.2) HTTP/HTTPS via eth-dmz -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-dmz" oifname "eth-security" \
    ip saddr 10.10.10.4 ip daddr 10.10.30.2 meta l4proto { tcp, udp } th dport 3100 \
    log prefix \"FWI_ALLOW_WEB_SIEM: \" accept

# F20 Waf/Rev Proxy (10.10.10.3) -> SIEM (10.10.30.2) HTTP/HTTPS via eth-dmz -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-dmz" oifname "eth-security" \
    ip saddr 10.10.10.3 ip daddr 10.10.30.2 meta l4proto { tcp, udp } th dport 3100 \
    log prefix \"FWI_ALLOW_WAF_PROXY_SIEM: \" accept

# F22 Admin (10.10.20.2) -> Time/DNS (10.10.30.4) DNS via eth-client -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-security" \
    ip saddr 10.10.20.2 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_ADMIN_DNS: \" accept

# F23 Attacker 2 (10.10.20.3) -> Time/DNS (10.10.30.4) DNS via eth-client -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-client" oifname "eth-security" \
    ip saddr 10.10.20.3 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_ATT2_DNS: \" accept

# F26 Eage Router (10.10.50.1) -> Time/DNS (10.10.30.4) DNS via eth-transit -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-transit" oifname "eth-security" \
    ip saddr 10.10.50.1 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_EAGE_ROUTER_DNS: \" accept

# F25 Internal Router () -> Time/DNS (10.10.30.4) DNS OUTBOUND -> eth-security
$NFT add rule inet filter OUTPUT oifname "eth-security" \
    ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix "FWI_ALLOW_ROUTER_DNS: " accept

# F24 Database (10.10.40.2) -> Time/DNS (10.10.30.4) DNS via eth-resource -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-resource" oifname "eth-security" \
    ip saddr 10.10.40.2 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_DATABASE_DNS: \" accept

# F27 Webserver (10.10.10.4) -> Time/DNS (10.10.30.4) DNS via eth-dmz -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-dmz" oifname "eth-security" \
    ip saddr 10.10.10.4 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_WEB_DNS: \" accept

# F28 Waf/Rev Proxy (10.10.10.3) -> Time/DNS (10.10.30.4) DNS via eth-dmz -> eth-security
$NFT add rule inet filter FORWARD iifname "eth-dmz" oifname "eth-security" \
    ip saddr 10.10.10.3 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_WAF_PROXY_DNS: \" accept


# --- 3. Log & Drop remaining forward traffic ---
$NFT add rule inet filter FORWARD log prefix \"FWI_DENIED_FWD: \" drop
