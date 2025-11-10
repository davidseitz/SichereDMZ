#!/bin/bash

# ==========================================================
# === IDS Kombi-Test (Nmap Scan & Path Traversal)        ===
# ==========================================================

# --- Konfiguration ---
ATTACKER_CONTAINER="clab-sun_dmz-attacker"
WAF_IP="10.10.1.10"         # Ziel für den Nmap Scan (löst auf WAF-IP aus)
WEB_IP="10.10.1.10"        # Ziel für den Path Traversal (geht zum Webserver) Zugriff über WAF
IDS_LOG_FILE="./logs/eve.json"

# Suricata Signature IDs (SIDs), die wir erwarten
SID_NMAP="2001899"          # ET SCAN Nmap Scripting Engine
SID_WEB="2001219"           # ET WEB_SERVER ../ (dot dot slash) Traversal

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
YLW="\033[0;33m"
NC="\033[0;30m"

echo "=== Starte automatisierte IDS-Tests ==="
# Globaler Fehlerstatus. 0 = OK, 1 = Fehler
TEST_FAILED=0

# --- Schritt 1: Log-Datei leeren ---
echo -n "Test 1: Vorbereitung (Log-Datei leeren)... "
if [ -f "$IDS_LOG_FILE" ]; then
    > "$IDS_LOG_FILE"
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FEHLER${NC}: Log-Datei $IDS_LOG_FILE nicht gefunden. Ist der 'logs' Ordner gemountet?"
    exit 1
fi

# --- Schritt 2: Angriffe ausführen ---
echo -n "Test 2.1: Führe Angriff 'Nmap Scan' aus... "
docker exec $ATTACKER_CONTAINER curl -s -o /dev/null -A "Nmap Scripting Engine" "http://$WAF_IP/"
echo -e "${GREEN}OK${NC}"

echo -n "Test 2.2: Führe Angriff 'Path Traversal' aus... "
docker exec $ATTACKER_CONTAINER curl -s -o /dev/null "http://$WEB_IP/index.php?file=../../etc/passwd"
echo -e "${GREEN}OK${NC}"


# --- Schritt 3: Warten ---
echo -n "Test 3: Warte 5 Sekunden auf IDS-Log-Verarbeitung... "
sleep 5
echo -e "${GREEN}OK${NC}"

# --- Schritt 4: Logs verifizieren ---
echo "Test 4: Werte Logs aus..."

# Test 4.1: Standard Regel (Nmap)
echo -n "  -> Prüfe auf Nmap Alert (sid:$SID_NMAP)... "
if grep -q "\"sid\":$SID_NMAP" $IDS_LOG_FILE; then
    echo -e "${GREEN}ERFOLG${NC}: 'Nmap' Alert gefunden."
else
    echo -e "${RED}FEHLER${NC}: 'Nmap' Alert (sid:$SID_NMAP) wurde NICHT gefunden."
    TEST_FAILED=1
fi

# Test 4.2: Web-Angriff Regel (Path Traversal)
echo -n "  -> Prüfe auf Path Traversal Alert (sid:$SID_WEB)... "
if grep -q "\"sid\":$SID_WEB" $IDS_LOG_FILE; then
    echo -e "${GREEN}ERFOLG${NC}: 'Path Traversal' Alert gefunden."
else
    echo -e "${RED}FEHLER${NC}: 'Path Traversal' Alert (sid:$SID_WEB) wurde NICHT gefunden."
    TEST_FAILED=1
fi

# --- Schritt 5: Zusammenfassung ---
echo "=== IDS-Tests abgeschlossen ==="
if [ $TEST_FAILED -eq 0 ]; then
    echo -e "${GREEN}Alle Tests erfolgreich bestanden!${NC}"
else
    echo -e "${RED}Mindestens ein Test ist fehlgeschlagen.${NC}"
fi

exit $TEST_FAILED