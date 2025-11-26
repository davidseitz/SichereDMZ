#!/bin/bash

# ==========================================================
# === Automatisierter WAF & Reverse-Proxy Test (HTTPS) ===
#
# Test 1:   Prüft die Proxy-Funktion (Legitimer Zugriff).
# Test 2-4: Prüft die WAF-Funktion (Blockiert Angriffe).
# ==========================================================

# --- Konfiguration ---
ATTACKER_CONTAINER="clab-security_lab-attacker_1"
WAF_IP="10.10.10.3"
EXPECTED_CONTENT="Willkommen - SUN DMZ Webserver"

# --- WICHTIG: Auf HTTPS und --no-check-certificate umgestellt ---
BASE_URL="https://${WAF_IP}"
WGET_OPTS="--no-check-certificate -T 3" # Optionen für wget

# Angriffs-Payloads (sollten alle 403 Forbidden auslösen)
ATTACK_URL_PATH="${BASE_URL}/?param=../../etc/passwd"
ATTACK_URL_XSS="${BASE_URL}/?search=<script>alert(1)</script>"
ATTACK_URL_SQLI="${BASE_URL}/?id=1%20OR%201=1" # %20 = URL-kodiertes Leerzeichen

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo "=== Starte automatisierte WAF/Proxy-Tests (HTTPS) ==="
TEST_FAILED=0

# --- Test 1: Positiv-Test (Legitimer Zugriff) ---
echo -n "Test 1: Legitimer HTTPS-Zugriff ('attacker' -> 'waf') ... "
# -qO- (quiet, output to stdout)
OUTPUT=$(docker exec $ATTACKER_CONTAINER wget $WGET_OPTS -qO- "${BASE_URL}/")

if [ $? -eq 0 ] && [[ "$OUTPUT" == *"$EXPECTED_CONTENT"* ]]; then
    echo -e "${GREEN}ERFOLG${NC}: Proxy-Weiterleitung funktioniert."
else
    echo -e "${RED}FEHLER${NC}: Legitimer Zugriff fehlgeschlagen oder falscher Inhalt."
    TEST_FAILED=1
fi

# --- Test 2: Negativ-Test (Path Traversal) ---
echo -n "Test 2: Path Traversal Angriff ('attacker' -> 'waf') ... "
# -S --spider (show headers, don't download)
docker exec $ATTACKER_CONTAINER wget $WGET_OPTS -S --spider "$ATTACK_URL_PATH" 2>&1 | grep -q "403 Forbidden"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: WAF hat den Angriff korrekt blockiert (403 Forbidden gefunden)."
else
    echo -e "${RED}FEHLER${NC}: WAF hat den Angriff NICHT blockiert (403 Forbidden nicht gefunden)."
    TEST_FAILED=1
fi

# --- Test 3: Negativ-Test (Cross-Site Scripting) ---
echo -n "Test 3: Cross-Site Scripting (XSS) Angriff ('attacker' -> 'waf') ... "
docker exec $ATTACKER_CONTAINER wget $WGET_OPTS -S --spider "$ATTACK_URL_XSS" 2>&1 | grep -q "403 Forbidden"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: WAF hat den Angriff korrekt blockiert (403 Forbidden gefunden)."
else
    echo -e "${RED}FEHLER${NC}: WAF hat den Angriff NICHT blockiert (403 Forbidden nicht gefunden)."
    TEST_FAILED=1
fi

# --- Test 4: Negativ-Test (SQL-Injection) ---
echo -n "Test 4: SQL-Injection (SQLi) Angriff ('attacker' -> 'waf') ... "
docker exec $ATTACKER_CONTAINER wget $WGET_OPTS -S --spider "$ATTACK_URL_SQLI" 2>&1 | grep -q "403 Forbidden"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: WAF hat den Angriff korrekt blockiert (403 Forbidden gefunden)."
else
    echo -e "${RED}FEHLER${NC}: WAF hat den Angriff NICHT blockiert (403 Forbidden nicht gefunden)."
    TEST_FAILED=1
fi

# ---: Test 5: Detaillierte Prüfung des benutzerdefinierten Zertifikats ---
echo -n "Test 5: Benutzerdefiniertes Zertifikat (Self-Signed & Alle Felder) prüfen ... "

