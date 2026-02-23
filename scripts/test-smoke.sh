#!/usr/bin/env bash
set -euo pipefail

# LockClaw Baseline — v1 smoke tests

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }
note() { echo "NOTE: $*"; }

LOCKCLAW_HOME="${LOCKCLAW_HOME:-/opt/lockclaw}"
CORE_DIR="${LOCKCLAW_HOME}/lockclaw-core"
MODE="${LOCKCLAW_MODE:-hobby}"

RUNTIME="none"
if command -v openclaw >/dev/null 2>&1; then
    RUNTIME="openclaw"
elif command -v ollama >/dev/null 2>&1; then
    RUNTIME="ollama"
fi

if [ -r /proc/uptime ]; then
    awk '{ if ($1 > 0) exit 0; exit 1 }' /proc/uptime || fail "system uptime invalid"
    pass "container running"
else
    fail "cannot verify container state"
fi

if id lockclaw >/dev/null 2>&1; then
    pass "lockclaw user exists"
else
    fail "lockclaw user missing"
fi

if [ -f "${CORE_DIR}/policies/modes/${MODE}.json" ]; then
    pass "mode policy exists (${MODE})"
else
    fail "mode policy missing (${MODE})"
fi

ROOT_MOUNT="$(awk '$2=="/"{print $4}' /proc/mounts | head -1)"
if [[ ",$ROOT_MOUNT," == *,ro,* ]]; then
    pass "root filesystem read-only"
else
    fail "root filesystem is not read-only"
fi

if [ -d /data ] && [ -w /data ]; then
    pass "/data writable"
else
    fail "/data missing or not writable"
fi

NO_NEW_PRIVS="$(awk '/^NoNewPrivs:/{print $2}' /proc/1/status)"
if [ "$NO_NEW_PRIVS" = "1" ]; then
    pass "no-new-privileges enabled"
else
    fail "no-new-privileges not enabled"
fi

if [ -x "${CORE_DIR}/audit/port-check.sh" ]; then
    "${CORE_DIR}/audit/port-check.sh" --profile container || fail "port-check failed"
    pass "port allowlist audit"
else
    fail "core port-check.sh missing"
fi

if [ -x "${CORE_DIR}/audit/pre-flight.sh" ]; then
    "${CORE_DIR}/audit/pre-flight.sh" --mode "$MODE" || fail "pre-flight failed"
    pass "pre-flight gate"
else
    fail "core pre-flight.sh missing"
fi

if [ "$RUNTIME" = "openclaw" ] || [ "$RUNTIME" = "ollama" ] || [ "$RUNTIME" = "none" ]; then
    pass "runtime detected: $RUNTIME"
fi

echo ""
echo "Smoke tests completed."
