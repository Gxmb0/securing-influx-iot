# Remediation

This document details the two significant fixes applied during the project, the reasoning behind each, and the evidence that they worked (or, for Telnet, why the attempted fix did not resolve the gap).

## 1. Root cause: Suricata `HOME_NET` scoping

### Symptom

Both an initial and a tuned Nikto scan against the DVWA target (IoT-Sim, port 8080) produced only generic protocol/stream-anomaly alerts (`SURICATA Applayer Detect Protocol`, `SURICATA STREAM invalid ack`), despite thousands of scan requests and several rule categories relevant to web attacks (`emerging-web_server`, `emerging-exploit`) being confirmed enabled.

### Diagnosis

Inspecting one of the specific ETOpen rules expected to match (a Mirai-related brute-force rule, used later while investigating Telnet) revealed the rule's direction requirement: `$EXTERNAL_NET → $HOME_NET`. The majority of ETOpen's meaningful, technique-level signatures are written this way — they only fire on traffic crossing from an "external" to a "home" network, not on traffic that Suricata considers entirely internal.

pfSense's Suricata package documents its default `HOME_NET` behavior directly in its own settings page: *"Default Home Net adds only local networks, WAN IPs, Gateways, VPNs and VIPs."* Because both the attacker segment (`192.168.20.0/24`, Kali) and the victim segment (`192.168.30.0/24`, IoT-Sim) are directly-connected local networks on the same pfSense box, **both ended up inside the default `HOME_NET`**. From Suricata's perspective, Kali's attack traffic was never "external" — it was `$HOME_NET → $HOME_NET`, which the vast majority of ETOpen's directional rules simply do not match.

### Fix

pfSense does not accept a plain Firewall alias directly in Suricata's `HOME_NET` dropdown — this is a documented point of confusion in the pfSense/Suricata community (see references below). The correct procedure:

1. Create a **Network-type** Firewall alias containing only the protected segment:
   - Name: `IOT_HOMENET`
   - Type: Network(s)
   - Value: `192.168.30.0/24`
