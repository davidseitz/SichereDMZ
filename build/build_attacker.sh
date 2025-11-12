#!/bin/bash

# --- Konfiguration ---
IMAGE_NAME="attacker-image"
DOCKERFILE_PATH="./attacker/attacker_dockerfile/Dockerfile"
DOCKERFILE_DIR="./attacker/attacker_dockerfile"

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

echo -e "${BLUE}Prüfe Status des Images ('$IMAGE_NAME')...${NC}"

if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo -e "${RED}Dockerfile nicht gefunden unter $DOCKERFILE_PATH. Abbruch.${NC}"
    exit 1
fi

IMAGE_TIMESTAMP_STR=$(docker image inspect -f '{{.Created}}' $IMAGE_NAME 2>/dev/null)

if [ -z "$IMAGE_TIMESTAMP_STR" ]; then
    echo "Image nicht gefunden. Build wird gestartet."
else
    IMAGE_TIMESTAMP=$(date -d "$IMAGE_TIMESTAMP_STR" +%s)
    DOCKERFILE_TIMESTAMP=$(date -r "$DOCKERFILE_PATH" +%s)
    
    if [ $DOCKERFILE_TIMESTAMP -gt $IMAGE_TIMESTAMP ]; then
        echo "Dockerfile ist neuer als das existierende Image. Neubau wird gestartet."
    else
        echo -e "${GREEN}Image ist bereits vorhanden und aktuell. Build wird übersprungen.${NC}"
        exit 0 # Exit successfully, no build needed
    fi
fi

# --- Build-Logik ---
echo -e "${BLUE}Starte Image-Build aus '$DOCKERFILE_DIR'...${NC}"
docker image rm $IMAGE_NAME > /dev/null 2>&1 || true
docker build -t $IMAGE_NAME $DOCKERFILE_DIR

if [ $? -ne 0 ]; then
    echo -e "${RED}Fehler beim Bauen des Images '$IMAGE_NAME'. Abbruch.${NC}"
    exit 1
fi
echo -e "${GREEN}Image '$IMAGE_NAME' erfolgreich gebaut.${NC}"