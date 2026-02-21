# Threat Model — LockClaw Baseline

## What this is

A container-level deployment baseline. Not an OS hardening layer.

## Assets

- AI runtime control plane (OpenClaw gateway, Ollama API)
- API keys and credentials passed via environment variables
- User data and model files in mounted volumes
- SSH keys (when SSH is enabled)

## Threats addressed

| Threat | Mitigation |
|--------|------------|
| Runtime API accidentally exposed on network | Services bind to `127.0.0.1` only; never `0.0.0.0` |
| Weak SSH posture | Key-only auth, no root login, modern ciphers (chacha20-poly1305, aes256-gcm) |
| Running as root | Dedicated `lockclaw` user; runtimes run as non-root |
| Unknown services listening | Smoke tests hard-fail on unexpected non-loopback ports |
| Credential leakage into image | `.dockerignore` excludes keys, `.env` files; creds passed at runtime |

## Threats NOT addressed

| Threat | Why | Recommendation |
|--------|-----|----------------|
| Host kernel exploit / container escape | Container-level project; can't harden the host | Use lockclaw-appliance or a hardened host OS |
| Network-level attacks (port scanning, MITM) | No firewall in the container | Host firewall, VPN, or reverse proxy |
| SSH brute-force | No fail2ban in the container | Host-level fail2ban or lockclaw-appliance |
| Supply chain attacks | Limited to pinning package versions | Verify upstream SHAs; use signed images |
| Docker daemon misconfiguration | Out of scope | Run Docker in rootless mode; restrict socket access |
| Denial of service | No rate limiting at container level | Host-level rate limiting |

## Assumptions

1. The host running Docker has its own firewall and network security
2. Docker daemon is properly secured (rootless mode recommended)
3. API keys are injected at runtime, never baked into images
4. Volumes for persistent data are on encrypted storage (user responsibility)
5. Container networking uses default bridge mode (no `--network=host`)

## Security boundaries

```
┌─────────────────────────────────────────────┐
│  Host (your responsibility)                 │
│  ┌───────────────────────────────────────┐  │
│  │  Docker container (LockClaw Baseline) │  │
│  │                                       │  │
│  │  ┌─────────────┐  ┌───────────────┐  │  │
│  │  │  AI Runtime  │  │  SSH (opt-in) │  │  │
│  │  │  127.0.0.1   │  │  0.0.0.0:22   │  │  │
│  │  └─────────────┘  └───────────────┘  │  │
│  │                                       │  │
│  │  User: lockclaw (non-root)           │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  Host firewall / VPN / reverse proxy        │
└─────────────────────────────────────────────┘
```
