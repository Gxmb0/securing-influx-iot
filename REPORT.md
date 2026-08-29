# Securing the Massive Influx of Connected Devices: A Segmented IoT Testbed for Evaluating Open-Source Network Intrusion Detection

## Abstract

The rapid proliferation of consumer and industrial Internet of Things (IoT) devices has outpaced the security tooling designed to protect them. Many IoT devices ship with weak or absent authentication, run outdated software, and communicate over protocols — such as MQTT and Telnet — that fall outside the primary focus of general-purpose, enterprise-oriented intrusion detection rulesets. This project constructs a segmented virtual testbed comprising an attacker host, a router/firewall/intrusion-detection appliance (pfSense with Suricata), a Security Information and Event Management platform (Wazuh), and a simulated IoT host running three representative vulnerable services (an unauthenticated MQTT broker, a vulnerable web application, and an open Telnet service). Using only free, open-source tooling — including the community-maintained ETOpen Emerging Threats ruleset rather than any paid signature subscription — this project evaluates detection coverage across four realistic attack classes, identifies and resolves a significant network intrusion detection system (NIDS) misconfiguration, develops and validates a custom detection rule for an uncovered protocol, and reports a final measured detection rate of 75% along with a documented, unresolved detection gap. The project additionally surfaces two operationally significant findings unrelated to signature coverage: a scoping misconfiguration common enough to be independently documented across multiple community support threads, and a previously unreported log-rotation failure mode in sustained Suricata deployments.

## 1. Introduction

### 1.1 Motivation

Estimates of connected IoT devices in active deployment run into the tens of billions, spanning consumer smart-home products, industrial sensors, and networked infrastructure equipment. This scale, combined with historically poor security practices in IoT firmware and deployment defaults — default credentials, unauthenticated management protocols, and infrequent patching — has made IoT devices a persistent and growing attack surface. The Mirai botnet and its many derivatives remain the canonical demonstration of this risk: a worm that propagated almost entirely by trying a short list of default Telnet credentials against internet-facing devices, at a scale sufficient to disrupt major internet infrastructure.

Security teams increasingly deploy network intrusion detection systems (NIDS) and centralized log analysis (SIEM) platforms to gain visibility into this traffic. However, the signature rulesets underlying most open-source NIDS deployments — including the widely-used Emerging Threats ruleset this project evaluates — were developed primarily around enterprise network traffic patterns: web servers, mail servers, and general TCP/IP scanning and exploitation. It is not obvious, without direct testing, how well this tooling generalizes to IoT-specific protocols and attack patterns.

### 1.2 Research question

This project asks a narrow, empirically answerable question: **using only free and open-source detection tooling, what fraction of realistic attacks against a small set of representative vulnerable IoT services are actually detected, and what specific factors determine success or failure?**

### 1.3 Scope and contributions

This is a hands-on, lab-based evaluation rather than a large-scale empirical study; its contribution is not statistical generality but a detailed, reproducible, and honestly-reported case study. Specifically, this project contributes:

1. A reproducible, segmented IoT security testbed architecture, built entirely on freely available software (VMware Workstation Pro, pfSense, Suricata, Wazuh, Docker, and standard Linux/BSD tooling).
2. An empirical evaluation of detection coverage across four attack classes against three representative IoT service weaknesses.
3. The identification and remediation of a genuine, non-obvious NIDS misconfiguration (Suricata `HOME_NET` scoping under a segmented topology) that silently suppressed the majority of relevant detection signatures — a misconfiguration independently corroborated by multiple community support threads, suggesting it is not unique to this lab.
4. A custom detection rule for MQTT connection attempts, validated with before/after evidence, addressing a protocol coverage gap in the default ruleset.
5. A transparent report of an unresolved detection gap (Telnet brute-force detection against a minimal `telnetd` implementation) including the diagnostic steps taken and the most plausible remaining explanation, offered as a direction for future work rather than a false claim of resolution.
6. The identification of an operational risk — silent log-write stalling once Suricata's EVE JSON output file grows large under sustained load — with direct relevance to production deployments, not just this lab.

## 2. Related context

