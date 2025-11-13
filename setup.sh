#!/bin/bash

# ==========================================================
# === Master-Setup-Skript für das SUN DMZ-Projekt (V21) ===
#
# Führt alle Schritte aus:
# 1. Baut die Docker-Images.
# 2. Startet/Stoppt/Testet das Containerlab.
#
# ./setup.sh [start|stop|restart|test]
# ==========================================================

# --- Konfiguration ---
TOPOLOGY_FILE="topology.yaml"
TEST_SCRIPT_PATH="./tests/run_all_tests.sh"
BUILD_SCRIPT_PATH="./build/build_all_containers.sh"

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

# Funktion zum Starten des Labs
function deploy_lab {
    echo -e "${BLUE}Deploye Containerlab-Topologie ($TOPOLOGY_FILE)...${NC}"
    # Ruft containerlab auf
    containerlab deploy -t $TOPOLOGY_FILE
}

# Funktion zum Zerstören des Labs
function destroy_lab {
    echo -e "${BLUE}Zerstöre Containerlab-Topologie ($TOPOLOGY_FILE)...${NC}"
    # Ruft containerlab aufl
    containerlab destroy -t $TOPOLOGY_FILE
}

# Funktion zum Ausführen der Tests
function run_tests {
    echo -e "${BLUE}Führe automatisierte Test-Suite aus...${NC}"
    
    if [ ! -f "$TEST_SCRIPT_PATH" ]; then
        echo -e "${RED}Test-Skript '$TEST_SCRIPT_PATH' nicht gefunden!${NC}"
        exit 1
    fi
    
    # Führt das Skript als aktueller Benutzer aus
    bash $TEST_SCRIPT_PATH
}

# --- 2. Hauptlogik ---

cd "$(dirname "$0")"

if [ "$#" -eq 0 ]; then
    echo "Fehlendes Argument."
    echo "Nutzung: $0 [start|stop|restart|test]"
    exit 1
fi

case "$1" in
    start)
        echo "=== Starte Lab ==="
        if [ ! -f "$BUILD_SCRIPT_PATH" ]; then
        echo -e "${RED}Build-Skript '$BUILD_SCRIPT_PATH' nicht gefunden!${NC}"
        exit 1
        fi
        
        # Führt das Skript als aktueller Benutzer aus bircht ab falls built fehlschlägt
        if ! bash $BUILD_SCRIPT_PATH; then
            echo -e "${RED}Build-Skript fehlgeschlagen! Abbruch.${NC}"
            exit 1
        fi

        deploy_lab
        echo -e "${GREEN}=== Lab gestartet ===${NC}"
        ;;
        
    stop)
        echo "=== Stoppe Lab ==="
        destroy_lab
        echo -e "${GREEN}=== Lab gestoppt ===${NC}"
        ;;
        
    restart)
        echo "=== Starte Lab neu (Intelligenter WAF-Build) ==="
        destroy_lab
        
        if [ ! -f "$BUILD_SCRIPT_PATH" ]; then
        echo -e "${RED}Build-Skript '$BUILD_SCRIPT_PATH' nicht gefunden!${NC}"
        exit 1
        fi
        
        # Führt das Skript als aktueller Benutzer aus und bricht ab falls build fehlschlägt
        if ! bash $BUILD_SCRIPT_PATH; then
            echo -e "${RED}Build-Skript fehlgeschlagen! Abbruch.${NC}"
            exit 1
        fi

        deploy_lab
        echo -e "${GREEN}=== Lab neu gestartet ===${NC}"
        ;;
        
    test)
        echo "=== Starte Tests ==="
        run_tests
        ;;
        
    *)
        echo -e "${RED}Unbekanntes Argument: $1${NC}"
        echo "Nutzung: $0 [start|stop|restart|test]"
        exit 1
        ;;
esac