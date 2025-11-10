# Networks

| Network Name          | Mode     | Subnet           | Gateway (router VM)     | DHCP Range (set in firewall VM) | Notes                                                      |
| --------------------- | -------- | ---------------- | ----------------------- | ------------------------------- | ---------------------------------------------------------- |
| **Internet (WAN)**    | NAT      | 192.168.123.0/24 | 192.168.123.1 (libvirt) | DHCP from libvirt (leave ON)    | pfSense/Edge Router WAN will get IP here; NAT out via host |
| **DMZ**               | Isolated | 10.0.10.0/29     | 10.0.10.1               | 10.0.10.2 – 10.0.10.6           | /29 → up to 6 usable IPs (enough for 5 servers + gateway)  |
| **Internal-Client**   | Isolated | 10.0.20.0/24     | 10.0.20.1               | 10.0.20.10 – 10.0.20.250        | /24 → up to 254 usable IPs (enough for 240 clients)        |
| **Internal-Resource** | Isolated | 10.0.30.0/29     | 10.0.30.1               | 10.0.30.2 – 10.0.30.6           | /29 → up to 6 usable IPs                                   |
| **Internal-Security** | Isolated | 10.0.40.0/29     | 10.0.40.1               | 10.0.40.2 – 10.0.40.6           | /29 → up to 6 usable IPs                                   |
