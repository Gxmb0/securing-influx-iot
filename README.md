# Securing the Massive Influx of Connected Devices

A hands-on network security research project that builds a segmented, containerized IoT testbed, deploys a network intrusion detection system (Suricata) and a SIEM (Wazuh), runs realistic attacks against simulated IoT devices, and evaluates — then improves — detection coverage using open-source tooling only.

## Why this project

Consumer and industrial IoT devices are frequently deployed with weak or no authentication, run outdated software, and expose protocols (Telnet, MQTT) that traditional enterprise-focused security tooling doesn't cover well out of the box. This project builds a small, realistic segmented network — one segment for the "attacker," one for "IoT devices" — and asks a concrete question: **does a free, open-source detection stack (Suricata + the ETOpen ruleset, fronting a Wazuh SIEM) actually catch attacks against IoT-style services, and where does it fall short?**

The answer, backed by logged evidence in this repo, is: partially — and the gaps are specific, diagnosable, and in one case fixable with a targeted custom rule.

## Repository structure

```
Securing-influx-iot/
│
├── README.md            — this file
├── METHODOLOGY.md        — lab architecture, build process, and test methodology
├── REPORT.md             — the full write-up (abstract, results, discussion, conclusion)
├── FINDINGS.md           — detailed per-test results and the metrics table
├── REMEDIATION.md        — root-cause fixes and custom detection rules, with before/after evidence
│
├── evidence/
│   ├── screenshots/      — dashboard, alert, and console screenshots supporting each finding
│   └── artifacts/
│       ├── scripts/          — attack scripts and commands used for each test
│       └── detection-rules/  — the custom Suricata rules written for this project
│
└── notes/                — working notes, raw logs, and scratch material
```

## Quick summary of results

- Built a 4-VM segmented lab on VMware Workstation Pro: pfSense (router/firewall/IDS), a Kali attack host, a Wazuh SIEM, and a simulated IoT host running three vulnerable services (MQTT broker, DVWA web app, open Telnet).
- Diagnosed and fixed a real IDS misconfiguration — Suricata's default `HOME_NET` variable included both the "attacker" and "victim" network segments, silently preventing the majority of detection signatures from ever matching.
- After the fix: **3 of 4 tested attack classes were detected** by the stock ETOpen ruleset (port scanning, web application attacks, and — after a custom rule — MQTT abuse). Telnet brute-forcing remained undetected even after a targeted remediation attempt, and that investigation is documented rather than hidden.
- Final measured detection rate: **75%**, with a full audit trail of what was tried, what worked, and what didn't.

See [REPORT.md](./REPORT.md) for the full write-up, [FINDINGS.md](./FINDINGS.md) for the raw test-by-test data, and [REMEDIATION.md](./REMEDIATION.md) for the fixes.

## Reproducing this lab

[METHODOLOGY.md](./METHODOLOGY.md) documents the full build from a bare VMware Workstation Pro installation through a working detection pipeline, including every configuration issue encountered and how it was resolved — useful both as a reproduction guide and as a record of realistic operational troubleshooting.

## Disclosure and ethics note

All testing in this project was conducted entirely within an isolated, locally-hosted virtual lab with no connection to production systems or third-party infrastructure. No real devices, networks, or data were involved. This repository is published for educational and research purposes.
