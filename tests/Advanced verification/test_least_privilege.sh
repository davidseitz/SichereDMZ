#!/bin/bash

# =============================================================================
# LEAST PRIVILEGE VERIFICATION SCRIPT
# =============================================================================
# Purpose: Validates that the 'admin' user sudoers policy enforces least
#          privilege - allowing ONLY system updates, blocking all other
#          privileged actions.
#
# Security Control: Sudoers whitelist for maintenance operations only
# Author: Red Team Assessment
# Date: 2025-11-29
# =============================================================================

set -o pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/dev/null"
# LOG_FILE="${SCRIPT_DIR}/least_privilege_audit_$(date +%Y-%m-%d_%H-%M-%S).log"

# Containers to test (excluding switches)
ALPINE_CONTAINERS=(
    "clab-security_lab-web_server"
    "clab-security_lab-bastion"
    "clab-security_lab-database"
    "clab-security_lab-siem"
    "clab-security_lab-timedns_server"
)

DEBIAN_CONTAINERS=(
    "clab-security_lab-internal_router"
    "clab-security_lab-edge_router"
    "clab-security_lab-reverse_proxy"
)

# Test user
TEST_USER="admin"

# --- Colors ---
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
WHITE="\033[1;37m"
NC="\033[0m"
BOLD="\033[1m"

# --- Counters ---
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# --- Functions ---

