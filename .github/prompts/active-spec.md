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

TASK_START
[READY FOR NEXT VIBE]
TASK_END

## History

HISTORY_START
> ✅ FINISHED: 20260221 — Implemented pre-flight.sh security gate
> Created scripts/pre-flight.sh: ss -ltn discovery, port extraction handling *, 0.0.0.0, [::], [::]
> Allowlist: 22, 8080. Fail-closed EXIT 1 on violation.
> iproute2 already in packages/baseline.txt. chmod +x covered by Dockerfile glob.
> Wired run_preflight() in docker-entrypoint.sh before start_ssh/start_runtime.
HISTORY_END