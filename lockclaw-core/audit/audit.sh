#!/usr/bin/env bash
set -euo pipefail

# lockclaw-core audit script
# Validates that required policy/overlay files exist and contain correct values.
#
# Usage:
#   audit.sh                              # auto-detect overlay dir
#   audit.sh --overlay-dir ./overlays     # explicit overlay dir
#   audit.sh --mode container             # container-only checks (no OS-level)
#   audit.sh --mode appliance             # full OS-level checks
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

OVERLAY_DIR=""
MODE="auto"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --overlay-dir)
            OVERLAY_DIR="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Auto-detect overlay dir if not specified
if [ -z "$OVERLAY_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Check common locations relative to consuming repo
    for candidate in \
        "$SCRIPT_DIR/../../overlays" \
        "$SCRIPT_DIR/../overlays" \
        "./overlays"; do
        if [ -d "$candidate" ]; then
            OVERLAY_DIR="$(cd "$candidate" && pwd)"
            break
        fi
    done
fi

# Auto-detect mode if not specified
if [ "$MODE" = "auto" ]; then
    if [ -n "$OVERLAY_DIR" ] && [ -d "$OVERLAY_DIR/etc/security" ]; then
        MODE="appliance"
    else
        MODE="container"
    fi
fi

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

check_file() {
    local path="$1"
    local desc="${2:-$path exists}"
    check "$desc" test -f "$path"
}

check_grep() {
    local pattern="$1"
    local file="$2"
    local desc="${3:-$file contains $pattern}"
    check "$desc" grep -Eqi "$pattern" "$file"
}

echo "lockclaw-core audit"
echo "  mode:        $MODE"
echo "  overlay-dir: ${OVERLAY_DIR:-<none>}"
echo ""

# ── Container-mode checks (always run) ────────────────────────
echo "=== Common checks ==="

# Verify this script itself is executable
check "audit.sh is executable" test -x "${BASH_SOURCE[0]}"

# ── Appliance-mode checks (only when overlays exist) ─────────
if [ "$MODE" = "appliance" ]; then
    echo ""
    echo "=== Appliance overlay checks ==="

    if [ -z "$OVERLAY_DIR" ] || [ ! -d "$OVERLAY_DIR" ]; then
        echo "  FAIL: overlay directory not found (expected --overlay-dir or ./overlays)"
        ((FAIL++))
    else
        # Required overlay files
        REQUIRED_FILES=(
            "etc/security/sysctl.conf"
            "etc/security/limits.conf"
            "etc/security/sudoers.d/10-lockclaw-hardening"
            "etc/security/sshd_config.d/10-lockclaw-hardening.conf"
            "etc/security/audit/audit.rules"
            "etc/security/logging/journald.conf"
            "etc/security/fail2ban/jail.local"
            "etc/security/fail2ban/filter.d/portscan.conf"
            "etc/security/logrotate.d/sudo"
            "etc/security/rsyslog.d/50-lockclaw.conf"
            "etc/security/aide/aide.conf"
            "etc/security/rkhunter/rkhunter.conf.local"
            "etc/security/apt/50unattended-upgrades"
            "etc/security/apt/20auto-upgrades"
            "etc/network/nftables.conf"
            "etc/network/resolved.conf"
            "etc/network/timesyncd.conf"
        )

        for f in "${REQUIRED_FILES[@]}"; do
            check_file "$OVERLAY_DIR/$f" "$f exists"
        done

        # Policy content validation
        echo ""
        echo "=== Policy content validation ==="

        SSH_OVERLAY="$OVERLAY_DIR/etc/security/sshd_config.d/10-lockclaw-hardening.conf"
        if [ -f "$SSH_OVERLAY" ]; then
            check_grep '^\s*PermitRootLogin\s+no' "$SSH_OVERLAY" "SSH: PermitRootLogin no"
            check_grep '^\s*PasswordAuthentication\s+no' "$SSH_OVERLAY" "SSH: PasswordAuthentication no"
            check_grep '^\s*Ciphers\s' "$SSH_OVERLAY" "SSH: Ciphers restricted"
            check_grep '^\s*KexAlgorithms\s' "$SSH_OVERLAY" "SSH: KexAlgorithms restricted"
            check_grep '^\s*MACs\s' "$SSH_OVERLAY" "SSH: MACs restricted"
        fi

        NFT_OVERLAY="$OVERLAY_DIR/etc/network/nftables.conf"
        if [ -f "$NFT_OVERLAY" ]; then
            check_grep 'policy\s+drop' "$NFT_OVERLAY" "Firewall: deny-default policy"
            check_grep 'dport\s+22' "$NFT_OVERLAY" "Firewall: SSH allow rule present"
        fi

        SYSCTL_OVERLAY="$OVERLAY_DIR/etc/security/sysctl.conf"
        if [ -f "$SYSCTL_OVERLAY" ]; then
            check_grep 'rp_filter\s*=\s*1' "$SYSCTL_OVERLAY" "Sysctl: rp_filter enabled"
            check_grep 'tcp_syncookies\s*=\s*1' "$SYSCTL_OVERLAY" "Sysctl: tcp_syncookies enabled"
        fi

        RESOLVED_OVERLAY="$OVERLAY_DIR/etc/network/resolved.conf"
        if [ -f "$RESOLVED_OVERLAY" ]; then
            if grep -Eqi 'DNSSEC\s*=\s*allow-downgrade' "$RESOLVED_OVERLAY"; then
                echo "  FAIL: resolved.conf uses DNSSEC=allow-downgrade (vulnerable)"
                FAIL=$((FAIL + 1))
            else
                echo "  PASS: DNSSEC not in downgrade mode"
                PASS=$((PASS + 1))
            fi
        fi

        F2B_OVERLAY="$OVERLAY_DIR/etc/security/fail2ban/jail.local"
        if [ -f "$F2B_OVERLAY" ]; then
            check_grep '^\s*enabled\s*=\s*true' "$F2B_OVERLAY" "fail2ban: sshd jail enabled"
            check_grep '\[portscan\]' "$F2B_OVERLAY" "fail2ban: portscan jail defined"
        fi
    fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
