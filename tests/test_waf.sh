#!/bin/bash

# ==========================================================
# === Automatisierter WAF & Reverse-Proxy Test (Erweitert) ===
#
# Test 1:   Prüft die Proxy-Funktion (Legitimer Zugriff).
# Test 2-4: Prüft die WAF-Funktion (Blockiert Angriffe).
# ==========================================================

# --- Konfiguration ---
ATTACKER_CONTAINER="clab-sun_dmz-attacker"
WAF_IP="10.10.1.10"
EXPECTED_CONTENT="Willkommen auf dem sicheren Webserver"

# Angriffs-Payloads (sollten alle 403 Forbidden auslösen)
ATTACK_URL_PATH="http://${WAF_IP}/?param=../../etc/passwd"
ATTACK_URL_XSS="http://${WAF_IP}/?search=<script>alert(1)</script>"
ATTACK_URL_SQLI="http://${WAF_IP}/?id=1%20OR%201=1" # %20 = URL-kodiertes Leerzeichen

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo "=== Starte automatisierte WAF/Proxy-Tests ==="
TEST_FAILED=0

# --- Test 1: Positiv-Test (Legitimer Zugriff) ---
echo -n "Test 1: Legitimer Zugriff ('attacker' -> 'waf') ... "
OUTPUT=$(docker exec $ATTACKER_CONTAINER wget -T 3 -qO- "http://$WAF_IP/")

if [ $? -eq 0 ] && [[ "$OUTPUT" == *"$EXPECTED_CONTENT"* ]]; then
    echo -e "${GREEN}ERFOLG${NC}: Proxy-Weiterleitung funktioniert."
else
    echo -e "${RED}FEHLER${NC}: Legitimer Zugriff fehlgeschlagen oder falscher Inhalt."
    TEST_FAILED=1
fi

# --- Test 2: Negativ-Test (Path Traversal) ---
echo -n "Test 2: Path Traversal Angriff ('attacker' -> 'waf') ... "
docker exec $ATTACKER_CONTAINER wget -S --spider -T 3 "$ATTACK_URL_PATH" 2>&1 | grep -q "403 Forbidden"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: WAF hat den Angriff korrekt blockiert (403 Forbidden gefunden)."
else
    echo -e "${RED}FEHLER${NC}: WAF hat den Angriff NICHT blockiert (403 Forbidden nicht gefunden)."
    TEST_FAILED=1
fi

# --- NEU: Test 3: Negativ-Test (Cross-Site Scripting) ---
echo -n "Test 3: Cross-Site Scripting (XSS) Angriff ('attacker' -> 'waf') ... "
docker exec $ATTACKER_CONTAINER wget -S --spider -T 3 "$ATTACK_URL_XSS" 2>&1 | grep -q "403 Forbidden"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: WAF hat den Angriff korrekt blockiert (403 Forbidden gefunden)."
else
    echo -e "${RED}FEHLER${NC}: WAF hat den Angriff NICHT blockiert (403 Forbidden nicht gefunden)."
    TEST_FAILED=1
fi

# --- NEU: Test 4: Negativ-Test (SQL-Injection) ---
echo -n "Test 4: SQL-Injection (SQLi) Angriff ('attacker' -> 'waf') ... "
docker exec $ATTACKER_CONTAINER wget -S --spider -T 3 "$ATTACK_URL_SQLI" 2>&1 | grep -q "403 Forbidden"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: WAF hat den Angriff korrekt blockiert (403 Forbidden gefunden)."
else
    echo -e "${RED}FEHLER${NC}: WAF hat den Angriff NICHT blockiert (403 Forbidden nicht gefunden)."
    TEST_FAILED=1
fi

echo "=== WAF/Proxy-Tests abgeschlossen ==="
exit $TEST_FAILED