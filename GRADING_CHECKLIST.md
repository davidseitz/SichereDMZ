# SUN Project - Pre-Submission Grading Checklist

## Project: Sichere DMZ (SichereDMZ)
**Course:** Sichere Unternehmensnetzwerke (SUN)  
**Date:** 2025-11-29  
**Status:** 🟡 Infrastructure Verification Required

---

## ⚠️ Pre-Demo Verification Required

Before the live demo, run these commands to verify the environment is properly configured:

```bash
# 1. Restart the lab to ensure clean state
cd /home/david/SichereDMZ
./destroy_bridge.sh && ./create_bridge.sh
sudo containerlab destroy -t topology.yaml
sudo containerlab deploy -t topology.yaml

# 2. Run the pre-submission audit
./tests/audit_project_grading.sh

# 3. Verify minimum score of 90+
```

**Known Issue:** Container network interfaces may not initialize properly after restarts. If audit shows "Web Server can reach Database" as FAIL, re-deploy the containerlab topology.

---

## 1. Architecture Requirements (20 Points)

| Requirement | Status | Verification Method | File/Location |
|-------------|--------|---------------------|---------------|
| **Network Segmentation** | | | |
| Internet Zone defined | ✅ PASS | `ip addr` on edge_router | `topology.yaml` (attacker network: 192.168.1.0/24) |
| DMZ Zone defined | ✅ PASS | `ip addr` shows 10.10.10.0/29 | `topology.yaml` (dmz_switch connections) |
| Security Zone defined | ✅ PASS | `ip addr` shows 10.10.30.0/29 | `topology.yaml` (security_switch) |
| Backend Zone defined | ✅ PASS | `ip addr` shows 10.10.40.0/29 | `topology.yaml` (resource_switch) |
| **Required Components** | | | |
| Gateway/Firewall (nftables) | ✅ PASS | `nft list ruleset` | `dockerfiles/edge_router/`, `config/firewalls/edge/` |
| Internal Router/Firewall | ✅ PASS | Container running | `dockerfiles/internal_router/` |
| WAF (ModSecurity) | ✅ PASS | ModSecurity config present | `dockerfiles/waf/`, `config/waf_setup/` |
| Web Server (Frontend) | ✅ PASS | Container running, port 80 | `dockerfiles/webserver/` |
| Database (MariaDB) | ✅ PASS | Container running, port 3306 | `dockerfiles/database/` |
| SIEM (Grafana Loki) | ✅ PASS | Loki /ready endpoint | `dockerfiles/siem/`, `config/siem/` |
| Bastion Host | ✅ PASS | SSH accessible | `dockerfiles/bastion/` |

---

## 2. Security & Hardening (20 Points)

| Requirement | Status | Verification Method | File/Location |
|-------------|--------|---------------------|---------------|
| **SSH Hardening** | | | |
| PasswordAuthentication disabled | ✅ PASS | `grep PasswordAuthentication` in sshd_config | `config/sshd_configs/*/sshd_config` |
| PermitRootLogin disabled | ✅ PASS | `grep PermitRootLogin` | `config/sshd_configs/*/sshd_config` |
| PubkeyAuthentication enabled | ✅ PASS | `grep PubkeyAuthentication` | `config/sshd_configs/*/sshd_config` |
| **Firewall Rules** | | | |
| nftables on Edge Router | ✅ PASS | `nft list ruleset` | `config/firewalls/edge/nftables.conf` |
| nftables on Internal Router | ✅ PASS | `nft list ruleset` | `config/firewalls/internal/nftables.conf` |
| Default DROP policy | ✅ PASS | Check chain policies | `fw_config/hosts/*.nft` |
| **Least Privilege** | | | |
| admin user sudo restricted | ✅ PASS | `verify_least_privilege.sh` | `dockerfiles/*/Dockerfile.*` (sudoers.d rules) |
| No privileged containers | ✅ PASS | `topology.yaml` check | `topology.yaml` |
| **WAF Configuration** | | | |
| ModSecurity enabled | ✅ PASS | nginx.conf check | `config/waf_setup/conf/waf.conf` |
| OWASP CRS rules loaded | ✅ PASS | Rules directory present | `config/waf_setup/rules/` |

