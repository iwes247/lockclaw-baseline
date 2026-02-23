#!/usr/bin/env bash
set -euo pipefail

# LockClaw Baseline — v1 container entrypoint
# Enforces locked-down defaults for containerized AI runtimes.

log() { echo "[lockclaw] $*"; }

LOCKCLAW_HOME="${LOCKCLAW_HOME:-/opt/lockclaw}"
LOCKCLAW_MODE="${LOCKCLAW_MODE:-hobby}"
CORE_DIR="${LOCKCLAW_HOME}/lockclaw-core"
MODE_POLICY_FILE="${CORE_DIR}/policies/modes/${LOCKCLAW_MODE}.json"
LOCKCLAW_DATA_DIR="${LOCKCLAW_DATA_DIR:-/data}"

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

require_mode_policy() {
    if [ ! -f "$MODE_POLICY_FILE" ]; then
        log "FATAL: mode policy not found: $MODE_POLICY_FILE"
        exit 1
    fi
}

json_array_numbers() {
    local key="$1"
    grep -oP '"'"$key"'"\s*:\s*\[\K[^\]]*' "$MODE_POLICY_FILE" | tr ',' '\n' | tr -d ' ' | sed '/^$/d'
}

json_array_strings() {
    local key="$1"
    grep -oP '"'"$key"'"\s*:\s*\[\K[^\]]*' "$MODE_POLICY_FILE" | tr ',' '\n' | sed -E 's/^\s*"(.*)"\s*$/\1/' | sed '/^$/d'
}

json_string() {
    local key="$1"
    grep -oP '"'"$key"'"\s*:\s*"\K[^"]*' "$MODE_POLICY_FILE" | head -1
}

prepare_data_dir() {
    mkdir -p "$LOCKCLAW_DATA_DIR"
}

# ── Runtime startup ──────────────────────────────────────────
start_openclaw() {
    if command -v openclaw >/dev/null 2>&1; then
        export HOME="$LOCKCLAW_DATA_DIR"
        mkdir -p "$LOCKCLAW_DATA_DIR/openclaw/workspace/skills"
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
        export OLLAMA_MODELS="${OLLAMA_MODELS:-${LOCKCLAW_DATA_DIR}/ollama/models}"
        mkdir -p "$OLLAMA_MODELS"

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

show_startup_banner() {
    mapfile -t allowed_ports < <(json_array_numbers "allowed_ports")
    mapfile -t writable_paths < <(json_array_strings "writable_paths")
    local egress_policy
    egress_policy="$(json_string "egress_policy")"

    log ""
    log "╔══════════════════════════════════════════════════════════╗"
    log "║  LockClaw Baseline v1 posture                           ║"
    log "║                                                         ║"
    log "║  Mode:      ${LOCKCLAW_MODE}                                         ║"
    log "║  Root FS:   read-only                                     ║"
    log "║  Caps:      dropped + no-new-privileges                   ║"
    log "║                                                         ║"
    log "║  Outbound:  ${egress_policy} (not enforced in baseline v1)       ║"
    log "║                                                         ║"
    log "║  Allowed Ports: ${allowed_ports[*]:-none}                           ║"
    log "║  Writable Paths: ${writable_paths[*]}                           ║"
    log "║  Validate:  /opt/lockclaw/scripts/test-smoke.sh         ║"
    log "╚══════════════════════════════════════════════════════════╝"
    log ""
}

run_preflight() {
    local preflight="${CORE_DIR}/audit/pre-flight.sh"
    if [ -x "$preflight" ]; then
        if ! "$preflight" --mode "$LOCKCLAW_MODE"; then
            log "FATAL: pre-flight security check failed. Aborting."
            exit 1
        fi
    else
        log "FATAL: core pre-flight not found or not executable at $preflight"
        exit 1
    fi
}

start_services() {
    require_mode_policy
    prepare_data_dir
    run_preflight
    show_startup_banner
    log "Outbound network is allowed; baseline v1 does not enforce egress restrictions."

    case "$RUNTIME" in
        openclaw) start_openclaw ;;
        ollama)   start_ollama ;;
        base)     log "No AI runtime detected — base image" ;;
    esac

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