Open-source network intrusion detection based on signature matching (Suricata, and its predecessor/sibling project Snort) is a mature, widely deployed technology, and the Emerging Threats ruleset is one of the most widely used open community rulesets supporting it. Separately, a substantial body of industry and academic work has documented the weak security posture of consumer and industrial IoT devices, with the Mirai botnet frequently cited as the canonical example of Telnet-based default-credential compromise at internet scale. This project sits at the intersection of these two areas: rather than proposing new detection signatures from first principles or conducting a large-scale traffic study, it empirically tests whether an already-deployed, freely available detection stack — the kind a small organization or individual researcher would realistically stand up — provides meaningful coverage against IoT-specific attack patterns, and documents exactly where and why it does or does not.

## 3. Methodology

Full architectural and procedural detail is provided in [METHODOLOGY.md](./METHODOLOGY.md); this section summarizes the key points relevant to interpreting the results.

### 3.1 Testbed architecture

The testbed consists of four virtual machines under VMware Workstation Pro, connected across three virtual networks: a NAT network providing internet egress, an "attack" segment hosting a Kali Linux attacker host, and a "protected" segment hosting both the simulated IoT host and the Wazuh SIEM. A pfSense virtual appliance routes and firewalls between the attack and protected segments, and additionally hosts the Suricata NIDS at this boundary — meaning all attacker-to-victim traffic necessarily crosses a point of inspection, rather than being incidentally visible on a shared segment.

### 3.2 Simulated IoT services

Three containerized services were deployed on the IoT-Sim host, each chosen for its correspondence to a well-documented, real-world IoT weakness: an unauthenticated MQTT message broker (representing the dominant IoT messaging protocol, commonly deployed without access control), a deliberately vulnerable web application standing in for a device's web-based administrative interface, and an open Telnet service using a minimal (`BusyBox`) implementation with no meaningful authentication — directly analogous to the vector exploited by Mirai and its derivatives.

### 3.3 Detection stack

Suricata 7.0.8 was deployed on the pfSense appliance, bound to the network interface facing the protected segment, using the free ETOpen Emerging Threats ruleset — deliberately not the paid ETPro tier — since this reflects the realistic tooling budget of a small organization, student researcher, or hobbyist. Detected events are logged in Suricata's EVE JSON format and forwarded via a Wazuh agent to a Wazuh manager (SIEM) running the current 4.14.x release line, where they are indexed and made available for analysis through Wazuh's dashboard.

### 3.4 Attack test design

Four attack classes were tested, each mapped to a specific simulated service and chosen to span a range of realistic threat categories rather than exhaustively covering all possible IoT attacks:

1. **Network reconnaissance** — an Nmap SYN scan, representing basic attacker footprinting.
2. **Web application attack** — an automated vulnerability scan (Nikto) and an automated SQL injection tool (sqlmap) against the vulnerable web application, representing exploitation of a device's administrative web interface.
3. **MQTT protocol abuse** — unauthenticated publish/subscribe activity against the message broker, representing eavesdropping or unauthorized command injection in an IoT messaging context.
4. **Telnet credential brute-forcing** — an automated dictionary attack against the open Telnet service using a small set of well-known default credentials, directly modeled on the Mirai attack pattern.

For each test, the attack's start time was recorded, the attack was executed from the Kali attacker host, and detection was checked first against pfSense's local Suricata alert log and then against the Wazuh dashboard, filtered by the relevant destination IP, port, and (where a specific detection was expected) signature ID. Results — detected or not — were logged regardless of outcome, and negative results were investigated rather than discarded, which is what surfaced both major findings described in Section 4.

## 4. Results

Full per-test results, exact signature IDs, and supporting log excerpts are provided in [FINDINGS.md](./FINDINGS.md). This section summarizes the results and their significance.

### 4.1 Initial results: a near-total detection failure, and its cause

In the initial round of testing, an Nmap scan was correctly detected and specifically fingerprinted by Suricata. However, subsequent web application scanning (Nikto, both in default and vulnerability-focused tuning modes, generating over 8,000 requests across two runs) produced **no technique-specific detections at all** — only generic protocol- and stream-anomaly signatures fired, which carry essentially no analytical value for an incident responder (they do not indicate an attack occurred, merely that traffic of some non-standard shape was present).

