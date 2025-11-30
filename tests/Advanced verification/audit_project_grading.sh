#!/bin/bash

# =============================================================================
# SUN PROJECT - PRE-SUBMISSION GRADING AUDIT
# =============================================================================
# Verifies all requirements from SUN_Programmentwurf.pdf are met.
# Run this before the live demo to ensure maximum points (100/100).
# =============================================================================

set -o pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Required containers (mapped to PDF requirements)
REQUIRED_CONTAINERS=(
    "clab-security_lab-edge_router:Gateway/Firewall (nftables)"
    "clab-security_lab-internal_router:Internal Router/Firewall"
    "clab-security_lab-reverse_proxy:WAF (ModSecurity)"
    "clab-security_lab-web_server:Web Server (Frontend)"
    "clab-security_lab-database:Database (MariaDB Backend)"
    "clab-security_lab-siem:SIEM (Grafana Loki)"
    "clab-security_lab-bastion:Bastion Host (Jump Server)"
)

# Network zones (IP ranges)
INTERNET_ZONE="192.168.1.0/24"      # Attacker network
DMZ_ZONE="10.10.10.0/29"            # WAF, Web Server
SECURITY_ZONE="10.10.30.0/29"       # SIEM
BACKEND_ZONE="10.10.40.0/29"        # Database

# Key IPs
WAF_IP="10.10.10.3"
WEBSERVER_IP="10.10.10.4"
DATABASE_IP="10.10.40.2"
SIEM_IP="10.10.30.2"
BASTION_IP="10.10.20.2"
ATTACKER_IP="192.168.1.2"

# --- Colors ---
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
WHITE="\033[1;37m"
BOLD="\033[1m"
NC="\033[0m"

# --- Counters ---
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNED_CHECKS=0

# --- Grading Categories ---
declare -A CATEGORY_SCORES
CATEGORY_SCORES["architecture"]=0
CATEGORY_SCORES["architecture_max"]=0
CATEGORY_SCORES["security"]=0
CATEGORY_SCORES["security_max"]=0
CATEGORY_SCORES["functionality"]=0
CATEGORY_SCORES["functionality_max"]=0

# --- Functions ---
print_banner() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                                           ║${NC}"
    echo -e "${CYAN}║   ${WHITE}███████╗██╗   ██╗███╗   ██╗    ${YELLOW}GRADING AUDIT${CYAN}                         ║${NC}"
    echo -e "${CYAN}║   ${WHITE}██╔════╝██║   ██║████╗  ██║    ${NC}Sichere Unternehmensnetzwerke${CYAN}            ║${NC}"
    echo -e "${CYAN}║   ${WHITE}███████╗██║   ██║██╔██╗ ██║    ${NC}Pre-Submission Verification${CYAN}             ║${NC}"
    echo -e "${CYAN}║   ${WHITE}╚════██║██║   ██║██║╚██╗██║${CYAN}                                             ║${NC}"
    echo -e "${CYAN}║   ${WHITE}███████║╚██████╔╝██║ ╚████║${CYAN}                                             ║${NC}"
    echo -e "${CYAN}║   ${WHITE}╚══════╝ ╚═════╝ ╚═╝  ╚═══╝${CYAN}                                             ║${NC}"
    echo -e "${CYAN}║                                                                           ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}Audit Date:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "  ${WHITE}Project:${NC}    ${PROJECT_ROOT}"
    echo ""
}

