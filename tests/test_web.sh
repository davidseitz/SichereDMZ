#!/bin/bash

# --- Konfiguration ---
WAF_CONTAINER="clab-sun_dmz-waf"
WEB_SERVER_IP="10.10.1.100"
CORRECT_HOST="web.sun.dmz"
EXPECTED_CONTENT="Willkommen auf dem sicheren Webserver"

# --- Farben für die Ausgabe ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo "=== Starte automatisierte Tests für Webserver-Härtung ==="
TEST_FAILED=0

# --- Test 1: Negative Härtungs-Test ---
# Wir prüfen, ob ein direkter IP-Zugriff (ohne Host-Header) fehlschlägt.
# Wir erwarten einen non-zero exit code von wget.
echo -n "Test 1: Direkter IP-Zugriff auf $WEB_SERVER_IP ... "
# -T 2 = 2 Sekunden Timeout. > /dev/null leitet HTML-Ausgabe (falls vorhanden) ins Nichts.
docker exec $WAF_CONTAINER wget -T 2 -qO- $WEB_SERVER_IP > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: Server hat die Verbindung wie erwartet abgewiesen."
else
    echo -e "${RED}FEHLER${NC}: Direkter IP-Zugriff war erfolgreich. Härtung defekt!"
    TEST_FAILED=1
fi

# --- Test 2: Positiver Funktions-Test ---
# Wir prüfen, ob der Zugriff MIT Host-Header funktioniert UND den richtigen Inhalt liefert.
echo -n "Test 2: Zugriff mit Host-Header '$CORRECT_HOST' ... "

# Führe wget aus und speichere die Ausgabe
OUTPUT=$(docker exec $WAF_CONTAINER wget --header="Host: $CORRECT_HOST" -T 2 -qO- $WEB_SERVER_IP 2>/dev/null)

# Prüfe den Exit-Code UND ob der Inhalt gefunden wurde
if [ $? -eq 0 ] && [[ "$OUTPUT" == *"$EXPECTED_CONTENT"* ]]; then
    echo -e "${GREEN}ERFOLG${NC}: Korrekte Webseite wurde ausgeliefert."
elif [ $? -ne 0 ]; then
    echo -e "${RED}FEHLER${NC}: Server hat die Verbindung trotz korrektem Host-Header abgewiesen."
    TEST_FAILED=1
else
    echo -e "${RED}FEHLER${NC}: Falscher Inhalt wurde ausgeliefert. Erwartet: '$EXPECTED_CONTENT'."
    TEST_FAILED=1
fi

echo "=== Tests abgeschlossen ==="
exit $TEST_FAILED