# LockClaw Baseline

Secure-by-default Docker deployment baseline for self-hosting AI runtimes.

## Who it's for

Developers and homelabbers who want to run OpenClaw, Ollama, or other AI runtimes in containers with sane security defaults — without manual hardening.

## What it is NOT

- **Not a hardened OS.** This does not harden the host kernel, firewall, or SSH daemon. Those are host/VM responsibilities — see [lockclaw-appliance](https://github.com/iwes247/lockclaw-appliance) for that.
- **Not a replacement for proper network security.** If your host is exposed to the internet, you need a firewall, VPN, or reverse proxy in front of this container.
- **Does not require `--cap-add NET_ADMIN`.** Capabilities are not needed by default. SSH is opt-in.

## What it does

| Default | Detail |
|---------|--------|
| Loopback-only services | AI runtimes bind to `127.0.0.1` — never directly exposed |
| SSH opt-in | Set `LOCKCLAW_ENABLE_SSH=1` to enable; disabled by default |
| SSH hardened (when enabled) | Key-only auth, no root login, modern ciphers |
| Non-root user | `lockclaw` user for all runtime processes |
| Port audit | Smoke tests hard-fail on unexpected non-loopback listeners |
| Minimal packages | Only what's needed — no nftables, auditd, or fail2ban |

## Image variants

| Image | Runtime | Pull |
|-------|---------|------|
| `lockclaw:openclaw` | [OpenClaw](https://github.com/openclaw/openclaw) gateway + [claude-mem](https://github.com/thedotmack/claude-mem) | `docker pull ghcr.io/iwes247/lockclaw:openclaw` |
| `lockclaw:ollama` | [Ollama](https://ollama.com) local LLM engine | `docker pull ghcr.io/iwes247/lockclaw:ollama` |
| `lockclaw:base` | None (bring your own) | `docker pull ghcr.io/iwes247/lockclaw:base` |
| `lockclaw:latest` | Same as `openclaw` | `docker pull ghcr.io/iwes247/lockclaw:latest` |

## Quickstart

### Run Ollama (simplest)

```bash
docker run -d --name lockclaw \
  -v lockclaw-models:/home/lockclaw/.ollama \
  lockclaw:ollama

# Interact via docker exec
docker exec -it lockclaw bash
ollama pull llama3.2
ollama run llama3.2
```

No ports are published. No capabilities required. The Ollama API is on `127.0.0.1:11434` inside the container.

### Run OpenClaw with SSH access

```bash
docker run -d --name lockclaw \
  -e LOCKCLAW_ENABLE_SSH=1 \
  -e SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)" \
  -e ANTHROPIC_API_KEY="sk-ant-..." \
  -v lockclaw-openclaw:/home/lockclaw/.openclaw \
  -p 2222:22 \
  lockclaw:openclaw

# SSH in and tunnel the gateway
ssh -p 2222 -L 18789:127.0.0.1:18789 lockclaw@localhost
```

### Docker Compose

```bash
docker compose up -d ollama
# or
docker compose up -d openclaw
```

See [docker-compose.yml](docker-compose.yml) for full configuration.

## Threat model

**What this protects against:**
- AI runtime APIs accidentally exposed to the network (loopback binding)
- Weak SSH defaults if SSH is enabled (key-only, modern ciphers)
- Running as root (dedicated `lockclaw` user)
- Unknown ports listening (hard-fail smoke test)

**What this does NOT protect against:**
- Host-level attacks (kernel exploits, container escape)
- Network-level attacks (no firewall — that's the host's job)
- Brute-force SSH (no fail2ban — use host-level or lockclaw-appliance)
- Supply chain attacks beyond pinned package versions
- Misconfigured Docker daemon or host networking

**Assumptions:**
- The host has a firewall (or is on a private network)
- Docker daemon is properly configured (non-root mode recommended)
- API keys are passed via environment variables, not baked into images

See [docs/threat-model.md](docs/threat-model.md) for details.

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LOCKCLAW_ENABLE_SSH` | No | `0` | Set to `1` to start sshd |
| `SSH_PUBLIC_KEY` | If SSH enabled | — | Public key for `lockclaw` user |
| `ANTHROPIC_API_KEY` | For OpenClaw | — | Anthropic API key |
| `OPENAI_API_KEY` | Optional | — | OpenAI API key |
| `OLLAMA_HOST` | No | `127.0.0.1:11434` | Ollama bind address |
| `OLLAMA_MODELS` | No | `/home/lockclaw/.ollama/models` | Model storage path |

## Persistent volumes

| Path | Purpose |
|------|---------|
| `/home/lockclaw/.openclaw` | OpenClaw config, workspace, skills, claude-mem data |
| `/home/lockclaw/.ollama` | Ollama models and config |
| `/home/lockclaw/.ssh` | SSH authorized_keys (alternative to `SSH_PUBLIC_KEY` env var) |

## Validate

```bash
# Run smoke tests inside the container
docker exec lockclaw /opt/lockclaw/scripts/test-smoke.sh

# Check what's listening
docker exec lockclaw ss -tlnp
```

## Related projects

- **[lockclaw-appliance](https://github.com/iwes247/lockclaw-appliance)** — Full OS-level hardening for VM/bare-metal (nftables, auditd, fail2ban, AIDE, rkhunter, Lynis)
- **[lockclaw-core](https://github.com/iwes247/lockclaw-core)** — Shared audit scripts and port allowlists

## License

MIT — see [LICENSE](LICENSE).