print_section() {
    local title="$1"
    local points="$2"
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}  ${WHITE}${title}${NC} ${YELLOW}(${points} Points)${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

check_pass() {
    local description="$1"
    local category="$2"
    local points="${3:-1}"
    
    ((TOTAL_CHECKS++))
    ((PASSED_CHECKS++))
    CATEGORY_SCORES["${category}"]=$((CATEGORY_SCORES["${category}"] + points))
    CATEGORY_SCORES["${category}_max"]=$((CATEGORY_SCORES["${category}_max"] + points))
    
    printf "  %-55s [${GREEN}PASS${NC}] +%d\n" "$description" "$points"
}

check_fail() {
    local description="$1"
    local category="$2"
    local points="${3:-1}"
    local reason="${4:-}"
    
    ((TOTAL_CHECKS++))
    ((FAILED_CHECKS++))
    CATEGORY_SCORES["${category}_max"]=$((CATEGORY_SCORES["${category}_max"] + points))
    
    printf "  %-55s [${RED}FAIL${NC}]  0\n" "$description"
    if [ -n "$reason" ]; then
        echo -e "       ${YELLOW}→ $reason${NC}"
    fi
}

check_warn() {
    local description="$1"
    local category="$2"
    local points="${3:-1}"
    local reason="${4:-}"
    
    ((TOTAL_CHECKS++))
    ((WARNED_CHECKS++))
    # Partial credit
    local partial=$((points / 2))
    CATEGORY_SCORES["${category}"]=$((CATEGORY_SCORES["${category}"] + partial))
    CATEGORY_SCORES["${category}_max"]=$((CATEGORY_SCORES["${category}_max"] + points))
    
    printf "  %-55s [${YELLOW}WARN${NC}] +%d\n" "$description" "$partial"
    if [ -n "$reason" ]; then
        echo -e "       ${YELLOW}→ $reason${NC}"
    fi
}

# Check if container is running
container_running() {
    docker ps --format '{{.Names}}' | grep -q "^${1}$"
}

# Test TCP connectivity between containers
test_connectivity() {
    local from_container="$1"
    local to_ip="$2"
    local to_port="$3"
    local timeout="${4:-3}"
    
    # Try nc first, then bash /dev/tcp, then timeout+cat
    if docker exec "$from_container" which nc &>/dev/null; then
        docker exec "$from_container" nc -z -w "$timeout" "$to_ip" "$to_port" 2>/dev/null
        return $?
    elif docker exec "$from_container" which bash &>/dev/null; then
        docker exec "$from_container" timeout "$timeout" bash -c "cat < /dev/tcp/$to_ip/$to_port" &>/dev/null
        return $?
    else
        # Fallback: try ping (less accurate for port)
        docker exec "$from_container" ping -c 1 -W "$timeout" "$to_ip" &>/dev/null
        return $?
    fi
}

# =============================================================================
# AUDIT SECTION 1: ARCHITECTURE (20 Points)
# =============================================================================
audit_architecture() {
    print_section "SECTION 1: ARCHITECTURE REQUIREMENTS" "20"
    
    echo ""
    echo -e "  ${CYAN}▶ 1.1 Required Components${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    for entry in "${REQUIRED_CONTAINERS[@]}"; do
        local container="${entry%%:*}"
        local description="${entry##*:}"
        
        if container_running "$container"; then
            check_pass "$description" "architecture" 2
        else
            check_fail "$description" "architecture" 2 "Container not running"
        fi
    done
    
    echo ""
    echo -e "  ${CYAN}▶ 1.2 Network Segmentation${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    # Check network interfaces exist
    local zones_configured=true
    
    if docker exec clab-security_lab-edge_router ip addr | grep -q "10.10.10.1"; then
        check_pass "DMZ Zone configured (10.10.10.0/29)" "architecture" 2
    else
        check_fail "DMZ Zone configured" "architecture" 2
        zones_configured=false
    fi
    
    if docker exec clab-security_lab-internal_router ip addr | grep -q "10.10.40.1"; then
        check_pass "Backend Zone configured (10.10.40.0/29)" "architecture" 2
    else
        check_fail "Backend Zone configured" "architecture" 2
        zones_configured=false
    fi
    
    if docker exec clab-security_lab-internal_router ip addr | grep -q "10.10.30.1"; then
        check_pass "Security Zone configured (10.10.30.0/29)" "architecture" 2
    else
        check_fail "Security Zone configured" "architecture" 2
        zones_configured=false
    fi
}

# =============================================================================
# AUDIT SECTION 2: SECURITY / HARDENING (20 Points)
# =============================================================================
audit_security() {
    print_section "SECTION 2: SECURITY & HARDENING" "20"
    
    echo ""
    echo -e "  ${CYAN}▶ 2.1 SSH Hardening (Bastion)${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    # Check PasswordAuthentication
    if docker exec clab-security_lab-bastion grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
        check_pass "PasswordAuthentication disabled" "security" 3
    else
        check_fail "PasswordAuthentication disabled" "security" 3 "Password login still allowed"
    fi
    
    # Check PermitRootLogin
    if docker exec clab-security_lab-bastion grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
        check_pass "Root login disabled" "security" 3
    else
        check_fail "Root login disabled" "security" 3 "Root can still SSH in"
    fi
    
    # Check PubkeyAuthentication
    if docker exec clab-security_lab-bastion grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
        check_pass "Public key authentication enabled" "security" 2
    else
        check_warn "Public key authentication enabled" "security" 2 "Not explicitly set"
    fi
    
    echo ""
    echo -e "  ${CYAN}▶ 2.2 Firewall Rules (nftables)${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    # Check firewall is active on edge router
    if docker exec clab-security_lab-edge_router nft list ruleset 2>/dev/null | grep -q "chain"; then
        check_pass "nftables active on Edge Router" "security" 2
    else
        check_fail "nftables active on Edge Router" "security" 2
    fi
    
    # Check firewall on internal router
    if docker exec clab-security_lab-internal_router nft list ruleset 2>/dev/null | grep -q "chain"; then
        check_pass "nftables active on Internal Router" "security" 2
    else
        check_fail "nftables active on Internal Router" "security" 2
    fi
    
    echo ""
    echo -e "  ${CYAN}▶ 2.3 Least Privilege (sudo restrictions)${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    # Check sudoers restrictions on bastion (representative container)
    local sudoers_restricted=false
    local sudoers_content
    sudoers_content=$(docker exec clab-security_lab-bastion sh -c 'cat /etc/sudoers.d/* 2>/dev/null' || echo "")
    
    if echo "$sudoers_content" | grep -qE "(apk update|apt-get update)"; then
        # Has restricted command
        if ! echo "$sudoers_content" | grep -qE "ALL=\(ALL\)\s*ALL|ALL=\(ALL:ALL\)\s*ALL|NOPASSWD:\s*ALL"; then
            check_pass "admin user restricted to updates only" "security" 4
            sudoers_restricted=true
        fi
    fi
    
    if [ "$sudoers_restricted" = false ]; then
        check_fail "admin user restricted to updates only" "security" 4 "Overly permissive sudo"
    fi
    
    echo ""
    echo -e "  ${CYAN}▶ 2.4 WAF Configuration (ModSecurity)${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    # Check ModSecurity is enabled
    if docker exec clab-security_lab-reverse_proxy cat /etc/nginx/nginx.conf 2>/dev/null | grep -qi "modsecurity on"; then
        check_pass "ModSecurity enabled in WAF" "security" 2
    elif docker exec clab-security_lab-reverse_proxy ls /etc/nginx/modsecurity.d/ 2>/dev/null | grep -q ".conf"; then
        check_pass "ModSecurity rules present" "security" 2
    else
        check_fail "ModSecurity enabled in WAF" "security" 2
    fi
    
    # Check OWASP CRS rules
    if docker exec clab-security_lab-reverse_proxy ls /etc/nginx/modsecurity.d/ 2>/dev/null | grep -qiE "crs|owasp"; then
        check_pass "OWASP CRS rules loaded" "security" 2
    elif docker exec clab-security_lab-reverse_proxy find /etc -name "*crs*" 2>/dev/null | grep -q crs; then
        check_pass "OWASP CRS rules present" "security" 2
    else
        check_warn "OWASP CRS rules loaded" "security" 2 "Rules may be custom"
    fi
}

# =============================================================================
# AUDIT SECTION 3: FUNCTIONALITY (20 Points)
# =============================================================================
audit_functionality() {
    print_section "SECTION 3: FUNCTIONALITY & NETWORK ISOLATION" "20"
    
    echo ""
    echo -e "  ${CYAN}▶ 3.1 Network Isolation Tests${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    # Test: WAF should NOT reach Database directly
    echo -n "  "
    if ! test_connectivity "clab-security_lab-reverse_proxy" "$DATABASE_IP" "3306"; then
        check_pass "WAF cannot reach Database (isolated)" "functionality" 3
    else
        check_fail "WAF cannot reach Database (isolated)" "functionality" 3 "WAF has direct DB access!"
    fi
    
    # Test: Attacker should NOT reach Database
    echo -n "  "
    if ! test_connectivity "clab-security_lab-attacker_1" "$DATABASE_IP" "3306"; then
        check_pass "Internet cannot reach Database" "functionality" 3
    else
        check_fail "Internet cannot reach Database" "functionality" 3 "CRITICAL: DB exposed!"
    fi
    
    # Test: Attacker should NOT reach SIEM
    echo -n "  "
    if ! test_connectivity "clab-security_lab-attacker_1" "$SIEM_IP" "3100"; then
        check_pass "Internet cannot reach SIEM" "functionality" 2
    else
        check_fail "Internet cannot reach SIEM" "functionality" 2 "SIEM exposed to internet!"
    fi
    
    # Test: Web Server SHOULD reach Database
    echo -n "  "
    if test_connectivity "clab-security_lab-web_server" "$DATABASE_IP" "3306"; then
        check_pass "Web Server can reach Database" "functionality" 3
    else
        check_fail "Web Server can reach Database" "functionality" 3 "App cannot connect to DB"
    fi
    
    # Test: Web Server SHOULD reach SIEM (for logging)
    echo -n "  "
    if test_connectivity "clab-security_lab-web_server" "$SIEM_IP" "3100"; then
        check_pass "Web Server can reach SIEM (logging)" "functionality" 2
    else
        check_fail "Web Server can reach SIEM (logging)" "functionality" 2 "Logs cannot be forwarded"
    fi
    
    echo ""
    echo -e "  ${CYAN}▶ 3.2 Service Health${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    # Web service accessible via WAF
    if docker exec clab-security_lab-attacker_1 nc -z -w 3 "$WAF_IP" 443 2>/dev/null || \
       docker exec clab-security_lab-attacker_1 nc -z -w 3 "$WAF_IP" 80 2>/dev/null; then
        check_pass "Web service accessible via WAF (80/443)" "functionality" 2
    else
        check_fail "Web service accessible via WAF" "functionality" 2
    fi
    
    # SIEM/Loki responding
    if docker exec clab-security_lab-siem wget -q -O - --timeout=3 "http://127.0.0.1:3100/ready" 2>/dev/null | grep -q "ready"; then
        check_pass "SIEM (Loki) service healthy" "functionality" 2
    else
        check_warn "SIEM (Loki) service healthy" "functionality" 2 "May require auth"
    fi
    
    # Database responding
    if test_connectivity "clab-security_lab-database" "127.0.0.1" "3306"; then
        check_pass "Database (MariaDB) service healthy" "functionality" 2
    else
        check_fail "Database (MariaDB) service healthy" "functionality" 2
    fi
    
    # IDS (Suricata) running
    if docker exec clab-security_lab-web_server pgrep -x suricata >/dev/null 2>&1 || \
       docker exec clab-security_lab-internal_router pgrep -x suricata >/dev/null 2>&1; then
        check_pass "IDS (Suricata) running" "functionality" 1
    else
        check_warn "IDS (Suricata) running" "functionality" 1 "Check Suricata status"
    fi
}

# =============================================================================
# AUDIT SECTION 4: ATTACK DEMONSTRATIONS (40 Points)
# =============================================================================
audit_attacks() {
    print_section "SECTION 4: ATTACK DEMONSTRATION READINESS" "40"
    
    echo ""
    echo -e "  ${CYAN}▶ 4.1 Attack Scripts Present${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    # Attack 1: WAF Bypass / Flood Attack
    if [ -f "${PROJECT_ROOT}/attacks/python-scripts/flood_users.py" ]; then
        check_pass "Attack 1: WAF Stress Test (flood_users.py)" "functionality" 5
    else
        check_fail "Attack 1: WAF Stress Test" "functionality" 5
    fi
    
    # Attack 2: SIEM Cardinality Explosion
    if [ -f "${PROJECT_ROOT}/attacks/python-scripts/loki_cardinality_attack.py" ]; then
        check_pass "Attack 2: SIEM Attack (loki_cardinality_attack.py)" "functionality" 5
    else
        check_fail "Attack 2: SIEM Attack" "functionality" 5
    fi
    
    # Attack 3: ZAP Vulnerability Scan (OWASP Top 10)
    if [ -f "${PROJECT_ROOT}/attacks/zap_scan_full.sh" ] || [ -f "${PROJECT_ROOT}/attacks/zap_scan_baseline.sh" ]; then
        check_pass "Attack 3: OWASP ZAP Scan (zap_scan_*.sh)" "functionality" 5
    else
        check_warn "Attack 3: OWASP ZAP Scan" "functionality" 5 "Consider adding ZAP scan"
    fi
    
    # Bonus: Network scanning
    if [ -f "${PROJECT_ROOT}/attacks/scan_inside.sh" ] && [ -f "${PROJECT_ROOT}/attacks/scan_outside.sh" ]; then
        check_pass "Bonus: Network Reconnaissance Scripts" "functionality" 2
    fi
    
    echo ""
    echo -e "  ${CYAN}▶ 4.2 Attack Documentation${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    # Loki attack documentation
    if [ -f "${PROJECT_ROOT}/attacks/docs/LOKI_ATTACK_DOCUMENTATION.md" ]; then
        check_pass "SIEM Attack documented" "functionality" 3
    else
        check_fail "SIEM Attack documented" "functionality" 3
    fi
    
    # Attack automation (benchmark suite)
    if [ -d "${PROJECT_ROOT}/attacks/loki_stages" ]; then
        check_pass "Attack automation suite (loki_stages/)" "functionality" 2
    fi
    
    echo ""
    echo -e "  ${CYAN}▶ 4.3 Verification Tests${NC}"
    echo "  ─────────────────────────────────────────────────────────────"
    
    # Security test suite
    if [ -f "${PROJECT_ROOT}/tests/test_security_comprehensive.sh" ]; then
        check_pass "Comprehensive security test suite" "functionality" 3
    elif [ -f "${PROJECT_ROOT}/tests/verify_least_privilege.sh" ]; then
        check_pass "Least privilege verification script" "functionality" 2
    else
        check_warn "Security verification scripts" "functionality" 3
    fi
    
    # Report generation
    local report_count
    report_count=$(ls -1 "${PROJECT_ROOT}/attacks/reports/"*.html 2>/dev/null | wc -l)
    if [ "$report_count" -gt 0 ]; then
        check_pass "Attack reports generated ($report_count reports)" "functionality" 2
    else
        check_warn "Attack reports generated" "functionality" 2 "Run ZAP to generate reports"
    fi
}

# =============================================================================
# FINAL SUMMARY
# =============================================================================
print_summary() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                          GRADING SUMMARY                                  ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Calculate totals
    local arch_score=${CATEGORY_SCORES["architecture"]}
    local arch_max=${CATEGORY_SCORES["architecture_max"]}
    local sec_score=${CATEGORY_SCORES["security"]}
    local sec_max=${CATEGORY_SCORES["security_max"]}
    local func_score=${CATEGORY_SCORES["functionality"]}
    local func_max=${CATEGORY_SCORES["functionality_max"]}
    
    local total_score=$((arch_score + sec_score + func_score))
    local total_max=$((arch_max + sec_max + func_max))
    
    # Normalize to 100-point scale (adjust weights as needed)
    local normalized_score=$((total_score * 100 / total_max))
    
    printf "  ${WHITE}%-40s${NC} %3d / %3d\n" "1. Architecture Requirements:" "$arch_score" "$arch_max"
    printf "  ${WHITE}%-40s${NC} %3d / %3d\n" "2. Security & Hardening:" "$sec_score" "$sec_max"
    printf "  ${WHITE}%-40s${NC} %3d / %3d\n" "3. Functionality & Attacks:" "$func_score" "$func_max"
    echo "  ───────────────────────────────────────────────────────"
    printf "  ${WHITE}%-40s${NC} %3d / %3d\n" "RAW TOTAL:" "$total_score" "$total_max"
    echo ""
    printf "  ${WHITE}%-40s${NC} ${BOLD}%3d / 100${NC}\n" "ESTIMATED GRADE:" "$normalized_score"
    echo ""
    
    # Pass/Fail determination
    echo "  ───────────────────────────────────────────────────────"
    echo -e "  ${WHITE}Checks:${NC} $PASSED_CHECKS passed, $FAILED_CHECKS failed, $WARNED_CHECKS warnings"
    echo ""
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        echo -e "  ${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${GREEN}║  ✓ PROJECT READY FOR SUBMISSION                                  ║${NC}"
        echo -e "  ${GREEN}║    All critical checks passed. Good luck with the demo!          ║${NC}"
        echo -e "  ${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    elif [ $FAILED_CHECKS -le 3 ]; then
        echo -e "  ${YELLOW}╔═══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${YELLOW}║  ⚠ MINOR ISSUES DETECTED                                         ║${NC}"
        echo -e "  ${YELLOW}║    $FAILED_CHECKS issue(s) should be fixed before submission.              ║${NC}"
        echo -e "  ${YELLOW}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "  ${RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${RED}║  ✗ CRITICAL ISSUES - DO NOT SUBMIT                               ║${NC}"
        echo -e "  ${RED}║    $FAILED_CHECKS critical issue(s) must be resolved.                       ║${NC}"
        echo -e "  ${RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    fi
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    print_banner
    
    audit_architecture
    audit_security
    audit_functionality
    audit_attacks
    
    print_summary
}

main "$@"
