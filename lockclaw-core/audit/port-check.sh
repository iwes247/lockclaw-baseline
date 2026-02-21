#!/usr/bin/env bash
set -euo pipefail

# lockclaw-core port-check script
# Verifies no unexpected ports are listening.
# Hard-fails on any port not in the allowlist for the given profile.
#
# Usage:
#   port-check.sh --profile container     # container profile
#   port-check.sh --profile appliance     # VM/appliance profile
#   port-check.sh --profile lan           # LAN-exposed profile
#   port-check.sh --allowlist-file ./my-ports.json
#
# Exit codes:
#   0 — only allowlisted ports are listening
#   1 — unexpected ports detected (hard fail)

PROFILE="container"
ALLOWLIST_FILE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --allowlist-file)
            ALLOWLIST_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Resolve allowlist file
if [ -z "$ALLOWLIST_FILE" ]; then
    ALLOWLIST_FILE="$CORE_DIR/policies/ports/${PROFILE}.json"
fi

if [ ! -f "$ALLOWLIST_FILE" ]; then
    echo "ERROR: Port allowlist not found: $ALLOWLIST_FILE" >&2
    exit 1
fi

echo "Port check — profile: $PROFILE"
echo "Allowlist: $ALLOWLIST_FILE"
echo ""

# Parse allowlist: extract port numbers from JSON
# Format: {"allowed_ports": [22, 18789], "description": "..."}
# Using grep+sed for portability (no jq dependency)
ALLOWED_PORTS=$(grep -oP '"allowed_ports"\s*:\s*\[\K[^\]]+' "$ALLOWLIST_FILE" | tr ',' '\n' | tr -d ' ')

if [ -z "$ALLOWED_PORTS" ]; then
    echo "WARNING: No ports in allowlist — all listeners will be flagged"
fi

echo "Allowed ports: $(echo "$ALLOWED_PORTS" | tr '\n' ' ')"
echo ""

# Check for ss command
if ! command -v ss >/dev/null 2>&1; then
    echo "ERROR: 'ss' command not found. Install iproute2." >&2
    exit 1
fi

# Get all TCP listeners
LISTENERS=$(ss -tlnH 2>/dev/null | awk '{print $4}' || true)

if [ -z "$LISTENERS" ]; then
    echo "No TCP listeners detected."
    echo "PASS: port check"
    exit 0
fi

echo "Active TCP listeners:"
UNEXPECTED=""
while IFS= read -r listener; do
    # Extract port number from address (e.g., 127.0.0.1:22 → 22, :::22 → 22, *:22 → 22)
    PORT=$(echo "$listener" | grep -oP ':\K[0-9]+$' || true)
    if [ -z "$PORT" ]; then
        continue
    fi

    # Check if port is in allowlist
    FOUND=0
    while IFS= read -r allowed; do
        if [ "$PORT" = "$allowed" ]; then
            FOUND=1
            break
        fi
    done <<< "$ALLOWED_PORTS"

    if [ "$FOUND" = "1" ]; then
        echo "  ✓ $listener (port $PORT — allowed)"
    else
        echo "  ✗ $listener (port $PORT — NOT in allowlist)"
        UNEXPECTED="${UNEXPECTED}${PORT} "
    fi
done <<< "$LISTENERS"

echo ""

if [ -n "$UNEXPECTED" ]; then
    echo "FAIL: Unexpected ports detected: $UNEXPECTED"
    echo "Add to $ALLOWLIST_FILE if intentional, or fix the service binding."
    exit 1
fi

echo "PASS: All listeners are in the allowlist."
exit 0