# Erfordert, dass 'openssl' im $ATTACKER_CONTAINER installiert ist
CERT_INFO=$(echo | docker exec $ATTACKER_CONTAINER \
    openssl s_client -connect ${WAF_IP}:443 2>/dev/null \
    | openssl x509 -noout -subject -issuer 2>/dev/null)

SUBJECT_LINE=$(echo "$CERT_INFO" | grep 'subject=' | sed 's/subject= *//')
ISSUER_LINE=$(echo "$CERT_INFO" | grep 'issuer=' | sed 's/issuer= *//')

# 1. Prüfen, ob es selbst-signiert ist (Subject == Issuer)
if [ -n "$SUBJECT_LINE" ] && [ "$SUBJECT_LINE" == "$ISSUER_LINE" ]; then

    # 2. Prüfen, ob alle Felder im Subject enthalten sind
    # Wir führen eine Reihe von 'grep's aus. Wenn eines fehlschlägt, ist das Ergebnis falsch.
    (
        echo "$SUBJECT_LINE" | grep -q "C = DE" && \
        echo "$SUBJECT_LINE" | grep -q "ST = Baden-Wuerttenberg" && \
        echo "$SUBJECT_LINE" | grep -q "L = Friedrichshafen" && \
        echo "$SUBJECT_LINE" | grep -q "O = \"Secure DMZ Providers \"" && \
        echo "$SUBJECT_LINE" | grep -q "OU = Waf-certificate" && \
        echo "$SUBJECT_LINE" | grep -q "CN = David" && \
        echo "$SUBJECT_LINE" | grep -q "emailAddress = seitz.david-it23@it.dhbw-ravensburg.de"
    )
    CHECK_RESULT=$? # Speichert den Exit-Code des obigen Blocks

    if [ $CHECK_RESULT -eq 0 ]; then
         echo -e "${GREEN}ERFOLG${NC}: Zertifikat ist self-signed UND alle benutzerdefinierten Felder sind korrekt."
    else
         echo -e "${RED}FEHLER${NC}: Zertifikat ist self-signed, aber die Felder stimmen nicht."
         echo "Gefunden: $SUBJECT_LINE"
         TEST_FAILED=1
    fi
else
    echo -e "${RED}FEHLER${NC}: Zertifikat ist NICHT self-signed oder konnte nicht gelesen werden."
    TEST_FAILED=1
fi

# --- Test 6: HTTP zu HTTPS Umleitungs-Test ---
echo -n "Test 6: HTTP-Anfragen werden auf HTTPS umgeleitet ... "

# Führe wget auf HTTP aus, erwarte 301
# -S --spider: Zeige Server-Antwort-Header, lade nichts herunter
# 2>&1: Leite stderr (wo wget's Header-Infos sind) auf stdout um
HTTP_URL="http://${WAF_IP}/"
EXPECTED_LOCATION="https://${WAF_IP}/"

WGET_OUTPUT=$(docker exec $ATTACKER_CONTAINER wget -S --spider --max-redirect=0 "$HTTP_URL" 2>&1)
# 1. Prüfen, ob ein 301 Redirect gesendet wurde
# (Wir benutzen 'grep -c' um die Anzahl der Treffer zu zählen)
CHECK_301=$(echo "$WGET_OUTPUT" | grep -c "HTTP/1.1 301 Moved Permanently")

# 2. Prüfen, ob das Umleitungs-Ziel exakt HTTPS ist
CHECK_LOCATION=$(echo "$WGET_OUTPUT" | grep -c "Location: ${EXPECTED_LOCATION}")

if [ "$CHECK_301" -eq 1 ] && [ "$CHECK_LOCATION" -eq 2 ]; then # Check_Location gibt 2 zurück wegen doppeltem Header-Ausdruck
    echo -e "${GREEN}ERFOLG${NC}: HTTP leitet korrekt auf HTTPS (301) um."
else
    echo -e "${RED}FEHLER${NC}: HTTP-Umleitung ist fehlerhaft (301 oder Location-Header stimmt nicht)."
    echo "DEBUG-Output: $WGET_OUTPUT" # Zeige den Output im Fehlerfall
    TEST_FAILED=1
fi

echo "=== WAF/Proxy-Tests abgeschlossen ==="
exit $TEST_FAILED