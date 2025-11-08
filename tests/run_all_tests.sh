#!/bin/bash

# ==========================================================
# === Master-Test-Suite für SUN-DMZ-Lab (Dynamisch) ===
#
# Dieses Skript führt automatisch alle Skripte im selben
# Verzeichnis aus, die mit 'test_' beginnen und auf '.sh'
# enden.
# ==========================================================

# --- Konfiguration ---
# Verzeichnis, in dem dieses Skript liegt
TEST_DIR=$(dirname "$0")
# Ein Container, der immer laufen muss (z.B. der attacker)
REQUIRED_CONTAINER="clab-sun_dmz-attacker"
# Der Dateiname dieses Master-Skripts, um sich selbst zu ignorieren
MASTER_SCRIPT_NAME=$(basename "$0")

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

echo -e "${BLUE}=== Starte Master-Test-Suite ===${NC}"

# 1. Prüfen, ob das Lab läuft
echo -n "Prüfe, ob Lab '$REQUIRED_CONTAINER' läuft ... "
if ! docker ps -f "name=$REQUIRED_CONTAINER" --format '{{.Names}}' | grep -q "$REQUIRED_CONTAINER"; then
    echo -e "${RED}FEHLER${NC}"
    echo "Das Containerlab scheint nicht zu laufen."
    echo -e "Bitte starten Sie es zuerst mit: ${GREEN}containerlab deploy -t topology.yaml${NC}"
    exit 1
fi
echo -e "${GREEN}OK${NC}"
echo "----------------------------------------"

# 2. Dynamisch alle Test-Skripte finden und ausführen
OVERALL_STATUS=0
# Finde alle Skripte im TEST_DIR, die mit 'test_' beginnen und auf '.sh' enden
TEST_SCRIPTS=($(find "$TEST_DIR" -maxdepth 1 -name "test_*.sh" -print))

if [ ${#TEST_SCRIPTS[@]} -eq 0 ]; then
    echo -e "${RED}FEHLER: Keine Test-Skripte (test_*.sh) im Verzeichnis '$TEST_DIR' gefunden.${NC}"
    exit 1
fi

echo "Folgende Test-Skripte werden ausgeführt:"
for script_path in "${TEST_SCRIPTS[@]}"; do
    echo "  -> $(basename "$script_path")"
done
echo "----------------------------------------"

# Iteriere durch alle gefundenen Skripte
for test_script in "${TEST_SCRIPTS[@]}"; do
    TEST_NAME=$(basename "$test_script")

    echo -e "${BLUE}Starte Test: $TEST_NAME${NC}"
    
    # Führe das gefundene Test-Skript aus
    bash "$test_script"
    STATUS=$?
    
    if [ $STATUS -eq 0 ]; then
        echo -e "${GREEN}Status $TEST_NAME: ERFOLGREICH${NC}"
    else
        echo -e "${RED}Status $TEST_NAME: FEHLGESCHLAGEN${NC}"
        OVERALL_STATUS=1 # Markiert, dass min. ein Test fehlgeschlagen ist
    fi
    echo "----------------------------------------"
done

# 3. Zusammenfassung
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}=== Alle Tests erfolgreich bestanden! ===${NC}"
    exit 0
else
    echo -e "${RED}=== Mindestens ein Test ist fehlgeschlagen! ===${NC}"
    exit 1
fi