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
# Run (default locked-down posture):
#   docker run -d --name lockclaw \
#     --read-only \
#     --tmpfs /tmp --tmpfs /run --tmpfs /var/tmp \
#     --security-opt no-new-privileges:true \
#     --cap-drop ALL \
#     -v lockclaw-data:/data \
#     lockclaw:latest

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
ENV LOCKCLAW_DATA_DIR=/data

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

RUN mkdir -p ${LOCKCLAW_DATA_DIR} && \
  chown -R lockclaw:lockclaw ${LOCKCLAW_DATA_DIR}

# ── Copy LockClaw tooling ───────────────────────────────────
COPY scripts/          ${LOCKCLAW_HOME}/scripts/
COPY lockclaw-core/    ${LOCKCLAW_HOME}/lockclaw-core/
RUN chmod +x ${LOCKCLAW_HOME}/scripts/*.sh \
             ${LOCKCLAW_HOME}/lockclaw-core/audit/*.sh

# ── Entrypoint ───────────────────────────────────────────────
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# No EXPOSE by default — services bind loopback only.

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
RUN mkdir -p /data/openclaw/workspace/skills && \
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
      > /data/openclaw/openclaw.json && \
    chown -R lockclaw:lockclaw /data/openclaw

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
ENV OLLAMA_MODELS=/data/ollama/models

# ── Create Ollama dirs with correct ownership ────────────────
RUN mkdir -p /data/ollama/models && \
  chown -R lockclaw:lockclaw /data/ollama

# Ollama listens on 127.0.0.1:11434 (loopback only).
# Access via SSH tunnel: ssh -L 11434:127.0.0.1:11434 ...

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -sf http://127.0.0.1:11434/ > /dev/null || exit 1
