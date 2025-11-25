#!/bin/bash
# === Automated NFTABLES Functionality Test for Edge Router (FWE) ===

# --- Konfiguration ---
EDGE_ROUTER="clab-security_lab-edge_router"
ATTACKER_CONTAINER="clab-security_lab-attacker_1" # IP: 192.168.1.2
INTERNAL_ROUTER_CONTAINER="clab-security_lab-internal_router"
CLIENT_CONTAINER="clab-security_lab-admin" # IP: 10.10.20.2 (Test for blocked internal traffic)
DNS_TIME_CONTAINER="clab-security_lab-time_dns" # IP: 10.10.30.4

# IP Addresses & Hostnames
PUBLIC_HOST="www.dhbw.de"     # Target hostname for Internet tests
EDGE_ROUTER_MGMT_IP="10.10.60.6"
REVPROXY_IP="10.10.10.3"
SIEM_IP="10.10.30.2"
BASTION_IP="10.10.30.3"

# Ports
SSH_PORT="3025"
DNS_PORT="53"
NTP_PORT="123"
SIEM_LOG_PORT="3100"
HTTP_PORT="80"
HTTPS_PORT="443"

# --- Colors ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo "=== Starte automatisierte Tests für Edge-Router-Regeln (FWE) ==="
TEST_FAILED=0

# Hilfsfunktion: prüft Exit-Code gegen Erwartung und meldet Ergebnis
check_result() {
    local rc=$1
    local expected=$2 # "pass" or "fail"
    local msg=$3

    if { [[ "$expected" == "pass" && $rc -eq 0 ]] || [[ "$expected" == "fail" && $rc -ne 0 ]]; }; then
        echo -e "${GREEN}ERFOLG${NC}: $msg"
    else
        echo -e "${RED}FEHLER${NC}: $msg (Expected: $expected, Actual: $rc)"
        TEST_FAILED=1
    fi
}

# Helper function for netcat tests
# DEST_IP now accepts an IP or a HOSTNAME
test_nc() {
    local SOURCE_CONT=$1
    local DEST_IP_OR_HOST=$2
    local PORT=$3
    local PROTO=$4 # tcp or udp
    local EXPECT_PASS=$5 # "pass" or "fail"
    local TEST_NAME="$6"

    # Note: Using a hostname here automatically tests DNS resolution as well.
    local COMMAND="docker exec $SOURCE_CONT nc -z -w 2 "
    if [ "$PROTO" == "udp" ]; then
        COMMAND="$COMMAND -u "
    fi
    COMMAND="$COMMAND $DEST_IP_OR_HOST $PORT"

    # Execute the command silently
    $COMMAND >/dev/null 2>&1
    local RESULT=$?

    check_result $RESULT "$EXPECT_PASS" "$TEST_NAME"
}

# --- 1. OUTPUT Chain Tests (Traffic from FWE itself) ---
echo "--- 1. OUTPUT Chain Tests (Traffic from FWE) ---"

# Rule: F(TBD) Edge Router -> Internet TCP Web (80, 443) - NOW USES DHBW.DE
echo -n "Test 1.1: FWE Eigener Zugriff -> Internet ($PUBLIC_HOST:$HTTP_PORT) TCP ... "
test_nc "$EDGE_ROUTER" "$PUBLIC_HOST" "$HTTP_PORT" "tcp" "pass" "FWE OUT to Internet TCP 80"
echo -n "Test 1.2: FWE Eigener Zugriff -> Internet ($PUBLIC_HOST:$HTTPS_PORT) TCP ... "
test_nc "$EDGE_ROUTER" "$PUBLIC_HOST" "$HTTPS_PORT" "tcp" "pass" "FWE OUT to Internet TCP 443"

# Rule: F(TBD) Edge Router -> Internet UDP QUIC (443) - NOW USES DHBW.DE
echo -n "Test 1.3: FWE Eigener Zugriff -> Internet ($PUBLIC_HOST:$HTTPS_PORT) UDP (QUIC) ... "
test_nc "$EDGE_ROUTER" "$PUBLIC_HOST" "$HTTPS_PORT" "udp" "pass" "FWE OUT to Internet UDP 443"

# Rule: Edge Router -> SIEM OUTBOUND Logs (10.10.30.2) TCP/UDP 3100
echo -n "Test 1.4: FWE Logs -> SIEM ($SIEM_IP:$SIEM_LOG_PORT) TCP ... "
test_nc "$EDGE_ROUTER" "$SIEM_IP" "$SIEM_LOG_PORT" "tcp" "pass" "FWE OUT to SIEM TCP 3100"
echo -n "Test 1.5: FWE Logs -> SIEM ($SIEM_IP:$SIEM_LOG_PORT) UDP ... "
test_nc "$EDGE_ROUTER" "$SIEM_IP" "$SIEM_LOG_PORT" "udp" "pass" "FWE OUT to SIEM UDP 3100"


# --- 2. FORWARD Chain Tests (Transit Traffic) ---
echo "--- 2. FORWARD Chain Tests (Transit Traffic) ---"

