#!/bin/bash

# === Automatisierter WAF & Reverse-Proxy Test ===

# --- Konfiguration ---
ATTACKER_CONTAINER="clab-sun_dmz-attacker"
WAF_IP="10.10.1.10"
EXPECTED_CONTENT="Willkommen auf dem sicheren Webserver"

# Ein einfacher Path-Traversal-Angriff, der von OWASP CRS blockiert wird
ATTACK_URL="http://${WAF_IP}/?param=../../etc/passwd"

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo "=== Starte automatisierte WAF/Proxy-Tests ==="
TEST_FAILED=0

# --- Test 1: Positiv-Test (Legitimer Zugriff) ---
echo -n "Test 1: Legitimer Zugriff ('attacker' -> 'waf') ... "
# -T 3 = 3 Sekunden Timeout
OUTPUT=$(docker exec $ATTACKER_CONTAINER wget -T 3 -qO- "http://$WAF_IP/")

if [ $? -eq 0 ] && [[ "$OUTPUT" == *"$EXPECTED_CONTENT"* ]]; then
    echo -e "${GREEN}ERFOLG${NC}: Proxy-Weiterleitung funktioniert."
else
    echo -e "${RED}FEHLER${NC}: Legitimer Zugriff fehlgeschlagen oder falscher Inhalt."
    TEST_FAILED=1
fi

# --- Test 2: Negativ-Test (WAF-Angriff) ---
echo -n "Test 2: Path Traversal Angriff ('attacker' -> 'waf') ... "
# -S = --server-response (um den HTTP-Statuscode zu sehen)
# Wir erwarten einen HTTP 403 (Forbidden) von der WAF
HTTP_STATUS=$(docker exec $ATTACKER_CONTAINER wget -S --spider -T 3 "$ATTACK_URL" 2>&1 | grep "HTTP/" | awk '{print $2}')

if [ "$HTTP_STATUS" == "403" ]; then
    echo -e "${GREEN}ERFOLG${NC}: WAF hat den Angriff korrekt blockiert (HTTP 403)."
elif [ -z "$HTTP_STATUS" ]; then
    echo -e "${RED}FEHLER${NC}: WAF hat nicht geantwortet (Timeout?)."
    TEST_FAILED=1
else
    echo -e "${RED}FEHLER${NC}: WAF hat den Angriff durchgelassen (Status: $HTTP_STATUS). Erwartet: 403."
    TEST_FAILED=1
fi

echo "=== WAF/Proxy-Tests abgeschlossen ==="
exit $TEST_FAILED