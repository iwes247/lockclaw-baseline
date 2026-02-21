#!/usr/bin/env bash
set -euo pipefail

# LockClaw Baseline — container entrypoint
# Detects which AI runtime is installed and starts it.
# Does NOT start OS-level services (nftables, auditd, fail2ban).
# Those belong in lockclaw-appliance.

log() { echo "[lockclaw] $*"; }

# ── Detect installed runtime ────────────────────────────────
detect_runtime() {
    if command -v openclaw >/dev/null 2>&1; then
        echo "openclaw"
    elif command -v ollama >/dev/null 2>&1; then
        echo "ollama"
    else
        echo "base"
    fi
}

RUNTIME="$(detect_runtime)"

# ── SSH key injection ────────────────────────────────────────
inject_ssh_key() {
    if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
        mkdir -p /home/lockclaw/.ssh
        echo "$SSH_PUBLIC_KEY" > /home/lockclaw/.ssh/authorized_keys
        chmod 600 /home/lockclaw/.ssh/authorized_keys
        chown -R lockclaw:lockclaw /home/lockclaw/.ssh
        log "SSH public key injected for user 'lockclaw'"
    elif [ -f /home/lockclaw/.ssh/authorized_keys ]; then
        log "SSH authorized_keys found (mounted or pre-existing)"
    fi
}

# ── Optional SSH ─────────────────────────────────────────────
start_ssh() {
    if [ "${LOCKCLAW_ENABLE_SSH:-0}" = "1" ]; then
        inject_ssh_key

        if [ ! -f /home/lockclaw/.ssh/authorized_keys ]; then
            log "WARN: SSH enabled but no key configured."
            log "  Set SSH_PUBLIC_KEY env var or mount authorized_keys."
            log "  Example: docker run -e SSH_PUBLIC_KEY=\"\$(cat ~/.ssh/id_ed25519.pub)\" ..."
            return
        fi

        if command -v sshd >/dev/null 2>&1; then
            if /usr/sbin/sshd 2>/dev/null; then
                log "sshd started (key-auth only, modern ciphers)"
            else
                log "WARN: sshd start failed"
            fi
        fi
    fi
}

# ── Runtime startup ──────────────────────────────────────────
start_openclaw() {
    if command -v openclaw >/dev/null 2>&1; then
        export HOME=/home/lockclaw
        su lockclaw -c 'openclaw gateway --port 18789 &' 2>/dev/null
        sleep 2
        if command -v ss >/dev/null 2>&1 && ss -tlnH 2>/dev/null | grep -q ':18789'; then
            log "OpenClaw gateway started (ws://127.0.0.1:18789)"
        else
            log "WARN: OpenClaw gateway may still be starting on :18789"
        fi
    fi
}

start_ollama() {
    if command -v ollama >/dev/null 2>&1; then
        export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
        export OLLAMA_MODELS="${OLLAMA_MODELS:-/home/lockclaw/.ollama/models}"

        su lockclaw -c \
            "OLLAMA_HOST=$OLLAMA_HOST OLLAMA_MODELS=$OLLAMA_MODELS ollama serve &" \
            2>/dev/null
        sleep 2
        if command -v ss >/dev/null 2>&1 && ss -tlnH 2>/dev/null | grep -q ':11434'; then
            log "Ollama started ($OLLAMA_HOST)"
        else
            log "WARN: Ollama may still be starting on $OLLAMA_HOST"
        fi
        log "Pull a model:  ollama pull llama3.2"
        log "Chat:          ollama run llama3.2"
    fi
}

# ── Banner ───────────────────────────────────────────────────
show_banner() {
    log ""
    log "╔══════════════════════════════════════════════════════════╗"
    log "║  LockClaw Baseline ready                                ║"
    log "║                                                         ║"
    log "║  User:      lockclaw                                    ║"

    if [ "${LOCKCLAW_ENABLE_SSH:-0}" = "1" ]; then
        log "║  SSH:       enabled (port 22, key-auth only)            ║"
    else
        log "║  SSH:       disabled (set LOCKCLAW_ENABLE_SSH=1)        ║"
    fi

    case "$RUNTIME" in
        openclaw)
            log "║  Runtime:   OpenClaw (ws://127.0.0.1:18789)             ║"
            log "║  Memory:    claude-mem (persistent across sessions)      ║"
            ;;
        ollama)
            log "║  Runtime:   Ollama (http://127.0.0.1:11434)             ║"
            log "║  Models:    /home/lockclaw/.ollama/models                ║"
            ;;
        base)
            log "║  Runtime:   none (bring your own)                       ║"
            ;;
    esac

    log "║                                                         ║"
    log "║  Validate:  /opt/lockclaw/scripts/test-smoke.sh         ║"
    log "╚══════════════════════════════════════════════════════════╝"
    log ""
}

# ── Pre-flight security gate ─────────────────────────────────
# ⚠ SECURITY: Fail-closed. If pre-flight detects unauthorized ports,
# the container MUST NOT start any application processes.
run_preflight() {
    local preflight="${LOCKCLAW_HOME}/scripts/pre-flight.sh"
    if [ -x "$preflight" ]; then
        if ! "$preflight"; then
            log "FATAL: pre-flight security check failed. Aborting."
            exit 1
        fi
    else
        log "WARN: pre-flight.sh not found or not executable at $preflight"
    fi
}

# ── Main ─────────────────────────────────────────────────────
start_services() {
    run_preflight
    start_ssh

    case "$RUNTIME" in
        openclaw) start_openclaw ;;
        ollama)   start_ollama ;;
        base)     log "No AI runtime detected — base image" ;;
    esac

    show_banner
}

case "${1:-start}" in
    start)
        start_services
        log "LockClaw ready. PID 1 holding."
        exec tail -f /dev/null
        ;;
    test)
        start_services
        exec /opt/lockclaw/scripts/test-smoke.sh
        ;;
    shell)
        start_services
        exec /bin/bash
        ;;
    *)
        exec "$@"
        ;;
esac
