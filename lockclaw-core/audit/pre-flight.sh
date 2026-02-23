#!/usr/bin/env bash
set -euo pipefail

MODE="${LOCKCLAW_MODE:-hobby}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY_FILE="$CORE_DIR/policies/modes/${MODE}.json"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$2"
            POLICY_FILE="$CORE_DIR/policies/modes/${MODE}.json"
            shift 2
            ;;
        --policy-file)
            POLICY_FILE="$2"
            shift 2
            ;;
        *)
            echo "[pre-flight] FATAL: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

log() { echo "[pre-flight] $*"; }
fail() {
    log "SECURITY VIOLATION: $*"
    exit 1
}

[ -f "$POLICY_FILE" ] || fail "mode policy file not found: $POLICY_FILE"

parse_json_array_numbers() {
    local key="$1"
    grep -oP '"'"$key"'"\s*:\s*\[\K[^\]]*' "$POLICY_FILE" \
        | tr ',' '\n' \
        | tr -d ' ' \
        | sed '/^$/d'
}

parse_json_array_strings() {
    local key="$1"
    grep -oP '"'"$key"'"\s*:\s*\[\K[^\]]*' "$POLICY_FILE" \
        | tr ',' '\n' \
        | sed -E 's/^\s*"(.*)"\s*$/\1/' \
        | sed '/^$/d'
}

parse_json_string() {
    local key="$1"
    grep -oP '"'"$key"'"\s*:\s*"\K[^"]*' "$POLICY_FILE" | head -1
}

mapfile -t ALLOWED_PORTS < <(parse_json_array_numbers "allowed_ports")
mapfile -t WRITABLE_PATHS < <(parse_json_array_strings "writable_paths")
EGRESS_POLICY="$(parse_json_string "egress_policy")"
EGRESS_LOGGING="$(parse_json_string "egress_logging")"

[[ "${#WRITABLE_PATHS[@]}" -gt 0 ]] || fail "policy contains no writable_paths"

if ! command -v ss >/dev/null 2>&1; then
    fail "'ss' command not found (iproute2 required)"
fi

LISTENERS="$(ss -ltnH 2>/dev/null | awk '{print $4}' || true)"
if [ -n "$LISTENERS" ]; then
    while IFS= read -r listener; do
        [ -n "$listener" ] || continue
        port="$(echo "$listener" | grep -oP ':\K[0-9]+$' || true)"
        [ -n "$port" ] || continue

        allowed=0
        for expected in "${ALLOWED_PORTS[@]}"; do
            if [ "$port" = "$expected" ]; then
                allowed=1
                break
            fi
        done

        if [ "$allowed" -ne 1 ]; then
            fail "listening port :$port is not allowlisted for mode '$MODE'"
        fi
    done <<< "$LISTENERS"
fi

ROOT_MOUNT="$(awk '$2=="/"{print $4}' /proc/mounts | head -1)"
if [[ ",$ROOT_MOUNT," != *,ro,* ]]; then
    fail "root filesystem is not read-only"
fi

for path in "${WRITABLE_PATHS[@]}"; do
    [ -d "$path" ] || fail "required writable path missing: $path"
    [ -w "$path" ] || fail "required writable path is not writable: $path"
done

is_policy_writable_path() {
    local path="$1"
    for writable in "${WRITABLE_PATHS[@]}"; do
        if [ "$path" = "$writable" ]; then
            return 0
        fi
    done
    return 1
}

while read -r _ mountpoint fstype options _; do
    [[ ",$options," == *,rw,* ]] || continue

    if is_policy_writable_path "$mountpoint"; then
        continue
    fi

    if [ "$fstype" = "tmpfs" ]; then
        case "$mountpoint" in
            /tmp|/run|/run/*|/var/tmp|/dev|/dev/shm)
                continue
                ;;
        esac
    fi

    case "$mountpoint" in
        /etc/hosts|/etc/hostname|/etc/resolv.conf)
            continue
            ;;
    esac

    case "$fstype" in
        proc|sysfs|cgroup|cgroup2|devpts|mqueue)
            continue
            ;;
    esac

    fail "RW mount outside allowed writable paths detected: $mountpoint ($fstype)"
done < /proc/mounts

[ -r /proc/1/status ] || fail "cannot read /proc/1/status"
CAP_EFF_HEX="$(awk '/^CapEff:/{print $2}' /proc/1/status)"
NO_NEW_PRIVS="$(awk '/^NoNewPrivs:/{print $2}' /proc/1/status)"
SECCOMP_MODE="$(awk '/^Seccomp:/{print $2}' /proc/1/status)"

[ "$NO_NEW_PRIVS" = "1" ] || fail "NoNewPrivs is not enabled"
[ "$SECCOMP_MODE" != "0" ] || fail "seccomp is disabled (container appears too privileged)"

CAP_EFF_DEC=$((16#$CAP_EFF_HEX))
has_cap() {
    local cap_bit="$1"
    (( (CAP_EFF_DEC & (1 << cap_bit)) != 0 ))
}

dangerous_caps=(1 12 16 17 19 21 22 25 39)
dangerous_names=("CAP_DAC_OVERRIDE" "CAP_NET_ADMIN" "CAP_SYS_MODULE" "CAP_SYS_RAWIO" "CAP_SYS_PTRACE" "CAP_SYS_ADMIN" "CAP_SYS_BOOT" "CAP_SYS_TIME" "CAP_BPF")
for i in "${!dangerous_caps[@]}"; do
    if has_cap "${dangerous_caps[$i]}"; then
        fail "dangerous capability present: ${dangerous_names[$i]}"
    fi
done

if [ "$CAP_EFF_HEX" = "0000003fffffffff" ] || [ "$CAP_EFF_HEX" = "3fffffffff" ]; then
    fail "container appears privileged (full effective capability set)"
fi

log "Startup posture summary"
log "  Mode: $MODE"
log "  Allowed Ports: ${ALLOWED_PORTS[*]:-none}"
log "  Writable Paths: ${WRITABLE_PATHS[*]}"
log "  Root FS: read-only"
log "  Caps: checked for dangerous privileges"
if [ "$EGRESS_POLICY" = "allow" ]; then
    if [ "$EGRESS_LOGGING" = "banner_only" ]; then
        log "  Outbound: allowed (not enforced in baseline v1)"
    else
        log "  Outbound: allowed"
    fi
fi

log "Pre-flight PASSED"
exit 0
