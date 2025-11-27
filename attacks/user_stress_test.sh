#!/bin/bash

ATTACKER_CONTAINER="clab-security_lab-attacker_1"
# Target for the latency check (Index page)
TARGET_URL="https://10.10.10.3/"
HOST_HEADER="web.sun.dmz"
DURATION=30

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to measure latency
measure_latency() {
    local phase_name="$1"
    local end_time=$((SECONDS + DURATION))
    local total_time=0
    local count=0

    echo -e "${GREEN}>>> Starting measurement: $phase_name (${DURATION}s)${NC}"
    
    while [ $SECONDS -lt $end_time ]; do
        # We use curl with -H "Host: ..." to pass the app.py host check
        resp_time=$(curl -k -H "Host: ${HOST_HEADER}" -o /dev/null -s -w "%{time_total}" --connect-timeout 2 "$TARGET_URL")
        
        if [ ! -z "$resp_time" ] && [ "$resp_time" != "0.000" ]; then
            total_time=$(awk "BEGIN {print $total_time + $resp_time}")
            count=$((count + 1))
        fi
        sleep 1
    done

    if [ $count -gt 0 ]; then
        avg=$(awk "BEGIN {print $total_time / $count}")
        echo -e "${BLUE}RESULT ($phase_name): Average Response Time = ${avg} seconds${NC}"
    else
        echo -e "${BLUE}RESULT ($phase_name): Server Unresponsive${NC}"
    fi
}

# 3. Baseline Test (No Attack)
measure_latency "Baseline (Normal Traffic)"

# 4. Start Attack in Background
echo -e "\n${GREEN}>>> Launching Signup Flood Attack...${NC}"

# UPDATE: Explicitly use the Virtual Environment Python
# This guarantees we have access to cv2, pytesseract, and requests
docker exec $ATTACKER_CONTAINER /opt/venv/bin/python3 /home/attacker/attacks/flood_users.py > /dev/null 2>&1 &

ATTACK_PID=$!

# Allow attack to ramp up
sleep 5

# 5. Stress Test (Under Attack)
measure_latency "Under Attack (DoS)"

# 6. Cleanup
echo -e "\n${BLUE}[CLEANUP] Stopping attack...${NC}"
# We kill the python process inside the container
docker exec $ATTACKER_CONTAINER pkill -f flood_users.py