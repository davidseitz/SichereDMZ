#!/bin/sh

# === FWI Internal NFTABLES SCRIPT (V47) ===
# Verwendung von absoluten Pfaden (/usr/sbin/nft)

NFT="/usr/sbin/nft"

# --- Reset & create table ---
$NFT flush ruleset
$NFT add table inet filter

# --- Chains & policies ---
$NFT add chain inet filter INPUT   { type filter hook input priority 0\; policy drop\; }
$NFT add chain inet filter OUTPUT  { type filter hook output priority 0\; policy drop\; }
$NFT add chain inet filter FORWARD { type filter hook forward priority 0\; policy drop\; }

# --- 1. Allow established/related traffic ---
$NFT add rule inet filter FORWARD ct state established,related accept
$NFT add rule inet filter INPUT   ct state established,related accept

# --- 2. Explicit 'Least Privilege' rules with logging ---

# F4 Webserver (10.10.10.4) -> Database (10.10.40.2) MariaDB via ethdmz -> ethresource
$NFT add rule inet filter FORWARD iifname "ethdmz" oifname "ethresource" \
    ip saddr 10.10.10.4 ip daddr 10.10.40.2 tcp dport 3306 \
    log prefix \"FWI_ALLOW_WEB_DATABASE: \" counter accept

# F6 Admin (10.10.20.2) -> Bastion (10.10.30.3) SSH via ethclient -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethclient" oifname "ethsecurity" \
    ip saddr 10.10.20.2 ip daddr 10.10.30.3 tcp dport 3025 \
    log prefix \"FWI_ALLOW_ADMIN_BASTION: \" counter accept

# F7 Admin (10.10.20.2) ->  Internet HTTP/HTTPS via ethclient -> ethtransit
$NFT add rule inet filter FORWARD iifname "ethclient" oifname "ethtransit" \
    ip saddr 10.10.20.2 meta l4proto { tcp, udp } th dport { 80, 443} \
    log prefix \"FWI_ALLOW_ADMIN_EDGE_ROUTER: \" counter accept

# F2 Attacker 2 (10.10.20.3) -> Internet HTTP/HTTPS via ethclient -> ethtransit
$NFT add rule inet filter FORWARD iifname "ethclient" oifname "ethtransit" \
    ip saddr 10.10.20.2 meta l4proto { tcp, udp } th dport { 80, 443} \
    log prefix \"FWI_ALLOW_ATT2_EDGE_ROUTER: \" counter accept

# F8 Bastion (10.10.30.3) -> Internal Router (10.10.60.1) SSH via ethsecurity -> Internal Router
$NFT add rule inet filter INPUT iifname "ethsecurity" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.1 tcp dport 3025 \
    log prefix "FWI_ALLOW_BASTION_INTERNAL_ROUTER: " counter accept

# F9 Bastion (10.10.30.3) -> Database (10.10.60.4) SSH via ethsecurity -> ethmgmt
$NFT add rule inet filter FORWARD iifname "ethsecurity" oifname "ethmgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.4 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_DATABASE: \" counter accept

# F10 Bastion (10.10.30.3) -> SIEM (10.10.60.5) SSH via ethsecurity -> ethmgmt
$NFT add rule inet filter FORWARD iifname "ethsecurity" oifname "ethmgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.5 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_SIEM: \" counter accept

# F11 Bastion (10.10.30.3) -> Edge Router (10.10.60.6) SSH via ethsecurity -> ethmgmt
$NFT add rule inet filter FORWARD iifname "ethsecurity" oifname "ethmgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.6 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_EDGE_ROUTER: \" counter accept

# F12 Bastion (10.10.30.3) -> Web Server (10.10.60.3) SSH via ethsecurity -> ethmgmt
$NFT add rule inet filter FORWARD iifname "ethsecurity" oifname "ethmgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.3 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_WEB_SERVER: \" counter accept

# F13 Bastion (10.10.30.3) -> WAF/Rev Proxy (10.10.60.2) SSH via ethsecurity -> ethmgmt
$NFT add rule inet filter FORWARD iifname "ethsecurity" oifname "ethmgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.2 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_WAF_PROXY: \" counter accept

# F(TBD) Bastion (10.10.30.3) -> Time/DNS Server (10.10.60.7) SSH via ethsecurity -> ethmgmt
$NFT add rule inet filter FORWARD iifname "ethsecurity" oifname "ethmgmt" \
    ip saddr 10.10.30.3 ip daddr 10.10.60.7 tcp dport 3025 \
    log prefix \"FWI_ALLOW_BASTION_TIME_DNS: \" counter accept

# F14 SIEM (10.10.30.2) -> Internet HTTP/HTTPS via ethsecurity -> ethtransit
$NFT add rule inet filter FORWARD iifname "ethsecurity" oifname "ethtransit" \
    ip saddr 10.10.30.2 meta l4proto { tcp, udp } th dport { 80, 443} \
    log prefix \"FWI_ALLOW_SIEM_EDGE_ROUTER: \" counter accept

# F15 Database (10.10.40.2) -> Internet HTTP/HTTPS via ethresource -> ethtransit
$NFT add rule inet filter FORWARD iifname "ethresource" oifname "ethtransit" \
    ip saddr 10.10.40.2 meta l4proto { tcp, udp } th dport { 80, 443} \
    log prefix \"FWI_ALLOW_DATABASE_EDGE_ROUTER: \" counter accept

