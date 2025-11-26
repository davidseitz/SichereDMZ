#!/bin/bash

# --- Configuration ---
# Container names (unchanged)
INTERNAL_ROUTER_CONTAINER="clab-security_lab-internal_router"
BASTION_CONTAINER="clab-security_lab-bastion"
ADMIN_CONTAINER="clab-security_lab-admin"
ATTACKER_CONTAINER="clab-security_lab-attacker_2"
WEB_CONTAINER="clab-security_lab-web_server" # 10.10.10.4
DB_CONTAINER="clab-security_lab-database"   # Assumed: 10.10.40.2 (DB_IP)
WAF_CONTAINER="clab-security_lab-reverse_proxy"       # Assumed: 10.10.10.3

# IP Addresses from nftables rules
EDGE_ROUTER_IP="10.10.50.1" # ethtransit
INTERNAL_ROUTER_MGMT_IP="10.10.60.1"
INTERNAL_ROUTER_TRANSIT_IP="10.10.50.2"
BASTION_IP="10.10.30.3"
ADMIN_IP="10.10.20.2"
ATTACKER2_IP="10.10.20.3"
WAF_IP="10.10.10.3"
DB_IP="10.10.40.2"
SIEM_IP="10.10.30.2"
TIME_DNS_IP="10.10.30.4"
PUBLIC_IP="8.8.8.8"

# Ports
SSH_PORT="3025"
DB_PORT="3306"
SIEM_LOG_PORT="3100"
DNS_PORT="53"
NTP_PORT="123"
HTTP_PORT="80"
HTTPS_PORT="443"

# Authentication
PRIVATE_KEY_PATH="/root/.ssh/id_rsa"

# --- Colors ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo "=== Start Internal Router Firewall Tests ==="
TEST_FAILED=0

# Helper function for netcat tests
test_nc() {
    local SOURCE_CONT=$1
    local DEST_IP=$2
    local PORT=$3
    local PROTO=$4 # tcp or udp
    local EXPECT_PASS=$5 # 0 for pass, 1 for fail
    local TEST_NAME="$6"

    local COMMAND="docker exec $SOURCE_CONT nc -z -w 2 "
    if [ "$PROTO" == "udp" ]; then
        COMMAND="$COMMAND -u "
    fi
    COMMAND="$COMMAND $DEST_IP $PORT"
    
    # Execute the command silently
    $COMMAND >/dev/null 2>&1
    local RESULT=$?

    if [ $EXPECT_PASS -eq 0 ]; then
        if [ $RESULT -eq 0 ]; then
            echo -e "${GREEN}SUCCESS${NC}"
        else
            echo -e "${RED}FAILED (Should PASS)${NC}"
            TEST_FAILED=1
        fi
    else
        if [ $RESULT -ne 0 ]; then
            echo -e "${GREEN}SUCCESS (Blocked as expected)${NC}"
        else
            echo -e "${RED}FAILED (Should be BLOCKED)${NC}"
            TEST_FAILED=1
        fi
    fi
}

# Helper function for SSH tests
test_ssh() {
    local SOURCE_CONT=$1
    local DEST_IP=$2
    local PORT=$3
    local EXPECT_PASS=$4 # 0 for pass, 1 for fail
    local TEST_NAME="$5"

    local COMMAND="docker exec $SOURCE_CONT ssh -p $PORT -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$DEST_IP \"echo SSH_SUCCESS\""

    # Execute the command silently
    $COMMAND >/dev/null 2>&1
    local RESULT=$?
    
    if [ $EXPECT_PASS -eq 0 ]; then
        if [ $RESULT -eq 0 ]; then
            echo -e "${GREEN}SUCCESS${NC}"
        else
            echo -e "${RED}FAILED (Should PASS)${NC}"
            TEST_FAILED=1
        fi
    else
        if [ $RESULT -ne 0 ]; then
            echo -e "${GREEN}SUCCESS (Blocked as expected)${NC}"
        else
            echo -e "${RED}FAILED (Should be BLOCKED)${NC}"
            TEST_FAILED=1
        fi
    fi
}