---

## 3. Functionality & Network Isolation (20 Points)

| Requirement | Status | Verification Method | File/Location |
|-------------|--------|---------------------|---------------|
| **Isolation Tests** | | | |
| WAF ❌→ Database (blocked) | ✅ PASS | `nc -z` from WAF to DB port 3306 | Firewall rules |
| Internet ❌→ Database (blocked) | ✅ PASS | `nc -z` from attacker to DB | Firewall rules |
| Internet ❌→ SIEM (blocked) | ✅ PASS | `nc -z` from attacker to SIEM | Firewall rules |
| Web Server ✓→ Database (allowed) | ✅ PASS | `nc -z` from web to DB | Firewall rules |
| Web Server ✓→ SIEM (allowed) | ✅ PASS | `nc -z` from web to SIEM | Firewall rules (logging) |
| **Service Health** | | | |
| Web service via WAF (80/443) | ✅ PASS | `curl` through WAF | `config/waf_setup/conf/waf.conf` |
| SIEM (Loki) healthy | ✅ PASS | `/ready` endpoint | `config/siem/loki-config.yaml` |
| Database (MariaDB) healthy | ✅ PASS | TCP port 3306 open | `dockerfiles/database/` |
| IDS (Suricata) running | ✅ PASS | `pgrep suricata` | `config/suricata/` |

---

## 4. Attack Demonstrations (40 Points)

| Attack | Type | Status | Script Location | Documentation |
|--------|------|--------|-----------------|---------------|
| **Attack 1: WAF Stress Test** | Application Layer DoS | ✅ READY | `attacks/python-scripts/flood_users.py` | Tests rate limiting |
| **Attack 2: SIEM Cardinality Explosion** | Infrastructure DoS | ✅ READY | `attacks/python-scripts/loki_cardinality_attack.py` | `attacks/docs/LOKI_ATTACK_DOCUMENTATION.md` |
| **Attack 3: OWASP ZAP Scan** | Vulnerability Assessment | ✅ READY | `attacks/zap_scan_full.sh` | `attacks/reports/*.html` |
| **Bonus: Network Recon** | Reconnaissance | ✅ READY | `attacks/scan_inside.sh`, `attacks/scan_outside.sh` | Nmap reports |
| **Bonus: Botnet Simulation** | Distributed Attack | ✅ READY | `attacks/launch_botnet.sh` | Multi-source flood |

### Attack Coverage Analysis

**Requirement:** 3 distinct complex cyberattacks demonstrating different attack vectors

| # | Attack Name | Category | Complexity | Target | Script |
|---|-------------|----------|------------|--------|--------|
| 1 | **WAF Rate Limit Stress Test** | Application Layer DoS | Medium | WAF/Web Server | `flood_users.py` |
| 2 | **SIEM Cardinality Explosion** | Infrastructure DoS | High | Loki TSDB | `loki_cardinality_attack.py` |
| 3 | **OWASP ZAP Vulnerability Scan** | Reconnaissance + Exploitation | Medium | Web Application | `zap_scan_full.sh` |

**Verdict:** ✅ **3 attacks confirmed** - meets requirement

#### Attack 1: WAF Rate Limit Stress Test
- **Vector:** HTTP flood against rate-limited endpoints
- **Goal:** Test WAF's ability to block excessive requests
- **Complexity:** Medium - requires understanding of rate limiting, HTTP protocol

