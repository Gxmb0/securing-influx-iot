# Methodology

This document describes the lab environment, its architecture, the software stack, and the testing methodology used throughout the project. It is written to be reproducible: another researcher with VMware Workstation Pro and the listed ISOs/images should be able to rebuild this environment from scratch.

## 1. Environment

| Component | Specification |
|---|---|
| Hypervisor | VMware Workstation Pro (Windows/Linux host) |
| Host resources allocated | 16 GB RAM, ~150 GB storage across all VMs |
| Guest count | 4 virtual machines |

## 2. Network topology

```
                    ┌──────────────────┐
                    │   Kali-Attacker   │  VMnet2 (Attack segment)
                    │  192.168.20.10    │
                    └────────┬──────────┘
                             │
                    ┌────────┴──────────┐
                    │      pfSense       │  WAN: NAT (VMnet8)
                    │ (router/firewall/  │  LAN: VMnet2  → 192.168.20.1
                    │  Suricata IDS)     │  OPT1: VMnet3 → 192.168.30.1
                    └────────┬───────────┘
                             │
              ┌──────────────┼──────────────┐
              │                             │
     ┌────────┴─────────┐         ┌─────────┴────────┐
     │   SIEM-Monitor     │         │     IoT-Sim        │
     │  192.168.30.10      │         │  192.168.30.20      │
     │  (Wazuh manager)    │         │  (simulated devices)│
     └──────────────────────┘         └─────────────────────┘
                VMnet3 (IoT / Monitoring segment, 192.168.30.0/24)
```

**Design rationale.** The attacker (Kali) and the protected assets (IoT-Sim, SIEM-Monitor) are placed on physically separate virtual network segments, connected only through pfSense. This mirrors a realistic network security posture — an IoT/OT segment isolated from a general-purpose or "internet-facing" segment — and, critically, forces all attack traffic to cross a routed, firewalled, and IDS-monitored boundary rather than sitting on a single flat broadcast domain. This is what makes the detection results in this project meaningful: Suricata is genuinely positioned as a network chokepoint, not incidentally sniffing local traffic.

## 3. Software stack

### pfSense (router / firewall / IDS host)
- pfSense Community Edition on FreeBSD 14.0
- Suricata 7.0.8, installed via the pfSense Package Manager
- Detection ruleset: **ETOpen Emerging Threats** (the free, community-maintained ruleset; no paid ETPro subscription was used)
- Enabled rule categories: `emerging-scan`, `emerging-exploit`, `emerging-web_client`, `emerging-web_server`, `emerging-telnet`
- EVE JSON alert logging enabled, written to `/var/log/suricata/<interface-instance>/eve.json`
- A Wazuh agent (v4.14.6, installed from the FreeBSD ports/pkg repository) configured to tail the EVE JSON log and forward events to the Wazuh manager

### SIEM-Monitor (Wazuh SIEM)
- Ubuntu Server 24.04 LTS
- Docker + Docker Compose
- Wazuh stack (manager, OpenSearch-based indexer, dashboard) deployed via the official `wazuh-docker` single-node Compose configuration, version **4.14.0**

### IoT-Sim (simulated IoT devices)
- Ubuntu Server 24.04 LTS, Docker
- Three containerized services, each chosen to represent a well-documented real-world IoT weakness:

| Service | Container | Port | Represents |
|---|---|---|---|
| MQTT broker | `eclipse-mosquitto`, unauthenticated | 1883 | The dominant IoT messaging protocol, very commonly deployed without access control |
| Vulnerable web admin panel | DVWA (`vulnerables/web-dvwa`) | 8080 → 80 | A device's web-based configuration/admin interface (e.g. an IP camera) |
| Open Telnet | BusyBox `telnetd` | 2323 → 23 | Default-credential Telnet access — the exact vector behind the Mirai botnet and its many derivatives |

### Kali-Attacker
- Stock Kali Linux (official VMware pre-built image)
- Tools used: `nmap`, `nikto`, `sqlmap`, `hydra`, `mosquitto-clients`, `tcpdump`

## 4. Build process summary

The lab was built incrementally, one VM at a time, with a working checkpoint required before proceeding to the next stage:

1. **VMware networking** — created two custom VMnets (VMnet2, VMnet3) as Host-only networks, alongside the default NAT network (VMnet8).
2. **pfSense** — installed, interfaces assigned (WAN/LAN/OPT1), static IPs configured, and firewall rules added (see §6 for a key gotcha here).
3. **Kali-Attacker** — imported from VMware's pre-built image, attached to the LAN/attack segment, static IP configured.
4. **SIEM-Monitor** — Ubuntu installed, Docker installed, Wazuh deployed via Compose.
5. **IoT-Sim** — Ubuntu installed, Docker installed, the three simulated device containers deployed.
6. **Suricata** — installed on pfSense, bound to the OPT1 interface (the boundary facing the protected IoT segment), ETOpen ruleset downloaded and relevant categories enabled.
7. **Wazuh agents** — deployed on both pfSense (to forward Suricata's EVE JSON alerts) and IoT-Sim (for host-level monitoring), completing the detection pipeline.

## 5. Detection pipeline

```
Attack traffic (Kali)
   → crosses pfSense's OPT1 interface
   → Suricata inspects against the ETOpen ruleset
   → matching traffic is logged as a JSON alert in eve.json
   → the Wazuh agent on pfSense tails eve.json and forwards events
   → the Wazuh manager (SIEM-Monitor) ingests, indexes, and displays the alert
   → analyst reviews the alert in the Wazuh dashboard's Discover view
```

IoT-Sim additionally runs its own Wazuh agent for independent host-level monitoring (file integrity, system logs), separate from the network-layer detection path above.

## 6. A note on operational realism

This project deliberately documents every configuration problem encountered during the build and testing process, rather than presenting only a clean, working end-state. Two issues in particular materially affected the results and are treated as first-class findings rather than footnotes:

- A **default `HOME_NET` misconfiguration** in Suricata silently prevented most detection signatures from ever matching for roughly the first half of the testing phase (see [REMEDIATION.md](./REMEDIATION.md)).
- **Suricata's EVE JSON log silently stalled** after growing to approximately 1.75 GB under sustained testing load, with the Suricata process itself remaining alive and showing no error — a genuine production-relevant operational risk, not merely a lab artifact.

Both are described in full, including how they were diagnosed, in [FINDINGS.md](./FINDINGS.md) and [REMEDIATION.md](./REMEDIATION.md).

## 7. Testing methodology

Each attack test followed a consistent procedure:

1. Confirm the target service is reachable and functioning before the test (avoids conflating "attack undetected" with "service was down").
2. Note the start time of the attack.
3. Run the attack from Kali-Attacker.
4. Check for a corresponding alert first in pfSense's local Suricata alert log, then in the Wazuh dashboard's Discover view, filtered by destination IP/port and, where useful, by signature ID.
5. Record the result — detected (with signature ID and detection latency where measurable) or not detected — in the metrics table in [FINDINGS.md](./FINDINGS.md), regardless of outcome.

Attack types were chosen to span a range of realistic IoT threat categories: network reconnaissance (port scanning), web application attack (SQL injection, automated vulnerability scanning), and IoT-protocol-specific abuse (unauthenticated MQTT pub/sub, Telnet credential brute-forcing).
