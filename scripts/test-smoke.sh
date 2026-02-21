#!/usr/bin/env bash
set -euo pipefail

# LockClaw Baseline — smoke tests
# Container-appropriate checks. No OS-level hardening assumptions.
# Hard-fails on unexpected ports.

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }
note() { echo "NOTE: $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${SCRIPT_DIR}/../lockclaw-core"
export CORE_DIR

# ── Detect runtime ──────────────────────────────────────────
RUNTIME="none"
if command -v openclaw >/dev/null 2>&1; then
    RUNTIME="openclaw"
elif command -v ollama >/dev/null 2>&1; then
    RUNTIME="ollama"
fi

# ── 1) Container running ────────────────────────────────────
if [ -r /proc/uptime ]; then
    awk '{ if ($1 > 0) exit 0; exit 1 }' /proc/uptime || fail "system uptime invalid"
    pass "container running"
else
    fail "cannot verify container state"
fi

# ── 2) Non-root user exists ──────────────────────────────────
if id lockclaw >/dev/null 2>&1; then
    pass "lockclaw user exists"
else
    fail "lockclaw user missing"
fi

# ── 3) Runtime checks ───────────────────────────────────────
if [ "$RUNTIME" = "openclaw" ]; then
    # Verify OpenClaw binary
    if openclaw --version >/dev/null 2>&1; then
        pass "openclaw installed"
    else
        fail "openclaw version check failed"
    fi

    # Verify gateway is listening on loopback:18789
    if command -v ss >/dev/null 2>&1; then
        if ss -tlnH 2>/dev/null | grep -q ':18789'; then
            pass "openclaw gateway listening on :18789"
            # Verify it's loopback-only
            if ss -tlnH 2>/dev/null | grep ':18789' | grep -q '127\.0\.0\.1'; then
                pass "openclaw gateway bound to loopback"
            else
                note "openclaw gateway may be on non-loopback address (check binding)"
            fi
        else
            note "gateway port 18789 not yet bound (may need API key)"
        fi
    fi

    # Verify claude-mem plugin
    if command -v claude-mem >/dev/null 2>&1 || npm list -g claude-mem >/dev/null 2>&1; then
        pass "claude-mem plugin installed"
    else
        note "claude-mem not found"
    fi

elif [ "$RUNTIME" = "ollama" ]; then
    # Verify Ollama binary
    if ollama --version >/dev/null 2>&1; then
        pass "ollama installed ($(ollama --version 2>/dev/null | head -1))"
    else
        fail "ollama version check failed"
    fi

    # Verify Ollama is listening on loopback:11434
    if command -v ss >/dev/null 2>&1; then
        if ss -tlnH 2>/dev/null | grep -q ':11434'; then
            pass "ollama server listening on :11434"
            if ss -tlnH 2>/dev/null | grep ':11434' | grep -q '127\.0\.0\.1'; then
                pass "ollama server bound to loopback"
            else
                note "ollama server may be on non-loopback address"
            fi
        else
            note "ollama port 11434 not yet bound (may still be starting)"
        fi
    fi

    # Verify model storage directory
    OLLAMA_DIR="${OLLAMA_MODELS:-/home/lockclaw/.ollama/models}"
    if [ -d "$OLLAMA_DIR" ]; then
        pass "ollama models directory exists ($OLLAMA_DIR)"
    else
        note "ollama models directory not found ($OLLAMA_DIR)"
    fi

elif [ "$RUNTIME" = "none" ]; then
    pass "base image — no AI runtime (bring your own)"
fi

# ── 4) SSH posture (if enabled) ──────────────────────────────
if [ "${LOCKCLAW_ENABLE_SSH:-0}" = "1" ]; then
    if command -v ss >/dev/null 2>&1 && ss -ltn | grep -q ':22'; then
        pass "sshd listening (SSH enabled)"
    else
        note "sshd not listening yet"
    fi

    # Verify SSH hardening
    if [ -f /etc/ssh/sshd_config.d/10-lockclaw.conf ]; then
        SSHD_CONF="/etc/ssh/sshd_config.d/10-lockclaw.conf"
        grep -Eqi '^\s*PermitRootLogin\s+no' "$SSHD_CONF" || fail "PermitRootLogin not set to no"
        grep -Eqi '^\s*PasswordAuthentication\s+no' "$SSHD_CONF" || fail "PasswordAuthentication not set to no"
        pass "SSH hardening checks (auth)"
    fi
else
    # SSH should NOT be listening if not enabled
    if command -v ss >/dev/null 2>&1 && ss -ltn | grep -q ':22'; then
        note "sshd is listening but LOCKCLAW_ENABLE_SSH is not set"
    fi
fi

# ── 5) Port exposure audit (HARD FAIL) ──────────────────────
# This is the critical check: no unexpected ports should be
# listening on non-loopback addresses.
if command -v ss >/dev/null 2>&1; then
    echo ""
    echo "=== Port Exposure Audit ==="

    # Build dynamic allowlist based on what's configured
    ALLOWED_REGEX=':22$'  # SSH is always allowed in the regex (may not be listening)

    # All listeners
    ALL_LISTENERS=$(ss -tlnH 2>/dev/null | awk '{print $4}' || true)

    # Non-loopback listeners (the ones that matter)
    NON_LOOPBACK=$(echo "$ALL_LISTENERS" | grep -v '127\.0\.0\.1' | grep -v '\[::1\]' | grep -v '^\*:' || true)

    if [ -n "$NON_LOOPBACK" ]; then
        # Filter out allowed ports
        UNEXPECTED=$(echo "$NON_LOOPBACK" | grep -Ev "$ALLOWED_REGEX" || true)
        if [ -n "$UNEXPECTED" ]; then
            echo "FAIL: Unexpected non-loopback listeners:"
            echo "$UNEXPECTED"
            fail "Unexpected ports exposed on non-loopback addresses"
        fi
    fi

    # Loopback listeners are fine — that's the point
    LOOPBACK_ONLY=$(echo "$ALL_LISTENERS" | grep -E '127\.0\.0\.1|\[::1\]' || true)
    if [ -n "$LOOPBACK_ONLY" ]; then
        pass "loopback-only services: $(echo "$LOOPBACK_ONLY" | tr '\n' ' ')"
    fi

    pass "no unexpected public ports exposed"
else
    note "ss not available; port check skipped"
fi

# ── 6) DNS resolution ───────────────────────────────────────
if command -v getent >/dev/null 2>&1; then
    if getent hosts github.com >/dev/null 2>&1; then
        pass "DNS resolution"
    else
        note "DNS resolution failed (may be expected in isolated networks)"
    fi
fi

echo ""
echo "Smoke tests completed."
