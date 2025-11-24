#!/bin/bash

# =================================================================
# === Intelligenter Docker-Build-Prozess (ALLES-IN-EINEM, PARALLEL) ===
#
# Sucht dynamisch nach Dockerfiles und baut sie parallel.
#
# NAMENS-KONVENTION:
# Dockerfile.<name> -> wird zu Image-Tag <name>-image
# =================================================================

# --- Konfiguration ---
BASE_SEARCH_DIR="dockerfiles"
# Anzahl der parallelen Builds (Standard: Anzahl der CPU-Kerne)
MAX_JOBS=$(nproc) 
LOG_DIR="build/build_logs"

# --- Farben ---
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

echo -e "${BLUE}=== Starte intelligenten Parallelen-Build-Prozess ===${NC}"
echo "Dies kann einige Minuten dauern..."
echo "Maximale parallele Jobs: $MAX_JOBS"

# Erstelle Log-Verzeichnis
mkdir -p "$LOG_DIR"
echo "Log-Dateien werden in '$LOG_DIR' gespeichert."

# --- WICHTIG: Wechsle in das Projekt-Hauptverzeichnis ---
# (Dorthin, wo das 'dockerfiles'-Verzeichnis liegt)
cd "$(dirname "$0")/.." || exit 1
echo "Wechsle in das Projekt-Hauptverzeichnis: $PWD"

# Wechsle in das Such-Verzeichnis
cd $BASE_SEARCH_DIR || { echo -e "${RED}Fehler: Konnte nicht ins Basisverzeichnis wechseln.${NC}"; exit 1; }
echo "Suche nach Dockerfiles in '$PWD'..."

JOB_COUNT=0
FAILURES=0

# Wir definieren die Build-Logik als Funktion
run_build_job() {
    DOCKERFILE_PATH=$1
    
    # set -e *innerhalb* der Sub-Shell. 
    set -e 

    # --- 1. Variablen dynamisch ableiten ---
    DOCKERFILE_DIR=$(dirname "$DOCKERFILE_PATH")
    DOCKERFILE_BASENAME=$(basename "$DOCKERFILE_PATH")
    SERVICE_NAME="${DOCKERFILE_BASENAME#Dockerfile.}" 
    IMAGE_NAME="${SERVICE_NAME}-image"

    echo "--- Verarbeite Service: $SERVICE_NAME ---"
    echo "  Dockerfile: $DOCKERFILE_PATH"
    echo "  Kontext-Dir: $DOCKERFILE_DIR"
    echo "  Image-Name: $IMAGE_NAME"

    # --- 2. Build-Logik ---
    echo "Prüfe Status des Images ('$IMAGE_NAME')..."
    
    # || true verhindert, dass set -e auslöst, wenn das Image nicht existiert
    IMAGE_TIMESTAMP_STR=$(docker image inspect -f '{{.Created}}' $IMAGE_NAME 2>/dev/null || true)

    if [ -z "$IMAGE_TIMESTAMP_STR" ]; then
        echo "Image nicht gefunden. Build wird gestartet."
    else
        IMAGE_TIMESTAMP=$(date -d "$IMAGE_TIMESTAMP_STR" +%s)
        
        # --- ÄNDERUNG HIER ---
        # Anstatt nur das Dockerfile zu prüfen, suchen wir die neuste Datei im gesamten Verzeichnis.
        # find: alle Dateien | stat: Timestamp holen | sort: absteigend | head: nur die neuste
        LATEST_CONTEXT_TIMESTAMP=$(find "$DOCKERFILE_DIR" -type f -exec stat -c %Y {} + | sort -nr | head -n1)

        # Fallback, falls Verzeichnis leer (sollte nicht passieren, da Dockerfile existiert)
        if [ -z "$LATEST_CONTEXT_TIMESTAMP" ]; then LATEST_CONTEXT_TIMESTAMP=0; fi
        
        echo "Image TS:   $IMAGE_TIMESTAMP"
        echo "Context TS: $LATEST_CONTEXT_TIMESTAMP"

        if [ "$LATEST_CONTEXT_TIMESTAMP" -gt "$IMAGE_TIMESTAMP" ]; then
            echo "Änderungen im Verzeichnis erkannt (neuer als Image). Neubau wird gestartet."
        else
            echo "Image ist bereits vorhanden und aktuell (Kontext unverändert). Build wird übersprungen."
            exit 0 # Job erfolgreich beendet (übersprungen)
        fi
    fi

    # --- 3. Build-Ausführung ---
    echo "Starte Image-Build aus '$DOCKERFILE_DIR'..."
    docker image rm $IMAGE_NAME > /dev/null 2>&1 || true
    
    KEY_FILE_PATH="../sshkey/sshkey.pub"

    # Der eigentliche Build-Befehl
    docker build \
        --build-arg="SSH_KEY_PUB=$(cat "$KEY_FILE_PATH")" \
        -t "$IMAGE_NAME" \
        -f "$DOCKERFILE_PATH" \
        "$DOCKERFILE_DIR"

    echo "Image '$IMAGE_NAME' erfolgreich gebaut."
}


# --- HAUPTSCHLEIFE: Job-Verwaltung ---

while IFS= read -r -d '' DOCKERFILE_PATH; do

    # --- Job-Pool-Verwaltung ---
    while (( $(jobs -p | wc -l) >= MAX_JOBS )); do
        sleep 1
    done

    # --- Service-Namen für das Log holen ---
    SERVICE_NAME=$(basename "$DOCKERFILE_PATH")
    SERVICE_NAME="${SERVICE_NAME#Dockerfile.}"
    LOG_FILE="../$LOG_DIR/${SERVICE_NAME}.log" 

    echo -e "${BLUE}Starte Build-Job für: $SERVICE_NAME${NC} (Log: $LOG_FILE)"

    # --- Starte den Job im Hintergrund ---
    (
        run_build_job "$DOCKERFILE_PATH"
    ) > "$LOG_FILE" 2>&1 &

    JOB_COUNT=$((JOB_COUNT + 1))

done < <(find -type f -name "Dockerfile.*" -print0)

# --- Aufräumen ---
echo -e "\n${BLUE}Alle Build-Jobs gestartet ($JOB_COUNT). Warte auf Fertigstellung...${NC}"

wait

echo -e "${GREEN}=== Alle Docker-Builds abgeschlossen ===${NC}"

# --- Fehler-Zusammenfassung ---
echo "Prüfe Logs auf Fehler..."
for logfile in ../$LOG_DIR/*.log; do
    # Check auf Erfolg oder Skip
    if ! tail -n 5 "$logfile" | grep -q -E "erfolgreich gebaut|übersprungen"; then
        SERVICE_NAME=$(basename "$logfile" .log)
        echo -e "${RED}FEHLER im Build für: $SERVICE_NAME${NC} (Siehe $logfile)"
        FAILURES=$((FAILURES + 1))
    fi
done

if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}Alle Builds erfolgreich (oder übersprungen).${NC}"
else
    echo -e "${RED}$FAILURES Build(s) sind fehlgeschlagen.${NC}"
    exit 1
fi