# --- Section 1: FORWARD Rules (Internal Traffic) ---
echo "--- 1. FORWARD Rules (Internal Traffic) ---"

# F4: Webserver (10.10.10.4) -> Database (10.10.40.2) MariaDB 3306
echo -n "Test 1.1: $WEB_CONTAINER -> DB MariaDB ($DB_IP:$DB_PORT) ... "
test_nc "$WEB_CONTAINER" "$DB_IP" "$DB_PORT" "tcp" 0 "Web -> DB MariaDB"

# F22, F23: Admin/Attacker 2 -> Time/DNS (10.10.30.4) UDP 53, 123
echo -n "Test 1.2: $ADMIN_CONTAINER -> DNS/Time ($TIME_DNS_IP:$DNS_PORT) UDP ... "
test_nc "$ADMIN_CONTAINER" "$TIME_DNS_IP" "$DNS_PORT" "udp" 0 "Admin -> DNS UDP"
echo -n "Test 1.3: $ATTACKER_CONTAINER -> DNS/Time ($TIME_DNS_IP:$NTP_PORT) UDP ... "
test_nc "$ATTACKER_CONTAINER" "$TIME_DNS_IP" "$NTP_PORT" "udp" 0 "Attacker2 -> NTP UDP"

# F22, F23: Admin/Attacker 2 -> Time/DNS (10.10.30.4) TCP 53
echo -n "Test 1.4: $ADMIN_CONTAINER -> DNS ($TIME_DNS_IP:$DNS_PORT) TCP ... "
test_nc "$ADMIN_CONTAINER" "$TIME_DNS_IP" "$DNS_PORT" "tcp" 0 "Admin -> DNS TCP"

# F16, F18, F21, F20: Traffic to SIEM (3100) - Test Webserver (10.10.10.4) to SIEM (10.10.30.2) TCP/UDP 3100
echo -n "Test 1.5: $WEB_CONTAINER -> SIEM Logs ($SIEM_IP:$SIEM_LOG_PORT) TCP ... "
test_nc "$WEB_CONTAINER" "$SIEM_IP" "$SIEM_LOG_PORT" "tcp" 0 "Web -> SIEM TCP"
echo "Skipt Test 1.6 NOT IMPLEMENTED UDP LOGS"
#echo -n "Test 1.6: $WEB_CONTAINER -> SIEM Logs ($SIEM_IP:$SIEM_LOG_PORT) UDP ... "
#test_nc "$WEB_CONTAINER" "$SIEM_IP" "$SIEM_LOG_PORT" "udp" 0 "Web -> SIEM UDP"

# F7: Admin/Attacker 2 -> Internet (Simulated via Edge Router $EDGE_ROUTER_IP) TCP 80/443
# Note: Since we can't truly test internet access, we test if the traffic makes it to the next hop (Edge Router).
# We use the Edge Router's IP as a proxy destination for the Forward rule test.
echo -n "Test 1.7: $ATTACKER_CONTAINER -> Edge Router HTTPS ($PUBLIC_IP:$HTTPS_PORT) UDP (QUIC) ... "
test_nc "$ATTACKER_CONTAINER" "$EDGE_ROUTER_IP" "$HTTPS_PORT" "udp" 0 "Attacker2 -> Internet UDP 443"

# --- Section 2: OUTPUT Rules (Router Initiated Traffic) ---
echo "--- 2. OUTPUT Rules (FWI Initiated Traffic) ---"

# F19: Internal Router (10.10.30.1) -> SIEM (10.10.30.2) TCP/UDP 3100
echo -n "Test 2.1: $INTERNAL_ROUTER_CONTAINER -> SIEM Logs ($SIEM_IP:$SIEM_LOG_PORT) TCP ... "
test_nc "$INTERNAL_ROUTER_CONTAINER" "$SIEM_IP" "$SIEM_LOG_PORT" "tcp" 0 "FWI -> SIEM TCP"
echo "Skipt Test 2.2 NOT IMPLEMENTED UDP LOGS"
#echo -n "Test 2.2: $INTERNAL_ROUTER_CONTAINER -> SIEM Logs ($SIEM_IP:$SIEM_LOG_PORT) UDP ... "
#test_nc "$INTERNAL_ROUTER_CONTAINER" "$SIEM_IP" "$SIEM_LOG_PORT" "udp" 0 "FWI -> SIEM UDP"

