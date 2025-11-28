#!/bin/bash

# ---
# Host-based Docker Scan Script (Outside Attacker)
# ---
# Role: Red Team / External Threat
# Scope: Hardcoded Specific Subnets
# ---

# --- CONFIGURATION ---
CONTAINER_NAME="clab-security_lab-attacker_1"

# [!] EDIT THIS LINE: Add all existing subnets here, separated by spaces.
# Example: "10.10.10.0/29 10.10.20.0/24 10.10.30.0/30"
TARGET_SUBNETS="10.10.10.0/16"

#TARGET_SUBNETS="10.10.10.0/29 10.10.20.0/29 10.10.30.0/29 10.10.40.0/29 10.10.50.0/29 10.10.60.0/28"

REPORT_NAME="attacks/reports/dmz_vuln_scan_outside_$(date +%Y-%m-%d_%H-%M).txt"
CONTAINER_REPORT_PATH="/tmp/$(basename "$REPORT_NAME")"
# ---

echo "--- Preparing Scan ---"
echo "Attacker Container: $CONTAINER_NAME"
echo "Target List:        $TARGET_SUBNETS"
echo ""

# --- STEP 1: PREP ---
mkdir -p attacks/reports

# --- STEP 2: RUN THE SCAN ---
echo "[Step 2/3] Running Nmap vulnerability scan on hardcoded targets..."

docker exec -i "$CONTAINER_NAME" mkdir -p /tmp/attacks/reports

# Nmap Flags:
# -sV: Version detection
# --script=vulners: Check CVEs
# We pass $TARGET_SUBNETS without quotes to ensure the list expands correctly
docker exec -i "$CONTAINER_NAME" nmap -sV --script=vulners -oN "$CONTAINER_REPORT_PATH" $TARGET_SUBNETS

if [ $? -ne 0 ]; then
    echo "ERROR: Nmap scan command failed."
    exit 1
fi
echo "Scan finished."
echo ""

# --- STEP 3: COPY REPORT TO HOST ---
echo "[Step 3/3] Copying report from container to host..."
docker cp "${CONTAINER_NAME}:${CONTAINER_REPORT_PATH}" "./$REPORT_NAME"

if [ $? -eq 0 ]; then
    echo "---"
    echo "SUCCESS: Scan complete!"
    echo "Report saved to: ./$REPORT_NAME"
    echo "---"
    docker exec -i "$CONTAINER_NAME" rm "$CONTAINER_REPORT_PATH"
else
    echo "ERROR: Could not copy report file."
fi