#!/bin/bash

# ---
# Host-based ZAP Vulnerability Scan Script
# ---
# This script executes a ZAP Baseline Scan from within the attacker container
# and copies the HTML report back to the host.

# --- CONFIGURATION ---
CONTAINER_NAME="clab-security_lab-attacker_3"
TARGET_URL="https://10.10.10.3"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
REPORT_FILENAME="zap_full_report_${TIMESTAMP}.html"

# Path inside the container (ZAP defaults to writing in /zap/wrk/)
CONTAINER_REPORT_PATH="/zap/wrk/${REPORT_FILENAME}"
    
# Path on your host machine
HOST_REPORT_DIR="./attacks/reports"
HOST_REPORT_PATH="${HOST_REPORT_DIR}/${REPORT_FILENAME}"
# ---

echo "--- Preparing ZAP Scan ---"
echo "Attacker Container: $CONTAINER_NAME"
echo "Target URL:         $TARGET_URL"
echo "Report File:        $REPORT_FILENAME"
echo ""

# --- STEP 1: PREPARATION ---
echo "[Step 1/3] Preparing directories..."
mkdir -p "$HOST_REPORT_DIR"

# Check if container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "ERROR: Container '$CONTAINER_NAME' is not running."
    exit 1
fi
echo "Ready."
echo ""

# --- STEP 2: RUN THE SCAN ---
echo "[Step 2/3] Running full ZAP Scan. This may take 1-5 minutes..."

# Command Breakdown:
# zap-full-scan.py : The full scan script
# -t : Target URL
# -r : Report filename (relative to /zap/wrk/)
# -I : Ignore warning on 404/500 errors (optional, keeps scan running)
docker exec -i "$CONTAINER_NAME" \
    zap-full-scan.py \
    -t "$TARGET_URL" \
    -r "$REPORT_FILENAME"
    
# Note: ZAP returns exit codes 1 (Fail) or 2 (Warn) if issues are found.
# We don't want the script to exit on these, as finding issues is the goal.
ZAP_EXIT_CODE=$?

if [ $ZAP_EXIT_CODE -eq 0 ]; then
    echo "Scan Clean (No issues found)."
elif [ $ZAP_EXIT_CODE -eq 1 ] || [ $ZAP_EXIT_CODE -eq 2 ]; then
    echo "Scan Finished (Issues found)."
else
    echo "ERROR: ZAP failed to run (Exit Code: $ZAP_EXIT_CODE)."
    exit 1
fi
echo ""

# --- STEP 3: COPY REPORT TO HOST ---
echo "[Step 3/3] Copying report from container to host..."

docker cp "${CONTAINER_NAME}:${CONTAINER_REPORT_PATH}" "$HOST_REPORT_PATH"

if [ $? -eq 0 ]; then
    echo "---"
    echo "SUCCESS: Scan complete!"
    echo "Report saved to: $HOST_REPORT_PATH"
    echo "---"
else
    echo "ERROR: Failed to copy report from container."
    exit 1
fi