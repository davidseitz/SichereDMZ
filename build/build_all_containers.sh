#!/bin/bash

# =================================================================
# === Intelligenter Docker-Build-Prozess (Alles-in-Einem) ===
#
# Sucht dynamisch nach Dockerfiles und baut sie nur,
# wenn sie neuer als das existierende Image sind.
#
# ERWARTETE STRUKTUR:
# dockerfiles/
# └── attacker/
#     └── Dockerfile.attacker
# └── web/
#     └── Dockerfile.web
#
# NAMENS-KONVENTION:
# Dockerfile.<name> -> wird zu Image-Tag <name>-image
# =================================================================

# --- Konfiguration ---
BASE_SEARCH_DIR="dockerfiles"

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

echo -e "${BLUE}=== Starte intelligenten Docker-Build-Prozess ===${NC}"

cd $BASE_SEARCH_DIR || { echo -e "${RED}Fehler: Konnte nicht ins Basisverzeichnis wechseln.${NC}"; exit 1; }
echo "Suche nach Dockerfiles in '$PWD'..."


# Stoppt bei dem ersten Fehler
set -e
BUILD_COUNT=0
SKIP_COUNT=0

# Finde alle Dockerfiles, die der Konvention entsprechen (z.B. Dockerfile.attacker)
# -print0 und read -d '' sorgen dafür, dass auch Namen mit Leerzeichen funktionieren
#
# KORREKTUR: Prozesssubstitution (< <(...) anstelle von Pipe)
#
while IFS= read -r -d '' DOCKERFILE_PATH; do

    # --- 1. Variablen dynamisch ableiten ---
    DOCKERFILE_DIR=$(dirname "$DOCKERFILE_PATH")
    DOCKERFILE_BASENAME=$(basename "$DOCKERFILE_PATH")

    # Extrahiere den Namen aus "Dockerfile.attacker" -> "attacker"
    # Shell-Parameter-Expansion: Entfernt "Dockerfile." vom Anfang
    SERVICE_NAME="${DOCKERFILE_BASENAME#Dockerfile.}" 
    
    # Baue den Image-Namen "attacker" -> "attacker-image"
    IMAGE_NAME="${SERVICE_NAME}-image"

    echo -e "\n--- Verarbeite Service: ${BLUE}$SERVICE_NAME${NC} ---"
    echo "  Dockerfile: $DOCKERFILE_PATH"
    echo "  Kontext-Dir: $DOCKERFILE_DIR"
    echo "  Image-Name: $IMAGE_NAME"

   # --- 2. Build-Logik (aus deinem Skript kopiert) ---
    echo -e "${BLUE}Prüfe Status des Images ('$IMAGE_NAME')...${NC}"
    
    # KORREKTUR: Hänge "|| true" an, um set -e zu befriedigen, 
    # falls das Image nicht existiert.
    IMAGE_TIMESTAMP_STR=$(docker image inspect -f '{{.Created}}' $IMAGE_NAME 2>/dev/null || true)

    if [ -z "$IMAGE_TIMESTAMP_STR" ]; then
        echo "Image nicht gefunden. Build wird gestartet."
    else
        # date -r (für Linux) holt den Timestamp der Datei
        IMAGE_TIMESTAMP=$(date -d "$IMAGE_TIMESTAMP_STR" +%s)
        DOCKERFILE_TIMESTAMP=$(date -r "$DOCKERFILE_PATH" +%s)
        
        if [ $DOCKERFILE_TIMESTAMP -gt $IMAGE_TIMESTAMP ]; then
            echo "Dockerfile ist neuer als das existierende Image. Neubau wird gestartet."
        else
            echo -e "${GREEN}Image ist bereits vorhanden und aktuell. Build wird übersprungen.${NC}"
            SKIP_COUNT=$((SKIP_COUNT + 1))
            continue # Springe zum nächsten Dockerfile in der 'find'-Schleife
        fi
    fi

    # --- 3. Build-Ausführung ---
    echo -e "${BLUE}Starte Image-Build aus '$DOCKERFILE_DIR'...${NC}"
    docker image rm $IMAGE_NAME > /dev/null 2>&1 || true
    
    # Benötigt jetzt KEIN "< /dev/null" mehr
    docker build -t $IMAGE_NAME -f $DOCKERFILE_PATH $DOCKERFILE_DIR 

    if [ $? -ne 0 ]; then
        echo -e "${RED}Fehler beim Bauen des Images '$IMAGE_NAME'. Abbruch.${NC}"
        exit 1 # Der 'set -e' Befehl oben sollte dies bereits tun, aber zur Sicherheit
    fi
    
    echo -e "${GREEN}Image '$IMAGE_NAME' erfolgreich gebaut.${NC}"
    BUILD_COUNT=$((BUILD_COUNT + 1))

done < <(find -type f -name "Dockerfile.*" -print0) # <-- KORREKTUR: Pipe von 'find' wird hier angehängt

echo -e "\n${GREEN}=== Alle Docker-Builds abgeschlossen ===${NC}"
echo -e "  ${GREEN}Gebaut/Aktualisiert:${NC} $BUILD_COUNT"
echo -e "  ${GREEN}Übersprungen (aktuell):${NC} $SKIP_COUNT"