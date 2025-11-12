#!/bin/bash
# === Automated NFTABLES Functionality Test for Edge Router (FWE) ===

# --- Konfiguration ---
EDGE_ROUTER="clab-security_lab-edge_router"
ATTACKER_CONTAINER="clab-security_lab-attacker_1"
INTERNAL_ROUTER_CONTAINER="clab-security_lab-internal_router"
CLIENT_CONTAINER="clab-security_lab-admin"
INTERNET_SIM_CONTAINER="clab-security_lab-internet"
WAN_IP="192.168.1.1"          # WAN-Gateway/Simulated Internet endpoint
REVPROXY_IP="10.10.10.3"      # Reverse Proxy im DMZ-Netz
EDGE_ROUTER_IP="10.10.50.1"   # Edge-Router Transit-IP
TEST_PORTS=(80 443)           # HTTP/HTTPS
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo "=== Starte automatisierte Tests für Edge-Router-Regeln ==="
TEST_FAILED=0

# Hilfsfunktion: prüft Exit-Code gegen Erwartung und meldet Ergebnis
check_result() {
    local rc=$1
    local expected=$2
    local msg=$3

    if { [[ "$expected" == "true" && $rc -eq 0 ]] || [[ "$expected" == "false" && $rc -ne 0 ]]; }; then
        echo -e "${GREEN}ERFOLG${NC}: $msg"
    else
        echo -e "${RED}FEHLER${NC}: $msg"
        TEST_FAILED=1
    fi
}

# --- Test 1: Attacker -> Reverse Proxy (TCP 80/443) ---
echo -n "Test 1: (Attacker) Zugriff auf Reverse Proxy Port 80/443 ... "
for p in "${TEST_PORTS[@]}"; do
    docker exec $ATTACKER_CONTAINER nc -z -w2 10.10.10.3 $p >/dev/null 2>&1
    check_result $? "true" "Port $p von Attacker zum Reverse Proxy erreichbar"
done

# --- Test 2: Interner Router -> Internet via ping (google.com) ---
# Prüft, ob ICMP-Pakete aus dem internen Netz ins Internet gelangen.
echo -n "Test 2: (Internal Router) Ping $INTERNET_TEST_HOST (Internet) ... "
# -c 1 : ein Ping, -W 2 : Timeout 2 Sekunden (Linux ping)
docker exec $INTERNAL_ROUTER_CONTAINER ping -c 1 -W 2 $INTERNET_TEST_HOST >/dev/null 2>&1
check_result $? "true" "Interner Router kann $INTERNET_TEST_HOST anpingen (Internetzugang)"

# --- Test 3: Edge Router selbst -> Internet (TCP 80/443) ---
echo -n "Test 3: (Edge Router) Eigener Zugriff ins Internet Port 80/443 ... "
for p in "${TEST_PORTS[@]}"; do
    docker exec $EDGE_ROUTER nc -z -w2 8.8.8.8 $p >/dev/null 2>&1
    check_result $? "true" "Edge Router selbst kann Port $p im Internet erreichen"
done

# --- Test 4: Unerlaubter Zugriff (Client direkt -> Internet) ---
echo -n "Test 4: (Client direkt) Zugriff auf Internet sollte BLOCKIERT sein ... "
for p in "${TEST_PORTS[@]}"; do
    docker exec $CLIENT_CONTAINER nc -z -w2 8.8.8.8 $p >/dev/null 2>&1
    check_result $? "false" "Client darf Port $p im Internet NICHT direkt erreichen"
done

echo "=== Tests abgeschlossen ==="
exit $TEST_FAILED
