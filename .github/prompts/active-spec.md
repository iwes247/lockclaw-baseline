# LockClaw Baseline — Active Spec

> **This file is the phone-to-VSCode bridge.**
> Edit from your phone (via GPT) → push → pull in VS Code → Copilot reads and executes.

## Project summary

LockClaw Baseline is a secure-by-default Docker deployment baseline for
self-hosting AI runtimes. No OS-level hardening (that's lockclaw-appliance).
No `--cap-add NET_ADMIN` required. Services bind to loopback only. SSH is
opt-in. Port audit hard-fails on unexpected listeners.

## Architecture

```
scripts/        ← smoke test tooling
lockclaw-core/  ← shared audit scripts and port allowlists (vendored)
packages/       ← baseline package manifest
docs/           ← threat model
```

## Security model

- All services bind to 127.0.0.1 — never directly exposed.
- SSH disabled by default; opt-in via LOCKCLAW_ENABLE_SSH=1.
- SSH (when enabled): key-only, no root, modern ciphers.
- Non-root user (`lockclaw`) for all runtime processes.
- Port audit: smoke tests hard-fail on unexpected non-loopback listeners.
- No nftables, auditd, or fail2ban — those are host/VM responsibilities.


## Current Task
**Task:** Implement the `pre-flight.sh` security gate in `lockclaw-baseline`.

**Pseudocode Logic (Architect’s Plan):**
1. **INIT:** Script starts during Docker container entrypoint phase.
2. **DISCOVERY:** Execute `ss -ltn` to identify all active listening ports.
3. **EXTRACTION:** Parse output to isolate the local port numbers only.
4. **VALIDATION:** Compare active ports against the ALLOWLIST (22, 8080).
5. **ACTION:** If any port NOT in ALLOWLIST is found, echo “SECURITY VIOLATION: Unauthorized port detected” and EXIT 1.
6. **PROCEED:** If only authorized ports are found, EXIT 0 and allow entrypoint to continue.

**Red-Teamer Constraints (Safety Rails):**
- **Dependency:** Claude must add `iproute2` to the `apt-get install` layer in the Dockerfile.
- **Scope:** Ensure the logic handles `*` (all interfaces) and `[::]` (IPv6) notation correctly.
- **Fail-Closed:** The main application process MUST NOT start if `pre-flight.sh` returns a non-zero exit code.
- **Permissions:** Ensure the script is explicitly `chmod +x` in the Dockerfile.

**Verification Command:**
Run `docker build -t lockclaw-test . && docker run —rm lockclaw-test` and verify it exits if an unauthorized service is added to the image.


## History

HISTORY_START
HISTORY_END
