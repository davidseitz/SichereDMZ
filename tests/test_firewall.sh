#!/bin/bash

# === Automatisierter Firewall-Test (Netzwerksegmentierung) ===
#
# Dieses Skript prüft, ob der Webserver (10.10.1.100)
# von Zonen blockiert wird, die NICHT die WAF sind.
#
# WICHTIG: Dieses Skript wird anfangs FEHLSCHLAGEN (rot).
# Das ist ERWARTET, da wir die iptables-Firewall-Regeln
# auf den Routern noch nicht konfiguriert haben!
# Sobald die Firewall-Regeln (Phase 4) aktiv sind,
# sollte dieses Skript ERFOLGREICH (grün) sein.
# ----------------------------------------------------

# --- Konfiguration ---
ATTACKER_CONTAINER="clab-sun_dmz-attacker"
CLIENT_CONTAINER="clab-sun_dmz-client"
WEB_SERVER_IP="10.10.1.100"
WEB_SERVER_PORT="80" # Wir testen Port 80

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo "=== Starte automatisierte Firewall-Segmentierungs-Tests ==="
TEST_FAILED=0

# --- Test 1: Internet -> Webserver (Sollte blockiert werden) ---
echo -n "Test 1: 'attacker' (Internet) -> 'web' (10.10.1.100) ... "
# nc -z -w 2 = Netcat, scanne Port (-z), 2s Timeout (-w 2)
docker exec $ATTACKER_CONTAINER nc -z -w 2 $WEB_SERVER_IP $WEB_SERVER_PORT > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: Verbindung von 'attacker' ist wie erwartet blockiert."
else
    echo -e "${RED}FEHLER${NC}: 'attacker' KANN auf den Webserver zugreifen! Firewall-Lücke!"
    TEST_FAILED=1
fi

# --- Test 2: Client-Netz -> Webserver (Sollte blockiert werden) ---
# (Annahme: Clients sollen NUR auf die WAF 10.10.1.10, nicht auf 10.10.1.100)
echo -n "Test 2: 'client' (Intern) -> 'web' (10.10.1.100) ... "
docker exec $CLIENT_CONTAINER nc -z -w 2 $WEB_SERVER_IP $WEB_SERVER_PORT > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: Verbindung von 'client' ist wie erwartet blockiert."
else
    echo -e "${RED}FEHLER${NC}: 'client' KANN auf den Webserver zugreifen! Interne Segmentierung fehlt!"
    TEST_FAILED=1
fi

echo "=== Firewall-Tests abgeschlossen ==="
exit $TEST_FAILED