2. Create a **Suricata Pass List** (`Services → Suricata → Pass Lists`), name it (e.g. `IOT_HOMENET_LIST`), uncheck the default inclusions, and reference the `IOT_HOMENET` alias in its address field.
3. On the OPT1 interface's settings (`Services → Suricata → OPT1 → OPT1 Settings`), set **Home Net** to the new Pass List.
4. Save and restart Suricata on the OPT1 interface.
5. Verify via the "View HOME_NET" button that it now resolves to exactly `192.168.30.0/24` and `192.168.30.1/32` (pfSense's own protected-side interface address) — critically, **excluding** the `192.168.20.0/24` attacker segment.

### Evidence of effect

Before the fix, two independent Nikto runs (test #2 and #3 in [FINDINGS.md](./FINDINGS.md)) produced no technique-specific alerts. Immediately after the fix, re-running the identical Nikto scan (test #5) produced a specific, correctly-attributed alert:

```
GID:SID 1:2101852 — GPL WEB_SERVER robots.txt access
data.src_ip: 192.168.20.10 (Kali)
data.dest_ip: 192.168.30.20 (IoT-Sim)
data.dest_port: 8080
```

This same fix is also what enabled test #7 (sqlmap detection) and is a prerequisite for the MQTT custom rule (below) to have been testable in the first place.

## 2. Custom rule: MQTT unauthorized connection detection

### Rationale

ETOpen's free ruleset has essentially no MQTT-specific signatures — a reasonable gap, since MQTT is a comparatively niche protocol relative to HTTP/TCP scanning that most general-purpose IDS rulesets are optimized for. Since one of this project's simulated devices is an intentionally unauthenticated MQTT broker (representing a very common real-world IoT misconfiguration), a targeted custom rule was written to close this specific, relevant gap.

### Rule

```
alert tcp any any -> 192.168.30.20 1883 (msg:"CUSTOM Unauthorized MQTT Connection Attempt"; flow:to_server,established; content:"|10|"; offset:0; depth:1; sid:9000001; rev:1;)
```

This matches the MQTT protocol's CONNECT packet type (control packet type `1`, encoded as the byte `0x10` in the first byte of an MQTT fixed header) arriving at the broker's port. Any client establishing a new MQTT session — legitimate or not — will send this byte pattern, so this rule functions as a connection-attempt/reconnaissance detector, appropriate given the broker has no authentication layer to specifically violate.

### Deployment

Added via `Services → Suricata → OPT1 → Rules → Custom`, saved, and Suricata restarted on OPT1 to load it.

### Evidence of effect

Re-running the original MQTT test (`mosquitto_sub`/`mosquitto_pub` round-trip) after adding the rule produced an immediate, correctly-attributed alert:

```
GID:SID 1:9000001 — CUSTOM Unauthorized MQTT Connection Attempt
data.app_proto: mqtt
data.dest_ip: 192.168.30.20
data.dest_port: 1883
data.src_ip: 192.168.20.10
```

Full evidence, including the Wazuh Discover screenshot, is in `evidence/screenshots/`. The rule file is in `evidence/artifacts/detection-rules/custom.rules`.

## 3. Custom rule attempt: Telnet brute-force detection (unresolved)

### Rationale

Similarly to MQTT, ETOpen's `emerging-telnet` category is written primarily for enterprise/network-equipment Telnet implementations (its rule messages explicitly reference Cisco devices) and did not match traffic against a minimal BusyBox `telnetd` instance during a Hydra brute-force attempt (test #6).

### Investigation

A raw packet capture (`tcpdump -A`) of a Hydra brute-force attempt against the Telnet service revealed that BusyBox's `telnetd`, under the rapid, automated connection pattern Hydra generates, does not complete a normal login-prompt exchange — instead, it frequently responds with the literal text **"Login timed out after 60 seconds."** before the connection is torn down. This is a distinctive, if unconventional, fingerprint of automated brute-forcing against this specific minimal Telnet implementation.

### Rule (as deployed)

```
alert tcp any any -> 192.168.30.20 2323 (msg:"CUSTOM Telnet Rapid Brute-Force Pattern (Login Timeout)"; flow:to_client,established; content:"Login timed out"; sid:9000002; rev:2;)
```

### Outcome

The rule was confirmed present, enabled, and correctly formatted in Suricata's active SID list. During verification, it was discovered that Suricata's EVE JSON log had silently stalled after growing to ~1.75 GB (see [FINDINGS.md](./FINDINGS.md) for detail) — meaning earlier test attempts against this rule were not actually being evaluated against live logging at all. The log was rotated and Suricata restarted; fresh, live logging was confirmed via `tail -f` during a real-time manual Telnet session.

**Even with confirmed-live logging, the rule did not fire.** This is reported as an unresolved false negative. The most plausible remaining explanation, not yet confirmed, is that Suricata's TCP stream reassembly may be splitting BusyBox's response across segment boundaries in a way that defeats the simple `content` match, or that the message is being sent in a context (partial/aborted connection teardown) that isn't cleanly captured by the `flow:to_client,established` qualifier. This is documented as a direction for future work rather than papered over with an unverified claim of success.

## References

- pfSense Suricata package documentation (in-product): "Networks Suricata Should Inspect and Protect" — Home Net / External Net field descriptions.
- Netgate Community Forum: *"Suricata cannot change HOME NET list?"* and *"Suricata GUI package v3.0_6 for pfSense 2.3"* threads — both independently document that a raw Firewall alias is not selectable in Suricata's Home Net dropdown and must be wrapped in a Pass List.
- Eclipse Mosquitto / MQTT protocol specification (OASIS MQTT v3.1.1) — control packet type encoding, used to derive the custom MQTT rule's byte match.
