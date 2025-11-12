#!/bin/bash

# --- Konfiguration ---
ADMIN_CONTAINER="clab-security_lab-admin"
WAF_MGMT_IP="10.10.60.2" # The WAF's management IP from topology.yaml
PRIVATE_KEY_PATH="/root/.ssh/id_rsa"
SSH_PORT="3025" # <-- Port hinzugefügt

# --- Farben für die Ausgabe ---
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo "=== Starte automatisierte Tests für SSH-Härtung (Port $SSH_PORT) ==="
TEST_FAILED=0

# --- Test 1: Positiver Härtungs-Test (Key-Authentifizierung) ---
# Wir prüfen, ob der Login MIT Key funktioniert.
echo -n "Test 1: Zugriff mit privatem SSH-Key ... "

# -p = Port
# -i = identity file (key)
# -o StrictHostKeyChecking=no = "ja" zur "Host-Key-Prüfung"
# "echo SSH_KEY_SUCCESS" = Ein einfacher Befehl, der nur bei Erfolg ausgeführt wird.
OUTPUT=$(docker exec $ADMIN_CONTAINER ssh -p $SSH_PORT -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no root@$WAF_MGMT_IP "echo SSH_KEY_SUCCESS" 2>/dev/null)

if [ $? -eq 0 ] && [[ "$OUTPUT" == *"SSH_KEY_SUCCESS"* ]]; then
    echo -e "${GREEN}ERFOLG${NC}: SSH-Login mit Key-Authentifizierung war erfolgreich."
else
    echo -e "${RED}FEHLER${NC}: SSH-Login mit Key-Authentifizierung fehlgeschlagen."
    TEST_FAILED=1
fi

# --- Test 2: Negativer Härtungs-Test (Passwort-Authentifizierung) ---
# Wir prüfen, ob der Login MIT Passwort fehlschlägt, wie in der Dockerfile konfiguriert.
echo -n "Test 2: Zugriff mit Passwort-Authentifizierung ... "

# -p = Port
# -o PreferredAuthentications=password = Erzwinge Passwort-Versuch
# -o PubkeyAuthentication=no = Deaktiviere Key-Versuch
# -o ConnectTimeout=3 = 3 Sekunden Timeout, falls der Server hängt
docker exec $ADMIN_CONTAINER ssh -p $SSH_PORT -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=3 root@$WAF_MGMT_IP "echo SSH_PASS_FAIL" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: Server hat Passwort-Authentifizierung wie erwartet abgewiesen."
else
    echo -e "${RED}FEHLER${NC}: Passwort-Authentifizierung war erfolgreich. Härtung defekt!"
    TEST_FAILED=1
fi

echo "=== Tests abgeschlossen ==="
exit $TEST_FAILED