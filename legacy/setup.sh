#!/bin/bash

# ==========================================================
# === Master-Setup-Skript für das SUN DMZ-Projekt (V21) ===
#
# Führt alle Schritte aus:
# 1. Baut das WAF-Docker-Image (intelligent).
# 2. Startet/Stoppt/Testet das Containerlab.
#
# ./setup.sh [start|stop|restart|test]
# ==========================================================

# --- Konfiguration ---
TOPOLOGY_FILE="topology.yaml"
WAF_IMAGE_NAME="sun-waf-image"
WAF_DOCKERFILE_PATH="./waf_dockerfile/Dockerfile"
WAF_DOCKERFILE_DIR="./waf_dockerfile"
TEST_SCRIPT_PATH="./tests/run_all_tests.sh"

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

# --- 1. Hilfsfunktionen ---

# Funktion, die den Build IMMER ausführt (wird nur intern benötigt)
function build_waf {
    echo -e "${BLUE}Starte WAF-Image-Build aus '$WAF_DOCKERFILE_DIR'...${NC}"
    echo "Dies kann einige Minuten dauern."
    
    # Altes Image löschen, um "dangling" Images zu vermeiden
    docker image rm $WAF_IMAGE_NAME > /dev/null 2>&1 || true
    
    # Führe den Docker-Build aus (ohne sudo)
    docker build -t $WAF_IMAGE_NAME $WAF_DOCKERFILE_DIR
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Fehler beim Bauen des WAF-Images. Abbruch.${NC}"
        exit 1
    fi
    echo -e "${GREEN}WAF-Image erfolgreich gebaut.${NC}"
}

# Funktion, die prüft, ob ein Build NÖTIG ist
function check_and_build_waf {
    echo -e "${BLUE}Prüfe Status des WAF-Images ('$WAF_IMAGE_NAME')...${NC}"
    
    if [ ! -f "$WAF_DOCKERFILE_PATH" ]; then
        echo -e "${RED}Dockerfile nicht gefunden unter $WAF_DOCKERFILE_PATH. Abbruch.${NC}"
        exit 1
    fi

    # Prüfen, ob das Image überhaupt existiert
    IMAGE_TIMESTAMP_STR=$(docker image inspect -f '{{.Created}}' $WAF_IMAGE_NAME 2>/dev/null)
    
    if [ -z "$IMAGE_TIMESTAMP_STR" ]; then
        echo "Image nicht gefunden. Build wird gestartet."
        build_waf
    else
        # Prüfen, ob das Dockerfile NEUER als das Image ist
        IMAGE_TIMESTAMP=$(date -d "$IMAGE_TIMESTAMP_STR" +%s)
        DOCKERFILE_TIMESTAMP=$(date -r "$WAF_DOCKERFILE_PATH" +%s)
        
        if [ $DOCKERFILE_TIMESTAMP -gt $IMAGE_TIMESTAMP ]; then
            echo "Dockerfile ist neuer als das existierende Image. Neubau wird gestartet."
            build_waf
        else
            echo -e "${GREEN}WAF-Image ist bereits vorhanden und aktuell. Build wird übersprungen.${NC}"
        fi
    fi
}

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
        check_and_build_waf # Ruft die intelligente Prüfung auf
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
        check_and_build_waf # KORRIGIERT: Ruft die intelligente Prüfung auf
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