#!/bin/bash
# Test 1: Network reconnaissance (baseline).
# Run from Kali-Attacker (192.168.20.10) against IoT-Sim (192.168.30.20).
# Expected detection: SID 2024364 (Nmap Scripting Engine fingerprint).

nmap -sS -p 1883,8080,2323 192.168.30.20
