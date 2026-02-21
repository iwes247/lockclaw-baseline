# LockClaw Baseline — Active Spec

> **Phone → GitHub → VS Code bridge**
>
> Edit this file from your phone (via GPT or GitHub mobile), push to `main`,
> then run `vibe-sync` in VS Code. Copilot reads this and executes your intent.

---

## How to use this file

1. **On your phone (GPT):** Describe what you want built/changed. Have GPT write
   the spec into this file format. Commit and push to `main` from GitHub mobile.
2. **In VS Code:** Run `vibe-sync` (alias or script). It pulls latest and prints
   this file so Copilot has full context.
3. **Tell Copilot:** "Read the active spec and do what it says."

---

## Identity

- **GitHub user:** `iwes247`
- **Git config:**
  ```
  user.name  = iwes247
  user.email = iwes247@users.noreply.github.com
  ```
- **Never push as your work user.** Verify: `git config user.name` → `iwes247`

---

## Project summary

Secure-by-default Docker/Compose deployment baseline for AI runtimes.
No `--cap-add NET_ADMIN` required. Container-level only — no OS hardening.

### Architecture

```
lockclaw-core/            ← shared audit scripts + port allowlists (vendored)
packages/                 ← container package manifest (baseline.txt)
scripts/                  ← smoke test tooling
docs/                     ← threat model
```

### Security defaults

| Default | Detail |
|---------|--------|
| Loopback-only | AI runtimes bind to `127.0.0.1` — never `0.0.0.0` |
| SSH opt-in | Disabled by default; `LOCKCLAW_ENABLE_SSH=1` to enable |
| Non-root | `lockclaw` user for all processes |
| Port audit | Smoke tests hard-fail on unexpected listeners |

### Image variants

- `lockclaw-baseline:openclaw` — OpenClaw gateway + claude-mem
- `lockclaw-baseline:ollama` — Ollama local LLM engine
- `lockclaw-baseline:base` — Bring your own runtime

### Related repos

- [lockclaw-appliance](https://github.com/iwes247/lockclaw-appliance) — OS-level hardening (VM/bare-metal)
- [lockclaw-core](https://github.com/iwes247/lockclaw-core) — Shared audit + port allowlists

---

## Current task

<!-- 
  PHONE USERS: Replace everything below this line with your task.
  Be specific — what to build, change, fix, or research.
  Copilot will read this and execute.
-->

_No active task. Edit this section from your phone and push to start._
