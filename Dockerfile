# LockClaw Baseline — Multi-stage Dockerfile
# Secure-by-default deployment baseline for AI runtimes.
#
# Targets:
#   base     — minimal secure container (bring your own runtime)
#   openclaw — base + OpenClaw gateway + claude-mem
#   ollama   — base + Ollama for local LLM inference
#
# Build:
#   docker build --target base     -t lockclaw:base .
#   docker build --target openclaw -t lockclaw:openclaw .
#   docker build --target ollama   -t lockclaw:ollama .
#   docker build -t lockclaw:latest .       # defaults to openclaw
#
# Run (default — no NET_ADMIN required):
#   docker run -d --name lockclaw lockclaw:latest
#
# Run (with SSH access):
#   docker run -d --name lockclaw \
#     -e SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)" \
#     -e LOCKCLAW_ENABLE_SSH=1 \
#     -p 2222:22 lockclaw:latest

# ═════════════════════════════════════════════════════════════
# PINNED VERSIONS — Update these deliberately, never use @latest.
#
#   To upgrade:  1. Change the ARG default below.
#                2. Run CI (build-and-smoke).
#                3. If green, commit.
#
#   To override at build time:
#     docker build --build-arg OPENCLAW_VERSION=2026.2.21 ...
#
# The CI lint step will hard-fail if @latest appears anywhere
# in this file.  See .github/workflows/build-and-smoke.yml.
# ═════════════════════════════════════════════════════════════

# ═════════════════════════════════════════════════════════════
# Stage 1: BASE — Minimal secure container
# ═════════════════════════════════════════════════════════════
FROM debian:bookworm-slim AS base

LABEL maintainer="iwes247"
LABEL org.opencontainers.image.title="LockClaw Baseline"
LABEL org.opencontainers.image.description="Secure-by-default deployment baseline for AI runtimes"
LABEL org.opencontainers.image.source="https://github.com/iwes247/lockclaw-baseline"

# ── Environment ──────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive
ENV LOCKCLAW_HOME=/opt/lockclaw

# ── Install minimal packages ────────────────────────────────
# Only what's needed for a functional container + diagnostics.
# No nftables, auditd, fail2ban — those are OS/appliance concerns.
COPY packages/baseline.txt /tmp/baseline.txt
RUN apt-get update && \
    grep -hv '^\s*#\|^\s*$' /tmp/baseline.txt \
      | xargs apt-get install -y --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/*.txt

# ── Create non-root user ────────────────────────────────────
RUN useradd -m -s /bin/bash lockclaw && \
    passwd -l lockclaw

# ── Install SSH (optional — activated via LOCKCLAW_ENABLE_SSH) ──
RUN apt-get update && \
    apt-get install -y --no-install-recommends openssh-server && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd && \
    # Harden SSH config even if not enabled by default
    mkdir -p /etc/ssh/sshd_config.d && \
    printf '%s\n' \
      'PermitRootLogin no' \
      'PasswordAuthentication no' \
      'PubkeyAuthentication yes' \
      'MaxAuthTries 3' \
      'X11Forwarding no' \
      'PermitEmptyPasswords no' \
      'Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com' \
      'KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org' \
      'MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com' \
      > /etc/ssh/sshd_config.d/10-lockclaw.conf && \
    chmod 0600 /etc/ssh/sshd_config.d/10-lockclaw.conf && \
    ssh-keygen -A && \
    mkdir -p /home/lockclaw/.ssh && \
    chmod 700 /home/lockclaw/.ssh && \
    chown -R lockclaw:lockclaw /home/lockclaw/.ssh

# ── Copy LockClaw tooling ───────────────────────────────────
COPY scripts/          ${LOCKCLAW_HOME}/scripts/
COPY lockclaw-core/    ${LOCKCLAW_HOME}/lockclaw-core/
RUN chmod +x ${LOCKCLAW_HOME}/scripts/*.sh \
             ${LOCKCLAW_HOME}/lockclaw-core/audit/*.sh

# ── Entrypoint ───────────────────────────────────────────────
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# No EXPOSE by default — services bind loopback only.
# Expose SSH only if LOCKCLAW_ENABLE_SSH=1 at runtime.

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["start"]


# ═════════════════════════════════════════════════════════════
# Stage 2: OPENCLAW — OpenClaw gateway + claude-mem
# ═════════════════════════════════════════════════════════════
FROM base AS openclaw

ARG OPENCLAW_VERSION=2026.2.19-2
ARG CLAUDE_MEM_VERSION=10.3.1
ARG NODE_MAJOR=22

LABEL org.opencontainers.image.description="LockClaw Baseline + OpenClaw AI gateway + claude-mem"

# ── Install Node.js 22 ──────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates gnupg git build-essential python3 && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ── Install OpenClaw gateway ─────────────────────────────────
RUN npm install -g openclaw@${OPENCLAW_VERSION} && \
    npm cache clean --force

# ── Configure OpenClaw workspace ─────────────────────────────
RUN mkdir -p /home/lockclaw/.openclaw/workspace/skills && \
    printf '%s\n' \
      '{' \
      '  "gateway": {' \
      '    "port": 18789,' \
      '    "bind": "loopback"' \
      '  },' \
      '  "agent": {' \
      '    "model": "anthropic/claude-opus-4-6"' \
      '  }' \
      '}' \
      > /home/lockclaw/.openclaw/openclaw.json && \
    chown -R lockclaw:lockclaw /home/lockclaw/.openclaw

# ── Pre-install claude-mem plugin ────────────────────────────
RUN npm install -g claude-mem@${CLAUDE_MEM_VERSION} && \
    npm cache clean --force

# ── Clean up build tools (not needed at runtime) ────────────
RUN apt-get purge -y build-essential python3 && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# OpenClaw listens on 127.0.0.1:18789 (loopback only).
# Access via SSH tunnel: ssh -L 18789:127.0.0.1:18789 ...

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD pgrep -x node > /dev/null || exit 1


# ═════════════════════════════════════════════════════════════
# Stage 3: OLLAMA — Local LLM inference engine
# ═════════════════════════════════════════════════════════════
FROM base AS ollama

ARG OLLAMA_VERSION=0.6.2

LABEL org.opencontainers.image.description="LockClaw Baseline + Ollama local LLM engine"

# ── Install Ollama ───────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends zstd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    curl -fsSL https://ollama.com/install.sh | OLLAMA_VERSION=${OLLAMA_VERSION} sh || true && \
    command -v ollama && \
    ollama --version

# ── Configure Ollama for loopback-only ───────────────────────
ENV OLLAMA_HOST=127.0.0.1:11434
ENV OLLAMA_MODELS=/home/lockclaw/.ollama/models

# ── Create Ollama dirs with correct ownership ────────────────
RUN mkdir -p /home/lockclaw/.ollama/models && \
    chown -R lockclaw:lockclaw /home/lockclaw/.ollama

# Ollama listens on 127.0.0.1:11434 (loopback only).
# Access via SSH tunnel: ssh -L 11434:127.0.0.1:11434 ...

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -sf http://127.0.0.1:11434/ > /dev/null || exit 1
