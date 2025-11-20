#!/bin/bash

# --- Konfiguration ---
BASTION_CONTAINER="clab-security_lab-bastion" # <-- WICHTIG: Bitte anpassen!
ADMIN_CONTAINER="clab-security_lab-admin"     # Behalten für Test 3 
WAF_MGMT_IP="10.10.60.2"                      # The WAF's management IP 
PRIVATE_KEY_PATH="/home/admin/.ssh/id_rsa"          # 
SSH_PORT="3025"                               # 

# --- Farben für die Ausgabe ---
GREEN="\033[0;32m" 
RED="\033[0;31m" 
NC="\033[0m" # No Color 

echo "=== Starte automatisierte Tests für SSH-Härtung (Port $SSH_PORT) ===" 
TEST_FAILED=0 

# --- Test 1: Positiver Härtungs-Test (Key-Auth vom Bastion-Host) ---
# Wir prüfen, ob der Login VOM BASTION-HOST mit Key funktioniert.
echo -n "Test 1: (BASTION) Zugriff mit privatem SSH-Key ... "

# -p = Port, -i = identity, -o StrictHostKeyChecking=no
# Test wird jetzt vom BASTION_CONTAINER ausgeführt
OUTPUT=$(docker exec $BASTION_CONTAINER ssh -p $SSH_PORT -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=5 admin@$WAF_MGMT_IP "echo SSH_KEY_SUCCESS" 2>/dev/null) 

if [ $? -eq 0 ] && [[ "$OUTPUT" == *"SSH_KEY_SUCCESS"* ]]; then 
    echo -e "${GREEN}ERFOLG${NC}: SSH-Login vom Bastion-Host war erfolgreich." 
else
    echo -e "${RED}FEHLER${NC}: SSH-Login vom Bastion-Host fehlgeschlagen. (Ist '$BASTION_CONTAINER' der richtige Name?)" 
    TEST_FAILED=1 
fi

# --- Test 2: Negativer Härtungs-Test (Passwort-Auth vom Bastion-Host) ---
# Wir prüfen, ob der Login VOM BASTION-HOST MIT Passwort fehlschlägt.
echo -n "Test 2: (BASTION) Zugriff mit Passwort-Authentifizierung ... " 

# Test wird jetzt vom BASTION_CONTAINER ausgeführt
docker exec $BASTION_CONTAINER ssh -p $SSH_PORT -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=3 admin@$WAF_MGMT_IP "echo SSH_PASS_FAIL" > /dev/null 2>&1 

if [ $? -ne 0 ]; then 
    echo -e "${GREEN}ERFOLG${NC}: Server hat Passwort-Authentifizierung (vom Bastion) wie erwartet abgewiesen." 
else
    echo -e "${RED}FEHLER${NC}: Passwort-Authentifizierung war erfolgreich. Härtung defekt!" 
    TEST_FAILED=1 
fi

# --- NEU: Test 3: Negativer Härtungs-Test (Direkt-Zugriff vom Admin-Host) ---
# Wir prüfen, ob der Login vom ADMIN-HOST (falsche IP) fehlschlägt.
echo -n "Test 3: (ADMIN)   Direkt-Zugriff von Admin-Host ... "

# Dieser Test sollte fehlschlagen, da die sshd_config "AllowUsers admin@10.10.30.3" vorschreibt.
# Wir verwenden den Key, der fehlschlagen MUSS, da die Quell-IP falsch ist.
docker exec $ADMIN_CONTAINER ssh -p $SSH_PORT -i $PRIVATE_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=5 admin@$WAF_MGMT_IP "echo SSH_ADMIN_FAIL" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${GREEN}ERFOLG${NC}: Server hat Verbindung von nicht autorisierter IP (Admin) wie erwartet abgewiesen."
else
    echo -e "${RED}FEHLER${NC}: Direkt-Zugriff vom Admin-Host war erfolgreich. Die 'AllowUsers' Regel ist defekt!"
    TEST_FAILED=1
fi


echo "=== Tests abgeschlossen ===" 
exit $TEST_FAILED