#!/bin/bash

# --- Configuration ---
INTERNAL_ROUTER_CONTAINER="clab-security_lab-internal_router"
BASTION_CONTAINER="clab-security_lab-bastion"
ADMIN_CONTAINER="clab-security_lab-admin"
WEB_CONTAINER="clab-security_lab-web_server"
WAF_IP="10.10.60.2"
SIEM_IP="10.10.30.2"
DB_IP="10.10.60.4"
TIME_DNS_IP="10.10.30.4"
SSH_PORT="3025"
PRIVATE_KEY_PATH="/root/.ssh/id_rsa"

# --- Colors ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo "=== Start Internal Router Firewall Tests ==="
TEST_FAILED=0

# --- Test 1: Bastion -> WAF / Reverse Proxy SSH (INPUT) ---
echo -n "Test 1: Bastion -> WAF / Reverse Proxy SSH ... "
docker exec $BASTION_CONTAINER ssh -p $SSH_PORT -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$WAF_IP "echo SSH_SUCCESS" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}SUCCESS${NC}"
else
    echo -e "${RED}FAILED${NC}"
    TEST_FAILED=1
fi

# --- Test 2: Bastion -> Database SSH (FORWARD) ---
echo -n "Test 2: Bastion -> Database SSH ... "
docker exec $BASTION_CONTAINER ssh -p $SSH_PORT -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$DB_IP "echo SSH_SUCCESS" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}SUCCESS${NC}"
else
    echo -e "${RED}FAILED${NC}"
    TEST_FAILED=1
fi

# --- Test 3: Admin -> Edge Router HTTP/HTTPS (FORWARD) ---
echo -n "Test 3: Admin -> Edge Router HTTP/HTTPS ... "
docker exec $ADMIN_CONTAINER nc -z -w 2 10.10.50.1 80 >/dev/null 2>&1
RES1=$?
docker exec $ADMIN_CONTAINER nc -z -w 2 10.10.50.1 443 >/dev/null 2>&1
RES2=$?
if [ $RES1 -eq 0 ] && [ $RES2 -eq 0 ]; then
    echo -e "${GREEN}SUCCESS${NC}"
else
    echo -e "${RED}FAILED${NC}"
    TEST_FAILED=1
fi

# --- Test 4: SIEM Log Ports (TCP 3100) ---
echo -n "Test 4: Internal Router -> SIEM TCP 3100 ... "
docker exec $INTERNAL_ROUTER_CONTAINER nc -z -w 2 $SIEM_IP 3100 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}SUCCESS${NC}"
else
    echo -e "${RED}FAILED${NC}"
    TEST_FAILED=1
fi

# --- Test 5: DNS/Time Server UDP 53/123 ---
echo -n "Test 5: Internal Router -> Time/DNS UDP 53/123 ... "
docker exec $INTERNAL_ROUTER_CONTAINER nc -z -u -w 2 $TIME_DNS_IP 53 >/dev/null 2>&1
RES1=$?
docker exec $INTERNAL_ROUTER_CONTAINER nc -z -u -w 2 $TIME_DNS_IP 123 >/dev/null 2>&1
RES2=$?
if [ $RES1 -eq 0 ] && [ $RES2 -eq 0 ]; then
    echo -e "${GREEN}SUCCESS${NC}"
else
    echo -e "${RED}FAILED${NC}"
    TEST_FAILED=1
fi

# --- Test 6: Negative Test (Attacker 2 blocked to SIEM) ---
echo -n "Test 6: Attacker 2 -> SIEM TCP 3100 (should fail) ... "
docker exec $ADMIN_CONTAINER nc -z -w 2 $SIEM_IP 3100 >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${GREEN}SUCCESS (blocked as expected)${NC}"
else
    echo -e "${RED}FAILED (should be blocked)${NC}"
    TEST_FAILED=1
fi

echo "=== Internal Router Firewall Tests Completed ==="
exit $TEST_FAILED
