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

# # 1. Install Python requests in the container (if missing)
# echo -e "${BLUE}[SETUP] Installing python requests library in attacker container...${NC}"
# docker exec $ATTACKER_CONTAINER pip3 install requests --break-system-packages > /dev/null 2>&1

# # 2. Copy the attack script to the container
# echo -e "${BLUE}[SETUP] Copying attack script...${NC}"
# docker cp flood_users.py $ATTACKER_CONTAINER:/flood_users.py

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
docker exec $ATTACKER_CONTAINER python3 /home/attacker/attacks/flood_users.py > /dev/null 2>&1 &
ATTACK_PID=$!

# Give it 2 seconds to ramp up
sleep 2

# 5. Stress Test
measure_latency "During Signup Flood"

# 6. Cleanup
echo -e "\n${BLUE}[CLEANUP] Stopping attack...${NC}"
# Kill the python script inside the container
docker exec $ATTACKER_CONTAINER pkill -f "python3 /flood_users.py"