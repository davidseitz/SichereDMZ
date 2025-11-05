#!/bin/bash

# =================================================================
# === Master Firewall Test (V3) - Zero Trust Validierung ===
# =================================================================

# --- Konfiguration ---
ATTACKER_CONTAINER="clab-sun_dmz-attacker"
CLIENT_CONTAINER="clab-sun_dmz-client"

WAF_IP="10.10.1.10"
WEB_IP="10.10.1.100"
IDS_IP="10.10.1.20"
SIEM_IP="10.10.3.10"

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo "=== Starte Master-Firewall-Tests (Positiv & Negativ) ==="
TEST_FAILED=0

# --- Hilfsfunktion zum Zählen von Fehlern ---
function check_result {
    # $1 = $? (Exit-Code des letzten Befehls)
    # $2 = "true" (Verbindung erwartet) oder "false" (Block erwartet)
    
    if [ "$2" == "true" ]; then # POSITIV-TEST
        if [ $1 -eq 0 ]; then
            echo -e "${GREEN}ERFOLG${NC}: Verbindung wie erwartet hergestellt."
        else
            echo -e "${RED}FEHLER${NC}: Verbindung fehlgeschlagen (sollte erlaubt sein)."
            TEST_FAILED=1
        fi
    else # NEGATIV-TEST
        if [ $1 -ne 0 ]; then
            echo -e "${GREEN}ERFOLG${NC}: Verbindung wie erwartet blockiert."
        else
            echo -e "${RED}FEHLER${NC}: Verbindung war erfolgreich (Firewall-Lücke!)."
            TEST_FAILED=1
        fi
    fi
}

# ==========================================================
echo "--- Sektion 1: Internet (attacker) -> DMZ & Intern ---"
# ==========================================================

# Test 1.1: attacker -> waf (Erlaubt)
echo -n "Test 1.1 (Positiv): 'attacker' -> 'waf' ($WAF_IP:80) ... "
docker exec $ATTACKER_CONTAINER nc -z -w 2 $WAF_IP 80 > /dev/null 2>&1
check_result $? "true"

# Test 1.2: attacker -> web (Blockiert)
echo -n "Test 1.2 (Negativ): 'attacker' -> 'web' ($WEB_IP:80) ... "
docker exec $ATTACKER_CONTAINER nc -z -w 2 $WEB_IP 80 > /dev/null 2>&1
check_result $? "false"

# Test 1.3: attacker -> ids (Blockiert)
echo -n "Test 1.3 (Negativ): 'attacker' -> 'ids' ($IDS_IP:80) ... "
docker exec $ATTACKER_CONTAINER nc -z -w 2 $IDS_IP 80 > /dev/null 2>&1
check_result $? "false"

# Test 1.4: attacker -> siem (Blockiert)
echo -n "Test 1.4 (Negativ): 'attacker' -> 'siem' ($SIEM_IP:1514) ... "
docker exec $ATTACKER_CONTAINER nc -z -w 2 $SIEM_IP 1514 > /dev/null 2>&1
check_result $? "false"

# Test 1.5 (NEU): attacker -> waf auf falschem Port (Blockiert)
echo -n "Test 1.5 (Negativ): 'attacker' -> 'waf' ($WAF_IP:22) ... "
docker exec $ATTACKER_CONTAINER nc -z -w 2 $WAF_IP 22 > /dev/null 2>&1
check_result $? "false"

# ==========================================================
echo "--- Sektion 2: Internes Netz (client) -> DMZ & Backend ---"
# ==========================================================

# Test 2.1: client -> waf (Erlaubt)
echo -n "Test 2.1 (Positiv): 'client' -> 'waf' ($WAF_IP:80) ... "
docker exec $CLIENT_CONTAINER nc -z -w 2 $WAF_IP 80 > /dev/null 2>&1
check_result $? "true"

# Test 2.2: client -> web (Blockiert)
echo -n "Test 2.2 (Negativ): 'client' -> 'web' ($WEB_IP:80) ... "
docker exec $CLIENT_CONTAINER nc -z -w 2 $WEB_IP 80 > /dev/null 2>&1
check_result $? "false"

# Test 2.3: client -> ids (Blockiert)
echo -n "Test 2.3 (Negativ): 'client' -> 'ids' ($IDS_IP:80) ... "
docker exec $CLIENT_CONTAINER nc -z -w 2 $IDS_IP 80 > /dev/null 2>&1
check_result $? "false"

# Test 2.4: client -> siem (Erlaubt auf Port 1514)
echo -n "Test 2.4 (Positiv): 'client' -> 'siem' ($SIEM_IP:1514) ... "
docker exec $CLIENT_CONTAINER nc -z -w 2 $SIEM_IP 1514 > /dev/null 2>&1
check_result $? "true"

# Test 2.5 (NEU): client -> siem auf falschem Port (Blockiert)
echo -n "Test 2.5 (Negativ): 'client' -> 'siem' ($SIEM_IP:80) ... "
docker exec $CLIENT_CONTAINER nc -z -w 2 $SIEM_IP 80 > /dev/null 2>&1
check_result $? "false"

echo "=== Firewall-Tests abgeschlossen ==="
exit $TEST_FAILED