# F33: Internal Router (10.10.50.2) -> Internet (Simulated via PUBLIC_IP) TCP 80/443
# This tests if the FWI can send traffic out of its ethtransit interface to a remote host.
echo -n "Test 2.3: $INTERNAL_ROUTER_CONTAINER -> Internet HTTPS ($PUBLIC_IP:$HTTPS_PORT) UDP (QUIC) ... "
test_nc "$INTERNAL_ROUTER_CONTAINER" "$PUBLIC_IP" "$HTTPS_PORT" "udp" 0 "FWI -> Internet UDP 443"

# F25: Internal Router -> Time/DNS (10.10.30.4) UDP 53/123
echo -n "Test 2.4: $INTERNAL_ROUTER_CONTAINER -> DNS ($TIME_DNS_IP:$DNS_PORT) UDP ... "
test_nc "$INTERNAL_ROUTER_CONTAINER" "$TIME_DNS_IP" "$DNS_PORT" "udp" 0 "FWI -> DNS UDP"
echo -n "Test 2.5: $INTERNAL_ROUTER_CONTAINER -> NTP ($TIME_DNS_IP:$NTP_PORT) UDP ... "
test_nc "$INTERNAL_ROUTER_CONTAINER" "$TIME_DNS_IP" "$NTP_PORT" "udp" 0 "FWI -> NTP UDP"

# --- Section 3: Negative Tests (Traffic that MUST be blocked) ---
echo "--- 3. Negative Tests (Must be Blocked) ---"

# Block Test 3.1: Admin -> DB MariaDB (Not allowed by rules, should be dropped by FORWARD policy)
echo -n "Test 3.1: $ADMIN_CONTAINER -> DB MariaDB ($DB_IP:$DB_PORT) (Expected Block) ... "
test_nc "$ADMIN_CONTAINER" "$DB_IP" "$DB_PORT" "tcp" 1 "Admin -> DB MariaDB Block"

# Block Test 3.2: Webserver -> Admin SSH (Not allowed by rules)
echo -n "Test 3.2: $WEB_CONTAINER -> Admin SSH ($ADMIN_IP:$SSH_PORT) (Expected Block) ... "
test_ssh "$WEB_CONTAINER" "$ADMIN_IP" "$SSH_PORT" 1 "Web -> Admin SSH Block"

# Block Test 3.3: Attacker 2 -> Internal Router SSH (Only Bastion is allowed in INPUT)
echo -n "Test 3.3: $ATTACKER_CONTAINER -> FWI Mgmt SSH ($INTERNAL_ROUTER_MGMT_IP:$SSH_PORT) (Expected Block) ... "
test_ssh "$ATTACKER_CONTAINER" "$INTERNAL_ROUTER_MGMT_IP" "$SSH_PORT" 1 "Attacker2 -> FWI SSH Block"

# Block Test 3.4: Attacker 2 -> SIEM (10.10.30.2) Logs - Attacker 2 IP (10.10.20.3) is not in the SIEM source IP list (F16, F18, F21, F20 source list)
# NOTE: The rule F22/F23 allows Admin/Attacker2 DNS/Time, but NOT SIEM logs.
echo -n "Test 3.4: $ATTACKER_CONTAINER -> SIEM Logs ($SIEM_IP:$SIEM_LOG_PORT) TCP (Expected Block) ... "
test_nc "$ATTACKER_CONTAINER" "$SIEM_IP" "$SIEM_LOG_PORT" "tcp" 1 "Attacker2 -> SIEM Logs Block"


echo "=== Internal Router Firewall Tests Completed ==="
exit $TEST_FAILED