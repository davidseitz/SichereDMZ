#!/bin/bash

# --- Configuration & Container Names ---
# Derived from 'name: security_lab' in topology.yaml
PREFIX="clab-security_lab"
BASTION="$PREFIX-bastion"
ADMIN="$PREFIX-admin"
ATTACKER_1="$PREFIX-attacker_1"
ATTACKER_2="$PREFIX-attacker_2"

# --- Network Targets (Management IPs) ---
# IPs taken from 'exec' commands in topology.yaml
BASTION_IP="10.10.30.3"
WAF_IP="10.10.60.2"
WEBSERVER_IP="10.10.60.3"
DB_IP="10.10.60.4"
SIEM_IP="10.10.60.5"
EDGE_RTR_IP="10.10.60.6"
INT_RTR_IP="10.10.60.1"
NTP_DNS_IP="10.10.60.7"

# --- SSH Configuration ---
USER="admin"
# Note: WAF uses port 3025 in your original script.
# Assuming other internal nodes use standard port 22. Change if needed.
PORT_SSH="3025"


# Path to keys INSIDE the containers
KEY_BASTION="/home/admin/.ssh/id_rsa" # Key used BY Bastion
KEY_ADMIN="/root/.ssh/id_rsa"         # Key used BY Admin

# --- Colors ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

TEST_FAIL_COUNT=0

# --- Helper Function ---
# Usage: run_test <Source_Container> <Target_IP> <Target_Port> <Key_Path> <Expected_Result> <Test_Name>
run_test() {
    local src=$1
    local dst=$2
    local port=$3
    local key=$4
    local expect=$5 # "PASS" or "FAIL"
    local name=$6

    echo -n "Testing: $name ($src -> $dst:$port)... "

    # Construct command
    # -o LogLevel=ERROR: Suppresses "Warning: Permanently added..." messages
    # -o StrictHostKeyChecking=no: Auto-accept new keys
    # -o UserKnownHostsFile=/dev/null: Don't save keys to a real file
    # -o BatchMode=yes: Fail instead of asking for passwords
    local cmd="ssh -p $port -i $key -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5 $USER@$dst 'echo OK'"

    if [ -z "$key" ]; then
        # If no key provided (e.g. attackers), don't use -i
        cmd="ssh -p $port -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5 $USER@$dst 'echo OK'"
    fi

    # Execute inside container
    OUTPUT=$(docker exec $src sh -c "$cmd" 2>&1)
    EXIT_CODE=$?

    # Evaluate Result
    if [ "$expect" == "PASS" ]; then
        if [ $EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}SUCCESS${NC}"
        else
            echo -e "${RED}FAILED (Should have worked)${NC}"
            echo "  Error: $OUTPUT"
            TEST_FAIL_COUNT=$((TEST_FAIL_COUNT+1))
        fi
    else # Expect FAIL
        if [ $EXIT_CODE -ne 0 ]; then
            echo -e "${GREEN}BLOCKED (As expected)${NC}"
        else
            echo -e "${RED}VULNERABLE (Access allowed!)${NC}"
            TEST_FAIL_COUNT=$((TEST_FAIL_COUNT+1))
        fi
    fi
}

echo "=== Starting Expanded Connectivity Tests ==="

# ---------------------------------------------------------
# GROUP 1: BASTION OUTBOUND (Should all SUCCEED)
# ---------------------------------------------------------
echo "--- 1. Bastion -> Internal Infrastructure ---"

# Bastion -> WAF (Port 3025 based on previous script)
run_test $BASTION $WAF_IP $PORT_SSH $KEY_BASTION "PASS" "Bastion -> WAF"

# Bastion -> Webserver
run_test $BASTION $WEBSERVER_IP $PORT_SSH $KEY_BASTION "PASS" "Bastion -> Webserver"

# Bastion -> SIEM
run_test $BASTION $SIEM_IP $PORT_SSH $KEY_BASTION "PASS" "Bastion -> SIEM"

# Bastion -> Database
run_test $BASTION $DB_IP $PORT_SSH $KEY_BASTION "PASS" "Bastion -> Database"

# Bastion -> Internal Router
run_test $BASTION $INT_RTR_IP $PORT_SSH $KEY_BASTION "PASS" "Bastion -> Int. Router"

# Bastion -> Edge Router
run_test $BASTION $EDGE_RTR_IP $PORT_SSH $KEY_BASTION "PASS" "Bastion -> Edge Router"

# Bastion -> NTP/DNS
run_test $BASTION $NTP_DNS_IP $PORT_SSH $KEY_BASTION "PASS" "Bastion -> NTP/DNS"


# ---------------------------------------------------------
# GROUP 2: INBOUND TO BASTION (Access Control)
# ---------------------------------------------------------
echo "--- 2. Access to Bastion Host ---"

# Admin -> Bastion (Should SUCCEED)
# Admin container has key mounted at /root/.ssh/id_rsa
run_test $ADMIN $BASTION_IP $PORT_SSH $KEY_ADMIN "PASS" "Admin -> Bastion"

# Attacker 1 -> Bastion (External) (Should FAIL)
# Attacker 1 has no keys mounted in topology
run_test $ATTACKER_1 $BASTION_IP $PORT_SSH "" "FAIL" "Attacker 1 (Ext) -> Bastion"

# Attacker 2 -> Bastion (Internal Client Net) (Should FAIL)
# Attacker 2 has no keys mounted in topology
run_test $ATTACKER_2 $BASTION_IP $PORT_SSH "" "FAIL" "Attacker 2 (Int) -> Bastion"


echo "---------------------------------------------------------"
if [ $TEST_FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}ALL TESTS PASSED: Network segmentation and Access Control verified.${NC}"
    exit 0
else
    echo -e "${RED}$TEST_FAIL_COUNT TEST(S) FAILED. Check logs above.${NC}"
    exit 1
fi