Investigation of this near-total failure — rather than accepting it as "the ruleset just doesn't cover this" — revealed a specific, root-cause misconfiguration: Suricata's default `HOME_NET` variable, under this segmented topology, incorporated **both** the attacker's network segment and the protected segment, because pfSense's default behavior includes all directly-connected local networks. Since the substantial majority of Emerging Threats signatures require traffic to flow from an "external" to a "home" network to match, and the attacker traffic was — by this misconfigured definition — internal, essentially no directional signature could ever fire, regardless of how obviously malicious the traffic pattern was.

This finding is significant beyond this single lab: independent searches of pfSense/Suricata community support forums surfaced multiple, separately-reported instances of the same underlying confusion — that a standard Firewall alias cannot be directly selected as a custom `HOME_NET` in this pfSense package, and must instead be wrapped in a Suricata-specific "Pass List" construct, a UI/UX detail that is not obvious and is easy to get wrong. This suggests the misconfiguration identified here is a plausible, real risk in comparable production or research segmented-network deployments, not an artifact unique to this lab's specific setup.

### 4.2 Post-remediation detection performance

Following the `HOME_NET` fix (detailed in [REMEDIATION.md](./REMEDIATION.md)), the identical Nikto scan was re-run and produced an immediate, correctly-attributed, technique-specific alert. Subsequent testing of the web application attack surface using sqlmap produced the strongest result of the project: Suricata's alert not only matched a SQL-injection-specific signature, but the logged HTTP User-Agent field explicitly identified the tool as `sqlmap/1.9.4`, providing an incident responder with immediate, unambiguous attribution — a materially more actionable result than a generic anomaly flag.

MQTT abuse testing, in contrast, produced no detection using the default ETOpen ruleset even after the `HOME_NET` fix — consistent with ETOpen's limited built-in coverage for less common IoT-specific protocols. A custom Suricata rule was written to match the MQTT protocol's connection-request packet type, and after deployment, the identical MQTT test produced a correctly-attributed alert, closing this specific gap with directly comparable before/after evidence.

Telnet brute-force detection was tested last and is reported as an **unresolved gap**. A default-credential dictionary attack using a small, realistic credential list (mirroring the kind used by Mirai) produced no alert despite the relevant Emerging Threats signature — explicitly referencing Mirai-style BusyBox brute-forcing and including the tested port in its port list — being confirmed present and enabled. Packet capture analysis of the actual attack traffic revealed that the minimal `BusyBox telnetd` implementation used in this lab does not behave like the more full-featured Telnet servers (e.g., Cisco network equipment) that Emerging Threats' Telnet category signatures were evidently written against — it does not complete a standard login-prompt exchange under a rapid automated connection pattern, instead responding with a distinctive "Login timed out" message. A custom rule was written and deployed to match this observed pattern directly, and separately, an unrelated but genuinely significant infrastructure fault was discovered and corrected during this investigation (Section 4.3). Even against confirmed fresh, live event logging — verified in real time during a manual test — the custom Telnet rule did not fire. This is reported as a genuine, unresolved false negative rather than presented as a successful fix; the most plausible remaining explanation is discussed as a direction for future work in Section 5.

### 4.3 A secondary finding: silent log-pipeline failure under load

During the Telnet investigation, Suricata's EVE JSON alert log was found to have grown to approximately 1.75 gigabytes and to have silently stopped receiving new writes roughly 40 minutes prior — while the Suricata process itself remained alive, reported no error, and continued to show a "running" status in pfSense's management interface. This had invalidated multiple test attempts during that window without any visible indication that detection had effectively gone dark. Rotating the oversized log file and restarting the Suricata process on the affected interface restored logging, confirmed via live monitoring during a subsequent test.

This is reported as a first-class finding because it has direct relevance beyond this lab: any production or research deployment of Suricata with EVE JSON logging enabled, under sustained traffic or testing volume, is exposed to the same failure mode unless an explicit log-rotation policy is configured. The failure is particularly concerning from an operational-security standpoint precisely because it is silent — there is no crash, no error message, and no obviously actionable signal that detection capability has degraded.

### 4.4 Summary

