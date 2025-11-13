#!/bin/bash

# ---
# Host-based Docker Scan Script
# ---
# This script executes a vulnerability scan from within an existing
# attacker container ("${CONTAINER_NAME}") and copies the report
# back to the host.

# --- CONFIGURATION ---
CONTAINER_NAME="clab-security_lab-attacker_2"
TARGET_SUBNET="10.10.10.0/25"
REPORT_NAME="attacks/reports/dmz_vuln_scan_inside_$(date +%Y-%m-%d_%H-%M).txt"
# This is the path *inside the container*
CONTAINER_REPORT_PATH="/tmp/$REPORT_NAME"
# ---

echo "--- Preparing Scan ---"
echo "Attacker Container: $CONTAINER_NAME"
echo "Target Subnet:      $TARGET_SUBNET"
echo ""

# # --- STEP 1: UPDATE NMAP SCRIPT DB ---

mkdir -p attacks/reports
# echo "[Step 1/3] Updating Nmap script database in '$CONTAINER_NAME'..."
# # We run this just in case, to get the latest 'vulners' definitions.
# # We use '-i' instead of '-it' for a non-interactive exec.
# docker exec -i "$CONTAINER_NAME" nmap --script-updatedb
# if [ $? -ne 0 ]; then
#     echo "Warning: Nmap DB update failed. Container may lack internet access or nmap."
#     echo "Continuing scan..."
# fi
# echo "Update complete."
# echo ""

# --- STEP 2: RUN THE SCAN ---
echo "[Step 2/3] Running Nmap vulnerability scan. This will take several minutes..."
# -sV: Probe open ports to determine service/version info
# --script=vulners: Run the vulners NSE script to check for known CVEs
# -oN: Output the scan in Normal format to the specified file
docker exec -i "$CONTAINER_NAME" mkdir -p /tmp/attacks/reports
docker exec -i "$CONTAINER_NAME" touch "$CONTAINER_REPORT_PATH"
docker exec -i "$CONTAINER_NAME" nmap -sV --script=vulners -oN "$CONTAINER_REPORT_PATH" "$TARGET_SUBNET"

if [ $? -ne 0 ]; then
    echo "ERROR: Nmap scan command failed."
    echo "Please check that the container '$CONTAINER_NAME' is running and has nmap installed."
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
    # Optional: Clean up the report file inside the container
    docker exec -i "$CONTAINER_NAME" rm "$CONTAINER_REPORT_PATH"
else
    echo "ERROR: Could not copy report file from container."
    echo "You can still access it manually inside the container at:"
    echo "$CONTAINER_NAME:$CONTAINER_REPORT_PATH"
fi