#!/bin/bash

# ==========================================================
# === IDS Test (V1) - Testet Custom & Standard Regeln ===
# ==========================================================

# --- Konfiguration ---
ATTACKER_CONTAINER="clab-sun_dmz-attacker"
WAF_IP="10.10.1.10"
IDS_LOG_FILE="./ids_config/logs/eve.json"

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo "=== Starte automatisierte IDS-Tests ==="
TEST_FAILED=0

# --- Schritt 1: Log-Datei leeren ---
echo -n "Test 1: Vorbereitung (Log-Datei leeren)... "
> $IDS_LOG_FILE
echo -e "${GREEN}OK${NC}"

# --- Schritt 2: Angriffe ausführen ---
# Wir führen die Angriffe aus, die das IDS erkennen soll.
echo -n "Test 2: Angriffe (Custom Rule und 'Nmap' UA) werden ausgeführt... "
# Auslöser für unsere Custom-Regel (sid:1000001)
docker exec $ATTACKER_CONTAINER curl -s -o /dev/null "http://$WAF_IP/?id=root"
# Auslöser für Standard ET Open Regel (sid:2001899)
docker exec $ATTACKER_CONTAINER curl -s -o /dev/null -A "Nmap Scripting Engine" "http://$WAF_IP/"
echo -e "${GREEN}OK${NC}"

# --- Schritt 3: Warten ---
# Suricata ist nicht real-time. Wir MÜSSEN ihm Zeit geben,
# die Logs auf die Festplatte zu schreiben.
echo -n "Test 3: Warte 5 Sekunden auf IDS-Log-Verarbeitung... "
sleep 5
echo -e "${GREEN}OK${NC}"

# --- Schritt 4: Logs verifizieren ---

# Test 4.1: Custom Regel
echo -n "Test 4.1 (Positiv): Prüfe auf Custom Alert (sid:1000001)... "
if grep -q '"sid":1000001' $IDS_LOG_FILE; then
    echo -e "${GREEN}ERFOLG${NC}: Custom Alert 'id=root' wurde im Log gefunden."
else
    echo -e "${RED}FEHLER${NC}: Custom Alert (sid:1000001) wurde NICHT gefunden."
    TEST_FAILED=1
fi

# Test 4.2: Standard Regel
# SID 2001899 = "ET SCAN Nmap Scripting Engine User-Agent"
echo -n "Test 4.2 (Positiv): Prüfe auf Standard Alert (sid:2001899)... "
if grep -q '"sid":2001899' $IDS_LOG_FILE; then
    echo -e "${GREEN}ERFOLG${NC}: Standard 'Nmap' Alert wurde im Log gefunden."
else
    echo -e "${RED}FEHLER${NC}: Standard Alert (sid:2001899) wurde NICHT gefunden."
    TEST_FAILED=1
fi

echo "=== IDS-Tests abgeschlossen ==="
exit $TEST_FAILED