| Metric | Result |
|---|---|
| Attack classes tested | 4 (reconnaissance, web application attack, MQTT abuse, Telnet brute-force) |
| Detected after all remediations | 3 of 4 (75%) |
| Root causes identified and fixed | 2 (HOME_NET scoping; a custom-rule content match derived directly from packet capture) |
| Custom detection rules developed | 2 (1 confirmed effective — MQTT; 1 unresolved — Telnet) |
| Secondary operational finding | 1 (EVE JSON log-rotation gap, silent failure mode) |

## 5. Discussion

The central finding of this project is not simply a detection rate, but a demonstration that **detection coverage in a free, open-source security stack is highly sensitive to configuration correctness, not just ruleset content**. The `HOME_NET` misconfiguration identified in Section 4.1 did not reflect any deficiency in the Emerging Threats ruleset itself — the relevant signatures existed and were well-formed — but a scoping error meant they were structurally incapable of matching the traffic pattern this lab's own topology generated. This is arguably a more actionable and generalizable finding for practitioners than a simple pass/fail coverage score would have been: it suggests that organizations deploying segmented networks with Suricata should specifically audit `HOME_NET`/`EXTERNAL_NET` scoping as a standard hardening step, rather than assuming default behavior correctly reflects their topology.

The successful MQTT remediation demonstrates that targeted, protocol-specific custom rules are a practical and low-effort way to close known gaps in general-purpose rulesets for organizations running IoT-specific protocols — a single, simply-constructed rule fully closed an identified detection gap.

The unresolved Telnet gap is, in the authors' view, the most intellectually interesting result of the project, precisely because it survived a genuine remediation attempt. It suggests that detecting attacks against minimal, non-standard service implementations (as is common in cheap or embedded IoT firmware, which frequently uses lightweight tools like BusyBox rather than full-featured daemons) may require detection logic more sophisticated than simple content matching — potentially involving Suricata's flow/stream-state tracking in ways not fully explored here, or protocol-aware parsing rather than raw byte matching. This is a legitimate limitation of the current work and a concrete direction for follow-up.

The EVE JSON log-rotation finding, while not related to detection signature coverage at all, is arguably of comparable practical importance: a detection system that silently stops detecting, with no operator-visible signal, arguably poses a greater operational risk than one with a known, documented coverage gap — the former creates false confidence, while the latter can at least be planned around.

## 6. Limitations

This project has several limitations, reported openly:

- **Scale.** This is a single-lab case study with a small number of attack tests per class, not a statistically powered evaluation. Results should be read as illustrative of specific, diagnosable phenomena, not as a general claim about ETOpen's coverage across the full space of IoT attacks.
- **False positive rate not measured.** A proper detection-system evaluation would also measure false positives against an idle-traffic baseline; this was identified as a needed follow-up but not completed within this project's scope.
- **Single implementation per protocol.** Only one MQTT broker implementation (Eclipse Mosquitto) and one Telnet implementation (BusyBox) were tested; results may not generalize to other implementations of the same protocols.
- **Unresolved gap.** The Telnet detection gap remains genuinely unresolved; the explanation offered in Section 5 is the most plausible candidate identified during investigation, not a confirmed root cause.

## 7. Conclusion

This project set out to answer a concrete question — does a freely available, open-source network detection stack meaningfully cover attacks against representative IoT service weaknesses? — through direct, hands-on testing rather than assumption. The answer is nuanced: coverage was strong for well-established attack patterns (scanning, web application attacks) once a significant but fixable configuration error was identified and corrected, adequate for a niche IoT protocol (MQTT) after a small amount of custom rule development, and genuinely insufficient, even after a targeted remediation attempt, for credential brute-forcing against a minimal IoT-style service implementation (Telnet). Alongside these signature-coverage findings, the project surfaced an operationally significant, silent log-pipeline failure mode with relevance well beyond this specific lab. Taken together, these results support a broader conclusion: securing the IoT attack surface with general-purpose, open-source tooling is achievable and cost-effective, but requires active configuration verification, targeted custom rule development for IoT-specific protocols, and deliberate operational hardening (such as log rotation) — it is not something that can be safely assumed to work correctly out of the box.

## Appendix: reproducibility

All configuration steps, exact commands, custom rule definitions, and supporting screenshots referenced in this report are provided in full in this repository — see [METHODOLOGY.md](./METHODOLOGY.md), [FINDINGS.md](./FINDINGS.md), [REMEDIATION.md](./REMEDIATION.md), and the `evidence/` directory.