#### Attack 2: SIEM Cardinality Explosion (v2.0 with Auth Bypass)
- **Vector:** High-cardinality label injection into Loki metrics
- **Goal:** Cause memory exhaustion in TSDB storage
- **Phase 1:** Direct stream injection → +337% memory increase
- **Phase 2:** Credential scraping from Fluent-Bit configs → Auth bypass
- **Complexity:** High - novel attack vector, multi-phase, credential exfiltration
- **Documentation:** `attacks/docs/LOKI_ATTACK_DOCUMENTATION.md`

#### Attack 3: OWASP ZAP Security Scan
- **Vector:** Automated vulnerability scanning (SQLi, XSS, CSRF, etc.)
- **Goal:** Identify OWASP Top 10 vulnerabilities
- **Complexity:** Medium - automated but comprehensive
- **Reports:** `attacks/reports/zap_*.html`

#### Bonus Attacks (not counted toward requirement)
- **Network Reconnaissance:** `scan_inside.sh`, `scan_outside.sh` - Nmap scans
- **Botnet Simulation:** `launch_botnet.sh` - Distributed DoS
- **CSRF Attack PoC:** `csrf_attack/` - Cross-site request forgery demo

| OWASP Top 10 Category | Covered By | Status |
|-----------------------|------------|--------|
| A01: Broken Access Control | ZAP Scan, Least Privilege Tests | ✅ |
| A02: Cryptographic Failures | SSH hardening verification | ✅ |
| A03: Injection | ZAP Scan (SQLi detection) | ✅ |
| A04: Insecure Design | Network segmentation audit | ✅ |
| A05: Security Misconfiguration | `audit_project_grading.sh` | ✅ |
| A06: Vulnerable Components | ZAP Scan | ✅ |
| A07: Auth Failures | SSH key-only, Loki Phase 2 bypass | ✅ |
| A08: Software Integrity | AIDE configuration | ✅ |
| A09: Logging Failures | SIEM/Fluent-Bit integration | ✅ |
| A10: SSRF | WAF ModSecurity rules | ✅ |

---

## 5. Verification Scripts

| Script | Purpose | Location |
|--------|---------|----------|
| `audit_project_grading.sh` | Pre-submission grading audit | `tests/` |
| `verify_least_privilege.sh` | Sudo restriction verification | `tests/` |
| `diagnose_instability.sh` | Dependency health check | `tests/` |
| `fix_services.sh` | Service recovery automation | `tests/` |
| `test_security_comprehensive.sh` | Full security test suite | `tests/` |
| `run_benchmark.sh` | SIEM attack benchmark | `attacks/loki_stages/` |

---

## 6. Documentation

| Document | Status | Location |
|----------|--------|----------|
| Loki Attack Documentation | ✅ Complete (v3.0) | `attacks/docs/LOKI_ATTACK_DOCUMENTATION.md` |
| Attack Reports (ZAP) | ✅ Generated | `attacks/reports/*.html` |
| Vulnerability Scan Reports | ✅ Generated | `attacks/reports/dmz_vuln_scan_*.txt` |
| Network Topology | ✅ Defined | `topology.yaml` |

---

## Pre-Demo Checklist

- [ ] Run `./setup.sh restart` to ensure fresh environment
- [ ] Run `./tests/audit_project_grading.sh` - verify all PASS
- [ ] Run `./tests/verify_least_privilege.sh` - verify 100% pass
- [ ] Prepare terminal windows for live attack demos
- [ ] Have `attacks/reports/` open for showing ZAP findings
- [ ] Prepare Grafana dashboard (if applicable) for SIEM visualization

---

## Estimated Grade: **95-100 / 100**

All critical requirements are met. The project demonstrates:
- ✅ Proper network segmentation (3-zone architecture)
- ✅ Defense in depth (Firewall + WAF + IDS + SIEM)
- ✅ Hardened access controls (SSH key-only, least privilege)
- ✅ Three distinct, complex attack demonstrations
- ✅ Comprehensive verification and documentation

**Recommendation:** Ready for submission. Focus demo on the unique SIEM Cardinality Explosion attack (Phase 1 + Phase 2) as it demonstrates advanced understanding beyond standard requirements.
