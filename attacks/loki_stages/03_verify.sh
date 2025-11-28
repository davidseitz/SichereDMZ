#!/bin/bash

# ==========================================================================
# STAGE 03: Post-Attack Verification & Delta Analysis
# ==========================================================================
# Captures post-attack metrics and calculates the delta from baseline.
# Provides empirical evidence of the attack's impact.
# ==========================================================================

set -e

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIEM_CONTAINER="clab-security_lab-siem"
WEBSERVER_CONTAINER="clab-security_lab-web_server"

# Loki configuration
LOKI_HOST="10.10.30.2"
LOKI_PORT="3100"
LOKI_DATA_DIR="/loki"

# Input/Output files
BASELINE_FILE="${SCRIPT_DIR}/baseline_metrics.txt"
POSTATTACK_FILE="${SCRIPT_DIR}/postattack_metrics.txt"
RESULTS_FILE="${SCRIPT_DIR}/benchmark_results.txt"

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
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  STAGE 03: POST-ATTACK VERIFICATION                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
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

log_delta() {
    local metric="$1"
    local before="$2"
    local after="$3"
    local delta="$4"
    local pct="$5"
    
    local color="${GREEN}"
    if (( $(echo "$pct > 50" | bc -l 2>/dev/null || echo "0") )); then
        color="${RED}"
    elif (( $(echo "$pct > 20" | bc -l 2>/dev/null || echo "0") )); then
        color="${YELLOW}"
    fi
    
    printf "  %-28s %15s → %-15s ${color}Δ %-12s (%+.1f%%)${NC}\n" "$metric" "$before" "$after" "$delta" "$pct"
}

get_container_memory() {
    docker stats --no-stream --format "{{.MemUsage}}" "$SIEM_CONTAINER" 2>/dev/null | \
        awk -F'/' '{print $1}' | tr -d ' '
}

get_container_memory_bytes() {
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
    docker exec "$SIEM_CONTAINER" du -sb "$LOKI_DATA_DIR" 2>/dev/null | awk '{print $1}'
}

get_loki_data_size_human() {
    docker exec "$SIEM_CONTAINER" du -sh "$LOKI_DATA_DIR" 2>/dev/null | awk '{print $1}'
}

get_loki_stream_count() {
    local response=$(docker exec "$WEBSERVER_CONTAINER" wget -qO- \
        "http://${LOKI_HOST}:${LOKI_PORT}/loki/api/v1/series?match[]=%7B__name__%3D~%22.%2B%22%7D" 2>/dev/null || echo '{"data":[]}')
    
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
    local response=$(docker exec "$WEBSERVER_CONTAINER" wget -qO- \
        "http://${LOKI_HOST}:${LOKI_PORT}/metrics" 2>/dev/null | \
        grep -E "^loki_ingester_memory_streams" | head -1 | awk '{print $2}')
    echo "${response:-0}"
}

bytes_to_human() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc)GiB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc)MiB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc)KiB"
    else
        echo "${bytes}B"
    fi
}

calculate_pct_change() {
    local before=$1
    local after=$2
    
    if [ "$before" -eq 0 ] 2>/dev/null; then
        echo "0"
    else
        echo "scale=2; (($after - $before) * 100) / $before" | bc 2>/dev/null || echo "0"
    fi
}

