#!/usr/bin/env bash
set -euo pipefail

# lockclaw-core security scanner
# Runs hardening tools: AIDE, rkhunter, Lynis
# Designed to run inside a VM/appliance (not containers).
#
# Usage:
#   security-scan.sh              # full scan (all tools)
#   security-scan.sh aide         # file integrity only
#   security-scan.sh rkhunter     # rootkit scan only
#   security-scan.sh lynis        # security audit only

TOOL="${1:-all}"
PASS=0
WARN=0
FAIL=0
DIVIDER="════════════════════════════════════════════════════════════"

log()  { echo "[lockclaw-scan] $*"; }
ok()   { echo "  ✓ $*"; ((PASS++)); }
warn() { echo "  ⚠ $*"; ((WARN++)); }
err()  { echo "  ✗ $*"; ((FAIL++)); }

run_aide() {
    log ""
    log "$DIVIDER"
    log "  AIDE — File Integrity Check"
    log "$DIVIDER"

    if ! command -v aide >/dev/null 2>&1; then
        err "aide not installed"
        return
    fi

    if [ ! -f /var/lib/aide/aide.db ]; then
        warn "AIDE baseline database not found"
        warn "Run: aide --init --config /etc/aide/aide.conf && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db"
        return
    fi

    AIDE_OUT=$(aide --check --config /etc/aide/aide.conf 2>&1) && AIDE_RC=$? || AIDE_RC=$?

    case $AIDE_RC in
        0)
            ok "No file changes detected (baseline intact)"
            ;;
        1|2|3|4|5|6|7)
            warn "AIDE detected file changes (exit code $AIDE_RC):"
            echo "$AIDE_OUT" | head -40
            ;;
        *)
            err "AIDE error (exit code $AIDE_RC)"
            echo "$AIDE_OUT" | tail -10
            ;;
    esac
}

run_rkhunter() {
    log ""
    log "$DIVIDER"
    log "  rkhunter — Rootkit Detection"
    log "$DIVIDER"

    if ! command -v rkhunter >/dev/null 2>&1; then
        err "rkhunter not installed"
        return
    fi

    RK_OUT=$(rkhunter --check --sk --nocolors 2>&1) && RK_RC=$? || RK_RC=$?

    WARNINGS=$(echo "$RK_OUT" | grep -c '\[ Warning \]' || true)
    INFECTED=$(echo "$RK_OUT" | grep -c '\[ Infected \]' || true)

    if [ "$INFECTED" -gt 0 ]; then
        err "rkhunter found $INFECTED infected item(s)!"
        echo "$RK_OUT" | grep -E '\[ Warning \]|\[ Infected \]'
    elif [ "$WARNINGS" -gt 0 ]; then
        warn "rkhunter found $WARNINGS warning(s) (review /var/log/rkhunter.log)"
        echo "$RK_OUT" | grep '\[ Warning \]'
    else
        ok "No rootkits or suspicious files detected"
    fi
}

run_lynis() {
    log ""
    log "$DIVIDER"
    log "  Lynis — Security Audit"
    log "$DIVIDER"

    if ! command -v lynis >/dev/null 2>&1; then
        err "lynis not installed"
        return
    fi

    LYNIS_OUT=$(lynis audit system --quick --no-colors 2>&1) && LYNIS_RC=$? || LYNIS_RC=$?

    SCORE=$(echo "$LYNIS_OUT" | grep -oP 'Hardening index\s*:\s*\K[0-9]+' || echo "unknown")

    if [ "$SCORE" != "unknown" ]; then
        if [ "$SCORE" -ge 70 ]; then
            ok "Lynis hardening score: $SCORE / 100"
        elif [ "$SCORE" -ge 50 ]; then
            warn "Lynis hardening score: $SCORE / 100 (room for improvement)"
        else
            err "Lynis hardening score: $SCORE / 100 (needs attention)"
        fi
    else
        warn "Could not parse Lynis score — check /var/log/lynis.log"
    fi

    SUGGESTIONS=$(echo "$LYNIS_OUT" | grep -c '^\s*- ' || true)
    [ "$SUGGESTIONS" -gt 0 ] && log "  $SUGGESTIONS suggestions — see: lynis show details"

    log "  Full report: /var/log/lynis-report.dat"
}

# ── Main ─────────────────────────────────────────────────────
log "LockClaw Security Scanner"
log "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

case "$TOOL" in
    aide)     run_aide ;;
    rkhunter) run_rkhunter ;;
    lynis)    run_lynis ;;
    all)
        run_aide
        run_rkhunter
        run_lynis
        ;;
    *)
        echo "Usage: $0 [aide|rkhunter|lynis|all]"
        exit 1
        ;;
esac

log ""
log "$DIVIDER"
log "  Results: $PASS passed, $WARN warnings, $FAIL failures"
log "$DIVIDER"

[ "$FAIL" -gt 0 ] && exit 1
exit 0
