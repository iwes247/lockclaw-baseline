# LockClaw Baseline

LockClaw enforces locked-down defaults for containerized AI runtimes.

It prevents accidental exposure caused by unsafe container configuration.

> ⚠️ Baseline is **not** host hardening. For host firewalling and OS-level controls, use [lockclaw-appliance](https://github.com/iwes247/lockclaw-appliance).

## What it does (v1)

- Fail-closed startup preflight before runtime startup
- Port allowlist validation from `lockclaw-core` policy
- Read-only root filesystem
- `/data` as the only writable persistent path
- Runtime tmpfs mounts (`/tmp`, `/run`, `/var/tmp`)
- `no-new-privileges` and dropped capabilities by default
- Startup posture logging for mode + allowed ports + writable paths
- Hobby/Builder policy modes (`LOCKCLAW_MODE`)

## What it is NOT

- Not a dashboard
- Not SaaS
- Not an agent firewall
- Not prompt inspection
- Not host hardening

## Quickstart (60 seconds)

```bash
docker compose up -d openclaw
docker compose logs -f openclaw
```

Default mode is Hobby (`LOCKCLAW_MODE=hobby`).

Expected startup includes:

- Mode shown (`hobby`)
- Root FS shown as read-only
- Writable paths shown as `/data`
- Outbound banner: allowed, not enforced in baseline v1
- `Pre-flight PASSED`

## Threat model focus (v1)

LockClaw baseline v1 focuses on accidental exposure from:

- Unsafe port publishing / unexpected listeners
- RW filesystems and writable mounts outside `/data`
- Over-privileged container capabilities

Outbound enforcement is **not included** in baseline v1.

## Modes

### Hobby

- Default mode
- Strict preflight checks enabled
- Outbound posture logged as allowed

### Builder

- Uses the same preflight enforcement checks
- Intended for build workflows with the same locked-down posture contract
- Outbound posture logged as allowed (banner-only logging intent)

## Validation

```bash
docker exec lockclaw-openclaw /opt/lockclaw/scripts/test-smoke.sh
```

## Related

- [lockclaw-core](https://github.com/iwes247/lockclaw-core) — policy + preflight single source of truth
- [lockclaw-appliance](https://github.com/iwes247/lockclaw-appliance) — host-level hardening and optional hard network controls

## License

MIT — see [LICENSE](LICENSE).