# F16 Database (10.10.40.2) -> SIEM (10.10.30.2) HTTP/HTTPS via ethresource -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethresource" oifname "ethsecurity" \
    ip saddr 10.10.40.2 ip daddr 10.10.30.2 meta l4proto { tcp, udp } th dport 3100 \
    log prefix \"FWI_ALLOW_DATABASE_SIEM: \" counter accept

# F18 Edge Router (10.10.50.1) -> SIEM (10.10.30.2) HTTP/HTTPS via ethtransit -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethtransit" oifname "ethsecurity" \
    ip saddr 10.10.50.1 ip daddr 10.10.30.2 meta l4proto { tcp, udp } th dport 3100 \
    log prefix \"FWI_ALLOW_EDGE_ROUTER_SIEM: \" counter accept

# F19 Internal Router (10.10.30.1) -> SIEM (10.10.30.2) HTTP/HTTPS OUTBOUND -> ethsecurity
$NFT add rule inet filter OUTPUT oifname "ethsecurity" \
    ip daddr 10.10.30.2 meta l4proto { tcp, udp } th dport 3100 \
    log prefix "FWI_ALLOW_ROUTER_LOGS_SIEM: " counter accept

# F33 Internal Router (10.10.50.2) -> Internet HTTP/HTTPS OUTBOUND -> ethtransit
$NFT add rule inet filter OUTPUT oifname "ethtransit" \
    ip saddr 10.10.50.2 meta l4proto { tcp, udp } th dport {80,443} \
    log prefix "FWI_ALLOW_INTERNAL_ROUTER_INTERNET: " counter accept

# F21 Web Server (10.10.10.4) -> SIEM (10.10.30.2) HTTP/HTTPS via ethdmz -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethdmz" oifname "ethsecurity" \
    ip saddr 10.10.10.4 ip daddr 10.10.30.2 meta l4proto { tcp, udp } th dport 3100 \
    log prefix \"FWI_ALLOW_WEB_SIEM: \" counter accept

# F20 Waf/Rev Proxy (10.10.10.3) -> SIEM (10.10.30.2) HTTP/HTTPS via ethdmz -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethdmz" oifname "ethsecurity" \
    ip saddr 10.10.10.3 ip daddr 10.10.30.2 meta l4proto { tcp, udp } th dport 3100 \
    log prefix \"FWI_ALLOW_WAF_PROXY_SIEM: \" counter accept

# F22 Admin (10.10.20.2) -> Time/DNS (10.10.30.4) DNS via ethclient -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethclient" oifname "ethsecurity" \
    ip saddr 10.10.20.2 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_ADMIN_DNS: \" counter accept

# F23 Attacker 2 (10.10.20.3) -> Time/DNS (10.10.30.4) DNS via ethclient -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethclient" oifname "ethsecurity" \
    ip saddr 10.10.20.3 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_ATT2_DNS: \" counter accept

# F26 Edge Router (10.10.50.1) -> Time/DNS (10.10.30.4) DNS via ethtransit -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethtransit" oifname "ethsecurity" \
    ip saddr 10.10.50.1 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_EDGE_ROUTER_DNS: \" counter accept

# F25 Internal Router () -> Time/DNS (10.10.30.4) DNS OUTBOUND -> ethsecurity
$NFT add rule inet filter OUTPUT oifname "ethsecurity" \
    ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix "FWI_ALLOW_ROUTER_DNS: " counter accept

# F24 Database (10.10.40.2) -> Time/DNS (10.10.30.4) DNS via ethresource -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethresource" oifname "ethsecurity" \
    ip saddr 10.10.40.2 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_DATABASE_DNS: \" counter accept

# F27 Webserver (10.10.10.4) -> Time/DNS (10.10.30.4) DNS via ethdmz -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethdmz" oifname "ethsecurity" \
    ip saddr 10.10.10.4 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_WEB_DNS: \" counter accept

# F28 Waf/Rev Proxy (10.10.10.3) -> Time/DNS (10.10.30.4) DNS via ethdmz -> ethsecurity
$NFT add rule inet filter FORWARD iifname "ethdmz" oifname "ethsecurity" \
    ip saddr 10.10.10.3 ip daddr 10.10.30.4 udp dport { 53, 123} \
    log prefix \"FWI_ALLOW_WAF_PROXY_DNS: \" counter accept

# F34a Time/DNS (10.10.30.4) -> Internet HTTP/HTTPS via ethsecurity -> ethtransit
$NFT add rule inet filter FORWARD iifname "ethsecurity" oifname "ethtransit" \
    ip saddr 10.10.30.4 l4proto { tcp, udp } th dport { 80, 443} \
    log prefix \"FWI_ALLOW_DNS_INTERNET_UPDATE: \" counter accept

# F34b Time/DNS (10.10.30.4) -> Internet DNS/NTP via ethsecurity -> ethtransit
$NFT add rule inet filter FORWARD iifname "ethsecurity" oifname "ethtransit" \
    ip saddr 10.10.30.4 ip daddr 10.10.50.1 udp th dport { 53, 123} \
    log prefix \"FWI_ALLOW_DNS_INTERNET_DNS_TIME: \" counter accept

# --- 3. Log & Drop remaining forward traffic ---
$NFT add rule inet filter FORWARD log prefix \"FWI_DENIED_FWD: \" counter drop