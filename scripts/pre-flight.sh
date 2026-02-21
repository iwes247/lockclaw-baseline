#!/usr/bin/env bash
# pre-flight.sh — Security gate for LockClaw Baseline
# Runs during container entrypoint BEFORE any application starts.
# Checks all listening ports against an allowlist and fails closed
# if any unauthorized port is detected.
#
# ⚠ SECURITY: This script MUST exit non-zero on violation.
# The main application process MUST NOT start if this fails.
set -euo pipefail

# ── Allowlist ────────────────────────────────────────────────
# Only these ports are permitted to be listening at pre-flight.
ALLOWLIST=(22 8080)

log() { echo "[pre-flight] $*"; }

# ── Discovery: find all listening TCP ports ──────────────────
# Uses ss -ltn (listening, TCP, numeric) from iproute2.
if ! command -v ss >/dev/null 2>&1; then
    log "FATAL: 'ss' not found. Install iproute2."
    exit 1
fi

RAW_OUTPUT=$(ss -ltn 2>/dev/null || true)

# ── Extraction: parse local port numbers ─────────────────────
# ss output formats for Local Address:Port:
#   0.0.0.0:22        — IPv4 all interfaces
#   127.0.0.1:8080    — IPv4 loopback
#   *:22              — all interfaces (wildcard)
#   [::]:22           — IPv6 all interfaces
#   [::1]:8080        — IPv6 loopback
#
# We extract the port number after the last colon.
mapfile -t LISTENING_PORTS < <(echo "$RAW_OUTPUT" \
    | tail -n +2 \
    | awk '{print $4}' \
    | sed -E 's/.*:([0-9]+)$/\1/' \
    | sort -un)

# ── Validation: compare against allowlist ────────────────────
VIOLATION=0

for port in "${LISTENING_PORTS[@]}"; do
    [ -z "$port" ] && continue
    AUTHORIZED=0
    for allowed in "${ALLOWLIST[@]}"; do
        if [ "$port" = "$allowed" ]; then
            AUTHORIZED=1
            break
        fi
    done

    if [ "$AUTHORIZED" -eq 0 ]; then
        log "SECURITY VIOLATION: Unauthorized port detected — :$port"
        VIOLATION=1
    fi
done

# ── Action: fail closed on any violation ─────────────────────
if [ "$VIOLATION" -ne 0 ]; then
    log "SECURITY VIOLATION: Unauthorized port detected"
    log "Allowed ports: ${ALLOWLIST[*]}"
    log "Container startup BLOCKED. Investigate and rebuild."
    exit 1
fi

# ── Proceed: all clear ───────────────────────────────────────
if [ "${#LISTENING_PORTS[@]}" -gt 0 ] && [ -n "${LISTENING_PORTS[0]}" ]; then
    log "OK — listening ports authorized: ${LISTENING_PORTS[*]}"
else
    log "OK — no ports listening at pre-flight (clean start)"
fi

exit 0
