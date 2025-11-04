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

# Führe wget aus und prüfe den stderr-Output direkt mit grep
# -q = quiet mode (keine Ausgabe)
# Wir suchen nach der Zeichenkette "403 Forbidden", die die WAF senden muss.
docker exec $ATTACKER_CONTAINER wget -S --spider -T 3 "$ATTACK_URL" 2>&1 | grep -q "403 Forbidden"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: WAF hat den Angriff korrekt blockiert (403 Forbidden gefunden)."
else
    echo -e "${RED}FEHLER${NC}: WAF hat den Angriff NICHT blockiert (403 Forbidden nicht gefunden)."
    TEST_FAILED=1
fi

echo "=== WAF/Proxy-Tests abgeschlossen ==="
exit $TEST_FAILED