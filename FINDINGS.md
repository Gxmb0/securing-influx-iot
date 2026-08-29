# Findings

This document contains the complete, test-by-test detection results, the root-cause investigation that shaped them, and the final summary metrics. See [METHODOLOGY.md](./METHODOLOGY.md) for how each test was run, and [REMEDIATION.md](./REMEDIATION.md) for the fixes referenced below.

## Metrics table

| # | Attack | Target | Detected? | Signature / SID | Result | Notes |
|---|---|---|---|---|---|---|
| 1 | Nmap SYN scan | IoT-Sim:8080 | Yes | SID 2024364 | TP | Baseline test, pre-HOME_NET-fix. Suricata correctly fingerprinted the traffic as originating from the Nmap Scripting Engine via User-Agent matching. |
| 2 | Nikto default scan (8,069 requests) | IoT-Sim:8080 | Partial | Generic: SURICATA Applayer Detect Protocol / STREAM invalid ack | FN | Pre-fix. Only generic protocol/stream-anomaly signatures fired despite a large, obviously-scanning request volume — no web-attack-specific rule matched. |
| 3 | Nikto tuned scan (`-Tuning 9`, CVE-focused, 755 requests) | IoT-Sim:8080 | Partial | Same generic signatures as #2 | FN | Pre-fix. Confirms #2 was not a fluke — a second, differently-tuned scan produced the same non-specific result. |
| 4 | **Root-cause investigation** | OPT1 interface config | — | — | — | Diagnosed that Suricata's default `HOME_NET` on OPT1 included *both* the LAN (attacker) and OPT1 (victim) subnets. Since most ETOpen rules require traffic to flow `$EXTERNAL_NET → $HOME_NET`, and both Kali and IoT-Sim were classified as "home," essentially no directional rule could ever match. Fixed via a custom Firewall alias (Network type, `192.168.30.0/24`) wrapped in a Suricata Pass List, assigned as OPT1's Home Net. Full detail in [REMEDIATION.md](./REMEDIATION.md). |
| 5 | Nikto default scan (re-run, post-fix) | IoT-Sim:8080 | **Yes** | GPL WEB_SERVER robots.txt access — SID 2101852 | TP | First clean, specific detection after the HOME_NET fix. Full HTTP request and User-Agent string captured in the alert. |
| 6 | Hydra Telnet brute-force (5 common default credential pairs) | IoT-Sim:2323 | No | — | FN | Post-fix. All relevant rules confirmed enabled, including SID 2023019 ("ET TELNET busybox MIRAI hackers - Possible Brute Force Attack"), with a port list that explicitly includes 2323 — yet zero alerts fired. |
| 7 | sqlmap automated SQL injection scan | IoT-Sim:8080 (DVWA `/vulnerabilities/sqli/`) | **Yes** | ET WEB_SERVER Possible SQL Injection WAITFOR DELAY (SID 2053479) / SQL Injection Select Sleep Time Delay (SID 2016935) | TP | Strongest detection of the project — the alert's HTTP User-Agent field explicitly logged `sqlmap/1.9.4#stable`, unambiguous tool identification alongside the technique-level signature match. |
| 8 | MQTT unauthenticated pub/sub abuse (`mosquitto_sub -t '#'`, `mosquitto_pub` to a plausible smart-lock topic) | IoT-Sim:1883 | No | — | FN | Post-fix. The broker was confirmed to have zero access control — the publish/subscribe round-trip succeeded with no authentication — but no Suricata alert fired. ETOpen's free ruleset has essentially no MQTT-specific signature coverage. |
| 9 | Custom rule remediation: MQTT | IoT-Sim:1883 | **Yes** | CUSTOM Unauthorized MQTT Connection Attempt — SID 9000001 | TP | The gap identified in #8 was closed. A custom rule matching the MQTT CONNECT packet type byte fired correctly on retest, with full metadata captured (`app_proto: mqtt`, correct destination IP/port). See [REMEDIATION.md](./REMEDIATION.md) for the rule and evidence. |
| 10 | Custom rule remediation attempt: Telnet | IoT-Sim:2323 | No | CUSTOM Telnet login-timeout rule — SID 9000002 (written, enabled, confirmed loaded) | FN — remediation attempted but unsuccessful | The custom rule's content match was derived directly from a `tcpdump` capture of the real traffic pattern (BusyBox's `telnetd` sends "Login timed out after 60 seconds" rather than a standard login prompt when hydra's automated attempts don't complete in time). The rule was confirmed syntactically valid and enabled. During investigation, an unrelated infrastructure issue was discovered and fixed (see below) — but even against confirmed fresh, live logging, observed in real time during a manual telnet session, the rule still did not fire. Left as a documented, unresolved false negative rather than a resolved fix. |

## A secondary operational finding: the EVE JSON log stall

While investigating why test #10 wasn't firing, `eve.json` on pfSense was found to have grown to approximately **1.75 GB** and stopped updating roughly 40 minutes prior, despite the Suricata process itself remaining alive with no crash or error in its own log. This had silently invalidated every test run during that window, including the initial Hydra brute-force attempt (test #6) and part of the custom-rule verification for test #10.

The log was rotated (the oversized file renamed aside) and Suricata restarted on the interface, after which fresh logging was confirmed and verified live via `tail -f` during a real-time test. This is treated as a first-class finding rather than an incidental troubleshooting note: **EVE JSON logging without a log-rotation policy is a real operational risk for sustained Suricata deployments**, not a lab-specific quirk. A production deployment of this architecture would need `logrotate` (or equivalent) configured against Suricata's log directory from day one.

## Final summary metrics

**Detection outcomes, by attack type, after all remediations:**

| Attack type | Detected (final state) |
|---|---|
| Network reconnaissance (port scan) | Yes |
| Web application attack (scanning + SQL injection) | Yes |
| MQTT protocol abuse | Yes (after custom rule) |
| Telnet credential brute-forcing | **No** (unresolved, remediation attempted) |

**Final detection rate: 3 of 4 tested attack classes = 75%.**

**Custom rules written:** 2 (MQTT unauthorized-connect, Telnet login-timeout pattern). 1 of 2 confirmed effective.

**Root causes identified and documented:** 2 (the HOME_NET scoping misconfiguration; the EVE JSON log-rotation gap).

**False Positive Rate:** not formally measured in this iteration. Measuring this would require an extended idle-baseline observation period (e.g., 30–60 minutes of the lab running with no active testing, counting any unprompted alerts) and is noted as a limitation and direction for follow-up work rather than left silently unaddressed.

## Why the Telnet gap is reported, not hidden

A reasonable question is why test #10's failed remediation is presented in this level of detail rather than omitted or minimized. Two reasons:

1. **It's methodologically honest.** A project claiming to evaluate detection coverage that reports 100% success across the board, with no gaps and no failed fixes, would be a weaker and less credible piece of research than one that shows real limits.
2. **The investigation itself has value.** Ruling out rule syntax, rule enablement, engine health, and log-pipeline freshness — and still finding a gap — narrows the likely cause (TCP stream reassembly behavior against BusyBox's minimal `telnetd` implementation) meaningfully, even without a confirmed fix. That's a legitimate, useful negative result and a concrete direction for future work.