# Rule F1: Attacker 1 (192.168.1.2) -> Rev Proxy (10.10.10.3) TCP Web (80, 443)
echo -n "Test 2.1: Attacker 1 -> Reverse Proxy ($REVPROXY_IP:$HTTP_PORT) TCP ... "
test_nc "$ATTACKER_CONTAINER" "$REVPROXY_IP" "$HTTP_PORT" "tcp" "pass" "Attacker to Rev Proxy TCP 80"
echo -n "Test 2.2: Attacker 1 -> Reverse Proxy ($REVPROXY_IP:$HTTPS_PORT) TCP ... "
test_nc "$ATTACKER_CONTAINER" "$REVPROXY_IP" "$HTTPS_PORT" "tcp" "pass" "Attacker to Rev Proxy TCP 443"

# Rule F(2,5,7,14,15): Internal Router (10.10.0.0/16) -> Internet TCP Web (80, 443) - NOW USES DHBW.DE
echo -n "Test 2.3: Internal Router -> Internet ($PUBLIC_HOST:$HTTP_PORT) TCP ... "
test_nc "$INTERNAL_ROUTER_CONTAINER" "$PUBLIC_HOST" "$HTTP_PORT" "tcp" "pass" "IR to Internet TCP 80"
echo -n "Test 2.4: Internal Router -> Internet ($PUBLIC_HOST:$HTTPS_PORT) TCP ... "
test_nc "$INTERNAL_ROUTER_CONTAINER" "$PUBLIC_HOST" "$HTTPS_PORT" "tcp" "pass" "IR to Internet TCP 443"

# Rule F(2,5,7,14,15): Internal Router (10.10.0.0/16) -> Internet UDP QUIC (443) - NOW USES DHBW.DE
echo -n "Test 2.5: Internal Router -> Internet ($PUBLIC_HOST:$HTTPS_PORT) UDP (QUIC) ... "
test_nc "$INTERNAL_ROUTER_CONTAINER" "$PUBLIC_HOST" "$HTTPS_PORT" "udp" "pass" "IR to Internet UDP 443"

# Rule F34: DNS Time Server (10.10.30.4) -> Internet DNS/NTP (53, 123) UDP - NOW USES DHBW.DE FOR DNS/NTP ACCESS
echo "--- Note: DNS/Time tests use IP since they are critical infrastructure ---"
# Test 2.6 and 2.7 remain on IP 8.8.8.8 to ensure that DNS/NTP specifically work to a non-DHBW.de server, as these are critical infrastructure services.
# If these were changed to use www.dhbw.de, the test would only check the forward rules, not the DNS service's primary function.
# Reverting to PUBLIC_IP for these tests.
echo -n "Test 2.6: DNS/Time Server -> Internet ($PUBLIC_IP:$DNS_PORT) UDP ... "
test_nc "$DNS_TIME_CONTAINER" "8.8.8.8" "$DNS_PORT" "udp" "pass" "DNS/Time to Internet UDP 53"
echo -n "Test 2.7: DNS/Time Server -> Internet ($PUBLIC_IP:$NTP_PORT) UDP ... "
test_nc "$DNS_TIME_CONTAINER" "8.8.8.8" "$NTP_PORT" "udp" "pass" "DNS/Time to Internet UDP 123"


# --- 3. Negative Tests (Blocked Traffic) ---
echo "--- 3. Negative Tests (Muss BLOCKIERT werden) ---"

# Negative Test 3.1: Internal Host (Client 10.10.20.2) -> DMZ (10.10.10.3) (Should be blocked by FORWARD policy)
echo -n "Test 3.1: Client (10.10.20.2) -> Reverse Proxy ($REVPROXY_IP:$HTTP_PORT) (Erwartet Block) ... "
test_nc "$CLIENT_CONTAINER" "$REVPROXY_IP" "$HTTP_PORT" "tcp" "fail" "Internal Host to DMZ Block"

# Negative Test 3.2: Attacker 1 -> Edge Router SSH (Should be blocked by INPUT policy/no matching rule)
echo -n "Test 3.2: Attacker 1 -> FWE SSH ($EDGE_ROUTER_MGMT_IP:$SSH_PORT) (Erwartet Block) ... "
docker exec $ATTACKER_CONTAINER nc -z -w2 $EDGE_ROUTER_MGMT_IP $SSH_PORT >/dev/null 2>&1
check_result $? "fail" "Attacker 1 to FWE SSH Block"

# Negative Test 3.3: Internal Host -> Reverse Proxy UDP (No QUIC rule for external traffic is present in FWE)
echo -n "Test 3.3: Attacker 1 -> Reverse Proxy ($REVPROXY_IP:$HTTPS_PORT) UDP (Erwartet Block) ... "
test_nc "$ATTACKER_CONTAINER" "$REVPROXY_IP" "$HTTPS_PORT" "udp" "fail" "Attacker to Rev Proxy UDP 443 Block"

echo "=== Tests abgeschlossen ==="
exit $TEST_FAILED