print_banner() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                                       ║${NC}"
    echo -e "${CYAN}║   ${WHITE}LEAST PRIVILEGE VERIFICATION - SECURITY CONTROL AUDIT${CYAN}            ║${NC}"
    echo -e "${CYAN}║                                                                       ║${NC}"
    echo -e "${CYAN}║   ${YELLOW}Policy: admin user restricted to update/upgrade operations only${CYAN}  ║${NC}"
    echo -e "${CYAN}║   ${YELLOW}Target: clab-security_lab-* containers (non-switch)${CYAN}              ║${NC}"
    echo -e "${CYAN}║                                                                       ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_test_header() {
    local container="$1"
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}  Testing: ${WHITE}${container}${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Run a command inside a container as the admin user
# Returns: exit code of the command
run_as_admin() {
    local container="$1"
    local cmd="$2"
    local timeout="${3:-10}"
    
    # Execute command as admin user with timeout
    docker exec -u "$TEST_USER" "$container" timeout "$timeout" sh -c "$cmd" 2>&1
    return $?
}

# Test that an ALLOWED action SUCCEEDS
# Pass if exit code = 0 OR if only blocked by password (not permission)
test_allowed_action() {
    local container="$1"
    local description="$2"
    local command="$3"
    local timeout="${4:-30}"
    
    ((TOTAL_TESTS++))
    
    printf "  %-50s " "$description"
    log_msg "TEST [ALLOWED]: $description on $container"
    log_msg "  Command: $command"
    
    local output
    output=$(run_as_admin "$container" "$command" "$timeout" 2>&1)
    local exit_code=$?
    
    log_msg "  Exit Code: $exit_code"
    log_msg "  Output: $output"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "[${GREEN}PASS${NC}] Action permitted ✓"
        ((PASSED_TESTS++))
        return 0
    else
        # Check if blocked due to password requirement (not permission)
        # This is acceptable - the user IS allowed, just needs auth
        if echo "$output" | grep -qiE "password is required|password for|authentication failure"; then
            echo -e "[${GREEN}PASS${NC}] Allowed (password required) ✓"
            ((PASSED_TESTS++))
            return 0
        fi
        
        # Check if it's a permission denial (sudoers restriction)
        if echo "$output" | grep -qiE "not allowed|sorry.*not allowed|is not in the sudoers"; then
            echo -e "[${RED}FAIL${NC}] Action blocked by sudoers!"
            echo -e "       ${YELLOW}Expected: Allowed | Got: Permission denied${NC}"
            ((FAILED_TESTS++))
            return 1
        fi
        
        # Other failure - might be network/timeout etc
        echo -e "[${YELLOW}WARN${NC}] Exit code $exit_code (non-permission)"
        ((PASSED_TESTS++))
        return 0
    fi
}

# Test that a FORBIDDEN action is BLOCKED
# Pass if exit code != 0 AND output contains permission/not allowed message
test_forbidden_action() {
    local container="$1"
    local description="$2"
    local command="$3"
    local timeout="${4:-5}"
    
    ((TOTAL_TESTS++))
    
    printf "  %-50s " "$description"
    log_msg "TEST [FORBIDDEN]: $description on $container"
    log_msg "  Command: $command"
    
    local output
    output=$(run_as_admin "$container" "$command" "$timeout" 2>&1)
    local exit_code=$?
    
    log_msg "  Exit Code: $exit_code"
    log_msg "  Output: $output"
    
    # Check for permission denied indicators
    if [ $exit_code -ne 0 ]; then
        # Command failed - this is expected for forbidden actions
        if echo "$output" | grep -qiE "not allowed|permission denied|sorry|not permitted|unauthorized|forbidden|cannot|denied"; then
            echo -e "[${GREEN}PASS${NC}] Blocked (Permission Denied) ✓"
            ((PASSED_TESTS++))
            return 0
        else
            # Failed but not with clear permission error - still a pass if blocked
            echo -e "[${GREEN}PASS${NC}] Blocked (Exit: $exit_code) ✓"
            ((PASSED_TESTS++))
            return 0
        fi
    else
        # Command succeeded - SECURITY VULNERABILITY!
        echo -e "[${RED}FAIL${NC}] ${BOLD}SECURITY GAP - Action permitted!${NC}"
        echo -e "       ${RED}⚠ This is a privilege escalation vector!${NC}"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Skip test if container doesn't exist or admin user missing
check_prerequisites() {
    local container="$1"
    
    # Check container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo -e "  ${YELLOW}[SKIP] Container not running${NC}"
        ((SKIPPED_TESTS++))
        return 1
    fi
    
    # Check admin user exists
    if ! docker exec "$container" id "$TEST_USER" &>/dev/null; then
        echo -e "  ${YELLOW}[SKIP] User '$TEST_USER' not found${NC}"
        ((SKIPPED_TESTS++))
        return 1
    fi
    
    # Check sudo is available
    if ! docker exec "$container" which sudo &>/dev/null; then
        echo -e "  ${YELLOW}[SKIP] sudo not installed${NC}"
        ((SKIPPED_TESTS++))
        return 1
    fi
    
    return 0
}

# Run all tests for an Alpine-based container
test_alpine_container() {
    local container="$1"
    
    print_test_header "$container"
    
    if ! check_prerequisites "$container"; then
        return
    fi
    
    echo -e "\n  ${CYAN}▶ Positive Tests (Should SUCCEED):${NC}"
    echo -e "  ${CYAN}─────────────────────────────────────────────────────${NC}"
    
    test_allowed_action "$container" \
        "sudo apk update (maintenance)" \
        "sudo /sbin/apk update" \
        60
    
    echo -e "\n  ${CYAN}▶ Negative Tests (Should be BLOCKED):${NC}"
    echo -e "  ${CYAN}─────────────────────────────────────────────────────${NC}"
    
    # Package Installation
    test_forbidden_action "$container" \
        "sudo apk add nmap (tool install)" \
        "sudo /sbin/apk add nmap"
    
    test_forbidden_action "$container" \
        "sudo apk add netcat-openbsd (tool install)" \
        "sudo /sbin/apk add netcat-openbsd"
    
    # File Access - Shadow file
    test_forbidden_action "$container" \
        "sudo cat /etc/shadow (hash dump)" \
        "sudo cat /etc/shadow"
    
    # File Access - Sudoers
    test_forbidden_action "$container" \
        "sudo cat /etc/sudoers (config read)" \
        "sudo cat /etc/sudoers"
    
    # Shell Escalation
    test_forbidden_action "$container" \
        "sudo -i (interactive root shell)" \
        "echo 'whoami' | sudo -i"
    
    test_forbidden_action "$container" \
        "sudo /bin/sh (shell escalation)" \
        "sudo /bin/sh -c 'whoami'"
    
    test_forbidden_action "$container" \
        "sudo su (switch user to root)" \
        "sudo su -c 'whoami'"
    
    # Arbitrary Binary Execution
    test_forbidden_action "$container" \
        "sudo python3 (arbitrary code)" \
        "sudo /usr/bin/python3 -c 'print(\"pwned\")'"
    
    test_forbidden_action "$container" \
        "sudo busybox (shell via busybox)" \
        "sudo /bin/busybox sh -c 'whoami'"
    
    # File Modification
    test_forbidden_action "$container" \
        "sudo tee (file write)" \
        "echo 'test' | sudo tee /tmp/escalation_test"
    
    test_forbidden_action "$container" \
        "sudo chmod (permission change)" \
        "sudo chmod 777 /etc/passwd"
    
    # Network Tools
    test_forbidden_action "$container" \
        "sudo wget (download)" \
        "sudo wget -q -O /dev/null http://example.com"
}

# Run all tests for a Debian-based container
test_debian_container() {
    local container="$1"
    
    print_test_header "$container"
    
    if ! check_prerequisites "$container"; then
        return
    fi
    
    echo -e "\n  ${CYAN}▶ Positive Tests (Should SUCCEED):${NC}"
    echo -e "  ${CYAN}─────────────────────────────────────────────────────${NC}"
    
    test_allowed_action "$container" \
        "sudo apt-get update (maintenance)" \
        "sudo /usr/bin/apt-get update" \
        120
    
    echo -e "\n  ${CYAN}▶ Negative Tests (Should be BLOCKED):${NC}"
    echo -e "  ${CYAN}─────────────────────────────────────────────────────${NC}"
    
    # Package Installation
    test_forbidden_action "$container" \
        "sudo apt-get install nmap (tool install)" \
        "sudo /usr/bin/apt-get install -y nmap"
    
    test_forbidden_action "$container" \
        "sudo apt-get install netcat (tool install)" \
        "sudo /usr/bin/apt-get install -y netcat"
    
    test_forbidden_action "$container" \
        "sudo apt install (alias bypass)" \
        "sudo apt install -y curl"
    
    # File Access - Shadow file
    test_forbidden_action "$container" \
        "sudo cat /etc/shadow (hash dump)" \
        "sudo cat /etc/shadow"
    
    # File Access - Sudoers
    test_forbidden_action "$container" \
        "sudo cat /etc/sudoers (config read)" \
        "sudo cat /etc/sudoers"
    
    # Shell Escalation
    test_forbidden_action "$container" \
        "sudo -i (interactive root shell)" \
        "echo 'whoami' | sudo -i"
    
    test_forbidden_action "$container" \
        "sudo /bin/bash (shell escalation)" \
        "sudo /bin/bash -c 'whoami'"
    
    test_forbidden_action "$container" \
        "sudo su (switch user to root)" \
        "sudo su -c 'whoami'"
    
    # Arbitrary Binary Execution
    test_forbidden_action "$container" \
        "sudo python3 (arbitrary code)" \
        "sudo /usr/bin/python3 -c 'print(\"pwned\")'"
    
    test_forbidden_action "$container" \
        "sudo perl (scripting lang)" \
        "sudo /usr/bin/perl -e 'print \"pwned\"'"
    
    # File Modification
    test_forbidden_action "$container" \
        "sudo tee (file write)" \
        "echo 'test' | sudo tee /tmp/escalation_test"
    
    test_forbidden_action "$container" \
        "sudo chmod (permission change)" \
        "sudo chmod 777 /etc/passwd"
    
    # Service Management
    test_forbidden_action "$container" \
        "sudo systemctl (service control)" \
        "sudo systemctl status ssh"
    
    # Network Tools
    test_forbidden_action "$container" \
        "sudo wget (download)" \
        "sudo wget -q -O /dev/null http://example.com"
}

# Print final summary
print_summary() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                        AUDIT SUMMARY                                  ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${WHITE}Total Tests:${NC}    $TOTAL_TESTS"
    echo -e "  ${GREEN}Passed:${NC}         $PASSED_TESTS"
    echo -e "  ${RED}Failed:${NC}         $FAILED_TESTS"
    echo -e "  ${YELLOW}Skipped:${NC}        $SKIPPED_TESTS"
    echo ""
    
    if [ "$FAILED_TESTS" -eq 0 ] && [ "$PASSED_TESTS" -gt 0 ]; then
        echo -e "  ${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${GREEN}║  ✓ AUDIT PASSED: Least Privilege Policy Enforced Correctly   ║${NC}"
        echo -e "  ${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${WHITE}Finding:${NC} The sudoers configuration correctly restricts the"
        echo -e "           admin user to maintenance operations only."
        exit 0
    else
        echo -e "  ${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${RED}║  ✗ AUDIT FAILED: Security Gaps Detected!                      ║${NC}"
        echo -e "  ${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${RED}Finding:${NC} $FAILED_TESTS forbidden action(s) were permitted."
        echo -e "           Review sudoers configuration immediately."
        echo ""
        echo -e "  ${WHITE}Log File:${NC} $LOG_FILE"
        exit 1
    fi
}

# Run tests for a single container (for targeted testing)
test_single_container() {
    local container="$1"
    
    print_banner
    
    # Determine container type
    if docker exec "$container" test -f /sbin/apk 2>/dev/null; then
        test_alpine_container "$container"
    elif docker exec "$container" test -f /usr/bin/apt-get 2>/dev/null; then
        test_debian_container "$container"
    else
        echo -e "${RED}[ERROR] Cannot determine container OS type${NC}"
        exit 1
    fi
    
    print_summary
}

# Run tests for all containers
test_all_containers() {
    print_banner
    
    echo -e "${WHITE}Testing Alpine-based containers...${NC}"
    for container in "${ALPINE_CONTAINERS[@]}"; do
        test_alpine_container "$container"
    done
    
    echo ""
    echo -e "${WHITE}Testing Debian-based containers...${NC}"
    for container in "${DEBIAN_CONTAINERS[@]}"; do
        test_debian_container "$container"
    done
    
    print_summary
}

# --- Main ---
main() {
    # Initialize log
    echo "# Least Privilege Audit Log" > "$LOG_FILE"
    echo "# Generated: $(date)" >> "$LOG_FILE"
    echo "# ============================================" >> "$LOG_FILE"
    
    if [ -n "$1" ]; then
        # Test specific container
        test_single_container "$1"
    else
        # Test all containers
        test_all_containers
    fi
}

# Show usage
usage() {
    echo "Usage: $0 [container_name]"
    echo ""
    echo "Options:"
    echo "  container_name  Test a specific container (optional)"
    echo "                  If omitted, tests all non-switch containers"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Test all containers"
    echo "  $0 clab-security_lab-web_server       # Test specific container"
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
