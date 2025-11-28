#!/bin/bash

# ==========================================================================
# STAGE 01: Baseline Capture
# ==========================================================================
# Captures initial system metrics from the SIEM container before attack.
# Metrics: Memory usage, CPU, Loki data directory size, stream count.
# ==========================================================================

set -e

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIEM_CONTAINER="clab-security_lab-siem"
WEBSERVER_CONTAINER="clab-security_lab-web_server"

# Loki configuration
LOKI_HOST="10.10.30.2"
LOKI_PORT="3100"
LOKI_DATA_DIR="/loki"  # Loki data directory inside container

# Output file for baseline metrics
BASELINE_FILE="${SCRIPT_DIR}/baseline_metrics.txt"

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
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  STAGE 01: BASELINE CAPTURE                                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_info() {
    echo -e "[$(date '+%H:%M:%S')] ${CYAN}[INFO]${NC} $1"
}

log_metric() {
    echo -e "[$(date '+%H:%M:%S')] ${MAGENTA}[METRIC]${NC} $1"
}

log_success() {
    echo -e "[$(date '+%H:%M:%S')] ${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "[$(date '+%H:%M:%S')] ${RED}[ERROR]${NC} $1"
}

get_container_memory() {
    # Get memory usage in bytes from docker stats
    docker stats --no-stream --format "{{.MemUsage}}" "$SIEM_CONTAINER" 2>/dev/null | \
        awk -F'/' '{print $1}' | tr -d ' '
}

get_container_memory_bytes() {
    # Convert memory string (e.g., "125.4MiB") to bytes
    local mem_str=$(get_container_memory)
    local value=$(echo "$mem_str" | grep -oE '[0-9.]+')
    local unit=$(echo "$mem_str" | grep -oE '[A-Za-z]+')
    
    case "$unit" in
        GiB|GB) echo "scale=0; $value * 1073741824 / 1" | bc ;;
        MiB|MB) echo "scale=0; $value * 1048576 / 1" | bc ;;
        KiB|KB) echo "scale=0; $value * 1024 / 1" | bc ;;
        B) echo "$value" ;;
        *) echo "0" ;;
    esac
}

get_container_cpu() {
    docker stats --no-stream --format "{{.CPUPerc}}" "$SIEM_CONTAINER" 2>/dev/null | tr -d '%'
}

get_loki_data_size() {
    # Get size of Loki data directory in bytes
    docker exec "$SIEM_CONTAINER" du -sb "$LOKI_DATA_DIR" 2>/dev/null | awk '{print $1}'
}

get_loki_data_size_human() {
    docker exec "$SIEM_CONTAINER" du -sh "$LOKI_DATA_DIR" 2>/dev/null | awk '{print $1}'
}

get_loki_stream_count() {
    # Query Loki for total number of streams via the series endpoint
    local response=$(docker exec "$WEBSERVER_CONTAINER" wget -qO- \
        "http://${LOKI_HOST}:${LOKI_PORT}/loki/api/v1/series?match[]=%7B__name__%3D~%22.%2B%22%7D" 2>/dev/null || echo '{"data":[]}')
    
    # Count the number of streams (series)
    echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data.get('data', [])))
except:
    print('0')
" 2>/dev/null || echo "0"
}

get_loki_ingester_memory() {
    # Query Loki metrics endpoint for ingester memory
    local response=$(docker exec "$WEBSERVER_CONTAINER" wget -qO- \
        "http://${LOKI_HOST}:${LOKI_PORT}/metrics" 2>/dev/null | \
        grep -E "^loki_ingester_memory_streams" | head -1 | awk '{print $2}')
    echo "${response:-0}"
}

# --- Main ---
main() {
    log_stage
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_info "Capturing baseline metrics from ${SIEM_CONTAINER}..."
    echo ""
    
    # Capture metrics
    log_info "Gathering container statistics..."
    
    local mem_human=$(get_container_memory)
    local mem_bytes=$(get_container_memory_bytes)
    local cpu_pct=$(get_container_cpu)
    
    log_info "Gathering Loki storage metrics..."
    
    local data_size_bytes=$(get_loki_data_size)
    local data_size_human=$(get_loki_data_size_human)
    
    log_info "Gathering Loki stream metrics..."
    
    local stream_count=$(get_loki_stream_count)
    local ingester_streams=$(get_loki_ingester_memory)
    
    # Display metrics
    echo ""
    echo -e "${MAGENTA}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${MAGENTA}│                    BASELINE METRICS                             │${NC}"
    echo -e "${MAGENTA}├─────────────────────────────────────────────────────────────────┤${NC}"
    printf "${MAGENTA}│${NC}  %-25s ${YELLOW}%-37s${NC} ${MAGENTA}│${NC}\n" "Timestamp:" "$timestamp"
    printf "${MAGENTA}│${NC}  %-25s ${YELLOW}%-37s${NC} ${MAGENTA}│${NC}\n" "Container:" "$SIEM_CONTAINER"
    echo -e "${MAGENTA}├─────────────────────────────────────────────────────────────────┤${NC}"
    printf "${MAGENTA}│${NC}  %-25s ${GREEN}%-37s${NC} ${MAGENTA}│${NC}\n" "Memory Usage:" "$mem_human"
    printf "${MAGENTA}│${NC}  %-25s ${GREEN}%-37s${NC} ${MAGENTA}│${NC}\n" "Memory (bytes):" "$mem_bytes"
    printf "${MAGENTA}│${NC}  %-25s ${GREEN}%-37s${NC} ${MAGENTA}│${NC}\n" "CPU Usage:" "${cpu_pct}%"
    echo -e "${MAGENTA}├─────────────────────────────────────────────────────────────────┤${NC}"
    printf "${MAGENTA}│${NC}  %-25s ${GREEN}%-37s${NC} ${MAGENTA}│${NC}\n" "Loki Data Size:" "$data_size_human"
    printf "${MAGENTA}│${NC}  %-25s ${GREEN}%-37s${NC} ${MAGENTA}│${NC}\n" "Loki Data (bytes):" "$data_size_bytes"
    printf "${MAGENTA}│${NC}  %-25s ${GREEN}%-37s${NC} ${MAGENTA}│${NC}\n" "Active Streams:" "$stream_count"
    printf "${MAGENTA}│${NC}  %-25s ${GREEN}%-37s${NC} ${MAGENTA}│${NC}\n" "Ingester Memory Streams:" "$ingester_streams"
    echo -e "${MAGENTA}└─────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    # Save to file
    cat > "$BASELINE_FILE" << EOF
# Loki Cardinality Attack - Baseline Metrics
# Generated: ${timestamp}
# Container: ${SIEM_CONTAINER}

BASELINE_TIMESTAMP="${timestamp}"
BASELINE_MEM_HUMAN="${mem_human}"
BASELINE_MEM_BYTES="${mem_bytes}"
BASELINE_CPU_PCT="${cpu_pct}"
BASELINE_DATA_SIZE_HUMAN="${data_size_human}"
BASELINE_DATA_SIZE_BYTES="${data_size_bytes}"
BASELINE_STREAM_COUNT="${stream_count}"
BASELINE_INGESTER_STREAMS="${ingester_streams}"
EOF
    
    log_success "Baseline metrics saved to: ${BASELINE_FILE}"
    echo ""
    
    exit 0
}

main "$@"
