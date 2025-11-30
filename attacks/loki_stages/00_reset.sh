#!/bin/bash

# ==========================================================================
# STAGE 00: Environment Reset
# ==========================================================================
# Restarts the lab environment to ensure a clean SIEM instance.
# Waits for all critical containers to be healthy before proceeding.
# ==========================================================================

set -e

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SETUP_SCRIPT="${PROJECT_ROOT}/setup.sh"

# Containers to verify
SIEM_CONTAINER="clab-security_lab-siem"
WEBSERVER_CONTAINER="clab-security_lab-web_server"

# Timeouts
RESTART_TIMEOUT=180
HEALTH_CHECK_INTERVAL=5

# Loki endpoint
LOKI_HOST="10.10.30.2"
LOKI_PORT="3100"

# --- Colors ---
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
NC="\033[0m"

# --- Functions ---
log_stage() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  STAGE 00: ENVIRONMENT RESET                                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_info() {
    echo -e "[$(date '+%H:%M:%S')] ${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "[$(date '+%H:%M:%S')] ${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "[$(date '+%H:%M:%S')] ${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "[$(date '+%H:%M:%S')] ${RED}[ERROR]${NC} $1"
}

wait_for_container() {
    local container="$1"
    local timeout="$2"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            return 0
        fi
        sleep $HEALTH_CHECK_INTERVAL
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
    done
    return 1
}

wait_for_loki() {
    local timeout="$1"
    local elapsed=0

    log_info "Waiting for Loki to accept connections..."

    while [ $elapsed -lt $timeout ]; do
        # Use docker exec to check from within the network
        if docker exec $WEBSERVER_CONTAINER timeout 2 bash -c "echo > /dev/tcp/${LOKI_HOST}/${LOKI_PORT}" 2>/dev/null; then
            return 0
        fi
        sleep $HEALTH_CHECK_INTERVAL
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
        echo -n "."
    done
    echo ""
    return 1
}

# --- Main ---
main() {
    log_stage

    # Check setup script exists
    if [ ! -f "$SETUP_SCRIPT" ]; then
        log_error "Setup script not found: ${SETUP_SCRIPT}"
        exit 1
    fi

    # Execute restart
    log_info "Executing: ./setup.sh restart"
    log_warning "This will restart the entire lab environment..."
    echo ""

    cd "$PROJECT_ROOT"
    
    # Run the restart
    if ! ./setup.sh restart; then
        log_error "Setup script failed!"
        exit 1
    fi

    echo ""
    log_info "Restart command completed. Verifying containers..."

    # Wait for SIEM container
    log_info "Waiting for SIEM container (${SIEM_CONTAINER})..."
    if wait_for_container "$SIEM_CONTAINER" "$RESTART_TIMEOUT"; then
        log_success "SIEM container is running"
    else
        log_error "SIEM container failed to start within ${RESTART_TIMEOUT}s"
        exit 1
    fi

    # Wait for Web Server container (our attack origin)
    log_info "Waiting for Web Server container (${WEBSERVER_CONTAINER})..."
    if wait_for_container "$WEBSERVER_CONTAINER" "$RESTART_TIMEOUT"; then
        log_success "Web Server container is running"
    else
        log_error "Web Server container failed to start within ${RESTART_TIMEOUT}s"
        exit 1
    fi

    # Wait for Loki to be responsive
    if wait_for_loki 60; then
        log_success "Loki is accepting connections at ${LOKI_HOST}:${LOKI_PORT}"
    else
        log_error "Loki failed to become responsive within 60s"
        exit 1
    fi

    # Brief stabilization delay
    log_info "Allowing 10 seconds for services to stabilize..."
    sleep 10

    echo ""
    log_success "Environment reset complete. Ready for baseline capture."
    echo ""

    exit 0
}

main "$@"
