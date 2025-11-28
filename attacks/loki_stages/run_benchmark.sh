#!/bin/bash

# ==========================================================================
# LOKI CARDINALITY ATTACK - BENCHMARK RUNNER
# ==========================================================================
# Master script that orchestrates the complete benchmark workflow:
#   Stage 00: Environment Reset (fresh SIEM instance)
#   Stage 01: Baseline Capture (pre-attack metrics)
#   Stage 02: Cardinality Explosion Attack
#   Stage 03: Verification & Delta Analysis
#
# Author: Red Team Assessment
# Date: 2025-11-28
# ==========================================================================

set -e

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Stage scripts
STAGE_00="${SCRIPT_DIR}/00_reset.sh"
STAGE_01="${SCRIPT_DIR}/01_baseline.sh"
STAGE_02="${SCRIPT_DIR}/02_attack.sh"
STAGE_03="${SCRIPT_DIR}/03_verify.sh"

# Output
LOG_DIR="${SCRIPT_DIR}"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
MASTER_LOG="${LOG_DIR}/benchmark_${TIMESTAMP}.log"

# Options
SKIP_RESET=false
VERBOSE=false

# --- Colors ---
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
WHITE="\033[1;37m"
NC="\033[0m"

# --- Functions ---
print_banner() {
    echo -e "${RED}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════════════╗
    ║                                                                       ║
    ║   ██████╗ ███████╗███╗   ██╗ ██████╗██╗  ██╗███╗   ███╗ █████╗ ██████╗║
    ║   ██╔══██╗██╔════╝████╗  ██║██╔════╝██║  ██║████╗ ████║██╔══██╗██╔══██╗
    ║   ██████╔╝█████╗  ██╔██╗ ██║██║     ███████║██╔████╔██║███████║██████╔╝
    ║   ██╔══██╗██╔══╝  ██║╚██╗██║██║     ██╔══██║██║╚██╔╝██║██╔══██║██╔══██╗
    ║   ██████╔╝███████╗██║ ╚████║╚██████╗██║  ██║██║ ╚═╝ ██║██║  ██║██║  ██║
    ║   ╚═════╝ ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝
    ║                                                                       ║
    ║         LOKI CARDINALITY EXPLOSION - BENCHMARK SUITE                  ║
    ╚═══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

log_master() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$MASTER_LOG"
}

run_stage() {
    local stage_name="$1"
    local stage_script="$2"
    local stage_num="$3"
    
    echo ""
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  RUNNING: ${stage_name}${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    log_master "INFO" "Starting ${stage_name}"
    
    if [ ! -f "$stage_script" ]; then
        echo -e "${RED}[ERROR] Stage script not found: ${stage_script}${NC}"
        log_master "ERROR" "Stage script not found: ${stage_script}"
        return 1
    fi
    
    chmod +x "$stage_script"
    
    local start_time=$(date +%s)
    
    if "$stage_script"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo ""
        echo -e "${GREEN}[✓] ${stage_name} completed in ${duration}s${NC}"
        log_master "SUCCESS" "${stage_name} completed in ${duration}s"
        return 0
    else
        local exit_code=$?
        echo ""
        echo -e "${RED}[✗] ${stage_name} failed with exit code ${exit_code}${NC}"
        log_master "ERROR" "${stage_name} failed with exit code ${exit_code}"
        return 1
    fi
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-reset    Skip Stage 00 (environment reset)"
    echo "  --verbose       Enable verbose output"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Stages:"
    echo "  00_reset.sh     Reset lab environment to fresh state"
    echo "  01_baseline.sh  Capture pre-attack metrics"
    echo "  02_attack.sh    Execute cardinality explosion attack"
    echo "  03_verify.sh    Capture post-attack metrics and calculate delta"
    echo ""
    exit 0
}

# --- Main ---
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-reset)
                SKIP_RESET=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Print banner
    print_banner
    
    local total_start=$(date +%s)
    
    echo -e "${CYAN}Benchmark Started: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}Master Log: ${MASTER_LOG}${NC}"
    echo ""
    
    log_master "INFO" "Benchmark started"
    log_master "INFO" "Skip reset: ${SKIP_RESET}"
    
    # Stage 00: Environment Reset
    if [ "$SKIP_RESET" = false ]; then
        if ! run_stage "Stage 00: Environment Reset" "$STAGE_00" "00"; then
            echo -e "${RED}[FATAL] Environment reset failed. Aborting benchmark.${NC}"
            exit 1
        fi
    else
        echo ""
        echo -e "${YELLOW}[SKIP] Stage 00: Environment Reset (--skip-reset specified)${NC}"
        log_master "INFO" "Stage 00 skipped"
    fi
    
    # Stage 01: Baseline Capture
    if ! run_stage "Stage 01: Baseline Capture" "$STAGE_01" "01"; then
        echo -e "${RED}[FATAL] Baseline capture failed. Aborting benchmark.${NC}"
        exit 1
    fi
    
    # Stage 02: Cardinality Explosion Attack
    if ! run_stage "Stage 02: Cardinality Explosion Attack" "$STAGE_02" "02"; then
        echo -e "${YELLOW}[WARN] Attack stage reported failure, continuing to verification...${NC}"
        log_master "WARN" "Attack stage failed but continuing"
    fi
    
    # Stage 03: Post-Attack Verification
    if ! run_stage "Stage 03: Post-Attack Verification" "$STAGE_03" "03"; then
        echo -e "${RED}[ERROR] Verification stage failed.${NC}"
        exit 1
    fi
    
    # Final Summary
    local total_end=$(date +%s)
    local total_duration=$((total_end - total_start))
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    BENCHMARK COMPLETE                                 ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "  Total Duration: ${WHITE}${total_duration} seconds${NC}"
    echo -e "  Master Log:     ${WHITE}${MASTER_LOG}${NC}"
    echo -e "  Results:        ${WHITE}${SCRIPT_DIR}/benchmark_results.txt${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    log_master "SUCCESS" "Benchmark completed in ${total_duration}s"
    
    # Display final results file
    if [ -f "${SCRIPT_DIR}/benchmark_results.txt" ]; then
        echo -e "${CYAN}Final Results Summary:${NC}"
        cat "${SCRIPT_DIR}/benchmark_results.txt"
    fi
    
    exit 0
}

main "$@"