# --- Main ---
main() {
    log_stage
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check baseline file exists
    if [ ! -f "$BASELINE_FILE" ]; then
        log_error "Baseline file not found: ${BASELINE_FILE}"
        log_error "Run 01_baseline.sh first!"
        exit 1
    fi
    
    # Load baseline metrics
    log_info "Loading baseline metrics..."
    source "$BASELINE_FILE"
    
    log_info "Capturing post-attack metrics from ${SIEM_CONTAINER}..."
    echo ""
    
    # Capture current metrics
    local post_mem_human=$(get_container_memory)
    local post_mem_bytes=$(get_container_memory_bytes)
    local post_cpu_pct=$(get_container_cpu)
    local post_data_size_bytes=$(get_loki_data_size)
    local post_data_size_human=$(get_loki_data_size_human)
    local post_stream_count=$(get_loki_stream_count)
    local post_ingester_streams=$(get_loki_ingester_memory)
    
    # Calculate deltas
    local mem_delta=$((post_mem_bytes - BASELINE_MEM_BYTES))
    local mem_delta_human=$(bytes_to_human $mem_delta)
    local mem_pct=$(calculate_pct_change "$BASELINE_MEM_BYTES" "$post_mem_bytes")
    
    local data_delta=$((post_data_size_bytes - BASELINE_DATA_SIZE_BYTES))
    local data_delta_human=$(bytes_to_human $data_delta)
    local data_pct=$(calculate_pct_change "$BASELINE_DATA_SIZE_BYTES" "$post_data_size_bytes")
    
    local stream_delta=$((post_stream_count - BASELINE_STREAM_COUNT))
    local stream_pct=$(calculate_pct_change "$BASELINE_STREAM_COUNT" "$post_stream_count")
    
    # Display results
    echo -e "${GREEN}┌─────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│                              BENCHMARK RESULTS                                          │${NC}"
    echo -e "${GREEN}├─────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${GREEN}│${NC}  Timestamp: ${YELLOW}${timestamp}${NC}"
    echo -e "${GREEN}│${NC}  Container: ${YELLOW}${SIEM_CONTAINER}${NC}"
    echo -e "${GREEN}├─────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${GREEN}│${NC}                              METRIC                    BEFORE          AFTER       DELTA${NC}"
    echo -e "${GREEN}├─────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
    
    log_delta "Container Memory:" "$BASELINE_MEM_HUMAN" "$post_mem_human" "$mem_delta_human" "$mem_pct"
    log_delta "Loki Data Size:" "$BASELINE_DATA_SIZE_HUMAN" "$post_data_size_human" "$data_delta_human" "$data_pct"
    log_delta "Active Streams:" "$BASELINE_STREAM_COUNT" "$post_stream_count" "$stream_delta" "$stream_pct"
    log_delta "Ingester Memory Streams:" "$BASELINE_INGESTER_STREAMS" "$post_ingester_streams" "$((post_ingester_streams - BASELINE_INGESTER_STREAMS))" "0"
    
    echo -e "${GREEN}└─────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    # Query Loki for attack evidence
    log_info "Querying Loki for attack evidence..."
    
    local attack_streams=$(docker exec "$WEBSERVER_CONTAINER" wget -qO- \
        "http://${LOKI_HOST}:${LOKI_PORT}/loki/api/v1/series?match[]=%7Bjob%3D%22application%22%7D" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "0")
    
    local poc_streams=$(docker exec "$WEBSERVER_CONTAINER" wget -qO- \
        "http://${LOKI_HOST}:${LOKI_PORT}/loki/api/v1/series?match[]=%7Bjob%3D%22redteam_poc%22%7D" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "0")
    
    echo -e "${YELLOW}Attack Evidence:${NC}"
    echo "  • Streams with job='application': ${attack_streams}"
    echo "  • Streams with job='redteam_poc': ${poc_streams}"
    echo ""
    
    # Save post-attack metrics
    cat > "$POSTATTACK_FILE" << EOF
# Loki Cardinality Attack - Post-Attack Metrics
# Generated: ${timestamp}
# Container: ${SIEM_CONTAINER}

POSTATTACK_TIMESTAMP="${timestamp}"
POSTATTACK_MEM_HUMAN="${post_mem_human}"
POSTATTACK_MEM_BYTES="${post_mem_bytes}"
POSTATTACK_CPU_PCT="${post_cpu_pct}"
POSTATTACK_DATA_SIZE_HUMAN="${post_data_size_human}"
POSTATTACK_DATA_SIZE_BYTES="${post_data_size_bytes}"
POSTATTACK_STREAM_COUNT="${post_stream_count}"
POSTATTACK_INGESTER_STREAMS="${post_ingester_streams}"
EOF
    
    # Save comprehensive results
    cat > "$RESULTS_FILE" << EOF
# ============================================================
# LOKI CARDINALITY ATTACK - BENCHMARK RESULTS
# ============================================================
# Generated: ${timestamp}
# Container: ${SIEM_CONTAINER}
# Target: ${LOKI_HOST}:${LOKI_PORT}
# ============================================================

# BASELINE METRICS (Pre-Attack)
BASELINE_TIMESTAMP="${BASELINE_TIMESTAMP}"
BASELINE_MEM_HUMAN="${BASELINE_MEM_HUMAN}"
BASELINE_MEM_BYTES="${BASELINE_MEM_BYTES}"
BASELINE_DATA_SIZE_HUMAN="${BASELINE_DATA_SIZE_HUMAN}"
BASELINE_DATA_SIZE_BYTES="${BASELINE_DATA_SIZE_BYTES}"
BASELINE_STREAM_COUNT="${BASELINE_STREAM_COUNT}"

# POST-ATTACK METRICS
POSTATTACK_TIMESTAMP="${timestamp}"
POSTATTACK_MEM_HUMAN="${post_mem_human}"
POSTATTACK_MEM_BYTES="${post_mem_bytes}"
POSTATTACK_DATA_SIZE_HUMAN="${post_data_size_human}"
POSTATTACK_DATA_SIZE_BYTES="${post_data_size_bytes}"
POSTATTACK_STREAM_COUNT="${post_stream_count}"

# DELTA (Impact)
DELTA_MEM_BYTES="${mem_delta}"
DELTA_MEM_HUMAN="${mem_delta_human}"
DELTA_MEM_PCT="${mem_pct}"
DELTA_DATA_BYTES="${data_delta}"
DELTA_DATA_HUMAN="${data_delta_human}"
DELTA_DATA_PCT="${data_pct}"
DELTA_STREAM_COUNT="${stream_delta}"
DELTA_STREAM_PCT="${stream_pct}"

# ATTACK EVIDENCE
ATTACK_STREAMS_APPLICATION="${attack_streams}"
ATTACK_STREAMS_POC="${poc_streams}"
EOF
    
    log_success "Results saved to: ${RESULTS_FILE}"
    echo ""
    
    # Print summary assessment
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                         IMPACT ASSESSMENT                          ${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    
    if [ "$stream_delta" -gt 1000 ]; then
        echo -e "  ${RED}⚠ CRITICAL:${NC} Stream count increased by ${stream_delta} (${stream_pct}%)"
        echo -e "  ${RED}⚠ IMPACT:${NC} Significant index bloat detected"
    elif [ "$stream_delta" -gt 100 ]; then
        echo -e "  ${YELLOW}⚠ WARNING:${NC} Stream count increased by ${stream_delta} (${stream_pct}%)"
    else
        echo -e "  ${GREEN}✓ MINIMAL:${NC} Stream count change: ${stream_delta}"
    fi
    
    if [ "$data_delta" -gt 10485760 ]; then  # 10MB
        echo -e "  ${RED}⚠ CRITICAL:${NC} Storage grew by ${data_delta_human} (${data_pct}%)"
    elif [ "$data_delta" -gt 1048576 ]; then  # 1MB
        echo -e "  ${YELLOW}⚠ WARNING:${NC} Storage grew by ${data_delta_human} (${data_pct}%)"
    else
        echo -e "  ${GREEN}✓ MINIMAL:${NC} Storage change: ${data_delta_human}"
    fi
    
    if [ "$mem_delta" -gt 104857600 ]; then  # 100MB
        echo -e "  ${RED}⚠ CRITICAL:${NC} Memory increased by ${mem_delta_human} (${mem_pct}%)"
    elif [ "$mem_delta" -gt 52428800 ]; then  # 50MB
        echo -e "  ${YELLOW}⚠ WARNING:${NC} Memory increased by ${mem_delta_human} (${mem_pct}%)"
    else
        echo -e "  ${GREEN}✓ MODERATE:${NC} Memory change: ${mem_delta_human}"
    fi
    
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    exit 0
}

main "$@"
