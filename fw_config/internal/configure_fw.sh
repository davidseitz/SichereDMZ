#!/bin/sh
set -e

# === FW2 (Internal) IPTABLES SCRIPT (V36) ===

# ENTFERNT: modprobe ip_tables
# ENTFERNT: modprobe nf_conntrack

# 1. Setze Default Policies (NUR INPUT/OUTPUT)
iptables -P INPUT   DROP
iptables -P OUTPUT  ACCEPT
iptables -P FORWARD ACCEPT 
iptables -F FORWARD 

# 2. Erlaube etablierte Verbindungen
iptables -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 3. Definiere 'Least Privilege'-Verkehr
iptables -A FORWARD -i eth1 -o eth3 -d 10.10.3.10 -p tcp --dport 1514 -j ACCEPT
iptables -A FORWARD -i eth1 -o eth3 -d 10.10.3.10 -p tcp --dport 514 -j ACCEPT
iptables -A FORWARD -i eth2 -o eth3 -d 10.10.3.10 -p tcp --dport 1514 -j ACCEPT
iptables -A FORWARD -i eth2 -o eth1 -d 10.10.1.10 -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -i eth2 -o eth1 -d 10.10.1.10 -p tcp --dport 443 -j ACCEPT

# 4. KORREKTUR: Explizite 'Log & Drop'-Regel am Ende
iptables -A FORWARD -j LOG --log-prefix "FW2_DENIED_FWD: "
iptables -A FORWARD -j DROP