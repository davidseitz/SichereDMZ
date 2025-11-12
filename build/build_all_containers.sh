#!/bin/bash

# ==========================================================
# === Orchestrator-Skript für alle Docker-Builds ===
#
# Sucht und führt alle Skripte im './build/' Verzeichnis aus.
# ==========================================================

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

# --- WICHTIG: Wechsle in das Projekt-Hauptverzeichnis ---
# (Eins über dem Ort, an dem dieses Skript liegt)
cd "$(dirname "$0")/.." || exit 1

BUILD_DIR="./build"
TEST_FAILED=0

# --- SELBST-AUSFÜHRUNGS-SCHUTZ ---
# Hole den Dateinamen dieses Skripts
ORCHESTRATOR_NAME=$(basename "$0")

# Stoppt bei dem ersten Fehler
set -e

echo -e "${BLUE}=== Starte intelligenten Docker-Build-Prozess ===${NC}"
echo "(Orchestrator '$ORCHESTRATOR_NAME' wird ausgeführt und sich selbst überspringen)"

if [ ! -d "$BUILD_DIR" ]; then
    echo -e "${RED}Build-Verzeichnis '$BUILD_DIR' nicht gefunden!${NC}"
    exit 1
fi

# Finde alle ausführbaren Skripte im build-Verzeichnis
for build_script in $(find $BUILD_DIR -name "*.sh" -executable); do

    # --- HIER IST DER SCHUTZ ---
    SCRIPT_FILENAME=$(basename "$build_script")
    if [ "$SCRIPT_FILENAME" == "$ORCHESTRATOR_NAME" ]; then
        continue # Überspringe dieses Skript (sich selbst)
    fi
    # --- ENDE DES SCHUTZES ---

    echo -e "\n--- Führe Build-Skript aus: $build_script ---"
    bash $build_script
    if [ $? -ne 0 ]; then
        echo -e "${RED}Build-Skript $build_script ist fehlgeschlagen!${NC}"
        exit 1
    fi
done

echo -e "\n${GREEN}=== Alle Docker-Builds erfolgreich (oder bereits aktuell) ===${NC}"