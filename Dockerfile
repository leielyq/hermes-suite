# =============================================================================
# Hermes Suite — All-in-One Container Image
#
# ⚠ 警示记录 (2026-11-11)
# 现象: 2026-10-15 起 CI 对 hermes-agent v0.22.1+ 的自动构建连续失败
#       (exit 1 at `npm install`, ~2min/run), v0.22.1→v0.23.1 共 8 个版本
#       未能发布镜像; Docker Hub 最后成功镜像停在 2026.9.24。
# 根因: 上游 v0.x 重构 — ① package.json 增加 preinstall 守卫, 拒绝 npm,
#       要求 pnpm (pm/lock.json); ② 基础镜像改由 pm 预置 Chromium 于
#       /opt/hermes/tools (PLAYWRIGHT_BROWSERS_PATH 由基础镜像声明),
#       不再需要 `npx playwright install`; ③ pm-pinned uv 不再暴露到
#       PATH, 下游镜像不可直接调用 uv。
# 修复: Stage 3 仅保留 whatsapp-bridge 移除; Stage 4 改用系统 python3
#       `python3 -m venv` 安装 supervisord; Stage 6 不再覆盖
#       PLAYWRIGHT_BROWSERS_PATH。验证: commit "Fix build against
#       hermes-agent v0.x (pnpm guard, pm-staged chromium, no uv)"
#       构建绿灯 + docker exec hermes-suite supervisorctl status 全 RUNNING。
#
# Combines: hermes-agent + hermes-dashboard
#
# Solves Podman v3.4.4 UID/GID sharing limitation between multiple containers
# by running both services in a single container under one user.
#
# Services:
#   hermes-gateway   — Agent gateway on port 8642 (CLI, Telegram, cron, tools)
#   hermes-dashboard — Built-in monitoring dashboard on port 9119
#
# Build:  podman build -t hermes-suite:2026.9.21 .
# Run:    podman-compose up -d
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Use the official hermes-agent image as the base
# This already contains: Python 3.13, Node.js, npm, Playwright, agent code,
# the built-in web dashboard (hermes dashboard), the gateway, uv, and s6-overlay.
# ---------------------------------------------------------------------------
ARG AGENT_VERSION=v2026.7.20
ARG ENABLE_WHATSAPP_BRIDGE=false
FROM docker.io/nousresearch/hermes-agent:${AGENT_VERSION}

USER root

# ---------------------------------------------------------------------------
# Stage 2: Install system dependencies needed by all services
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        sudo \
        git \
        curl \
        nano \
        net-tools \
        iputils-ping \
        iproute2 \
        openssh-client \
        procps \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# Allow hermes user to use sudo without password
RUN echo "hermes ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ---------------------------------------------------------------------------
# Stage 3: WhatsApp bridge removal
# Since hermes-agent v0.x the base image ships node deps and a pm-pinned
# Chromium under /opt/hermes/tools (with its shared libs), so no npm install
# or playwright download is needed here — upstream's package.json now rejects
# plain `npm install` in favor of pnpm anyway (pm/lock.json).
# WhatsApp bridge is removed by default (ENABLE_WHATSAPP_BRIDGE=false).
# Set --build-arg ENABLE_WHATSAPP_BRIDGE=true or use --whatsapp flag in
# build.sh to keep it.
# ---------------------------------------------------------------------------
RUN if [ "$ENABLE_WHATSAPP_BRIDGE" != "true" ]; then rm -rf /opt/hermes/scripts/whatsapp-bridge; fi

# ---------------------------------------------------------------------------
# Stage 4: Install supervisord (not available in Debian Trixie apt)
# The base image's uv is pm-pinned and deliberately not exposed on PATH
# ("build consumers receive Python environments, never an installer"), so
# we build a dedicated venv with the system python3's stdlib venv+pip.
# ---------------------------------------------------------------------------
RUN python3 -m venv /opt/supervisor && \
    /opt/supervisor/bin/pip install --no-cache-dir supervisor && \
    ln -sf /opt/supervisor/bin/supervisord /usr/local/bin/supervisord && \
    ln -sf /opt/supervisor/bin/supervisorctl /usr/local/bin/supervisorctl

RUN mkdir -p /var/log/supervisor /var/run/supervisor && \
    chown -R hermes:hermes /var/log/supervisor /var/run/supervisor

# ---------------------------------------------------------------------------
# Stage 5: Set up supervisord config and startup script
# ---------------------------------------------------------------------------
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY start.sh /opt/hermes-suite/start.sh
RUN chmod +x /opt/hermes-suite/start.sh

# Custom services: supervisord.conf [include]s /etc/supervisor/conf.d/*.conf.
# Create the directory so the include stays valid even without the volume
# mounted (docker-compose.yaml mounts ./supervisor.d here at runtime).
RUN mkdir -p /etc/supervisor/conf.d

# ---------------------------------------------------------------------------
# Patch: disable dashboard auto-sso — the upstream middleware auto-redirects
# to /auth/login (OAuth start) when a single provider is registered, but
# BasicAuthProvider is password-only and raises NotImplementedError there.
# Skip it so unauthenticated requests go directly to /login (password form).
# ---------------------------------------------------------------------------
RUN sed -i 's/auto = _auto_sso_response(request)/auto = None  # disabled: BasicAuthProvider has no OAuth start flow/'     /opt/hermes/hermes_cli/dashboard_auth/middleware.py

# ---------------------------------------------------------------------------
# Stage 6: Environment, labels, and runtime config
# ---------------------------------------------------------------------------
# Re-declare ARGs after FROM so they are available in LABEL
ARG AGENT_VERSION=v2026.7.20
ARG ENABLE_WHATSAPP_BRIDGE=false

LABEL org.opencontainers.image.title="Hermes Suite" \
      org.opencontainers.image.description="All-in-one: hermes-agent + hermes-dashboard" \
      org.opencontainers.image.source="https://github.com/sunnysktsang/hermes-suite" \
      org.opencontainers.image.vendor="sunnysktsang" \
      hermes-suite.agent-version="${AGENT_VERSION}"

ENV PATH="/opt/hermes/.venv/bin:$PATH"
ENV HERMES_HOME=/opt/data
ENV HERMES_DATA_DIR=/opt/data
# PLAYWRIGHT_BROWSERS_PATH is intentionally NOT overridden: the v0.x base
# image points it at the pm-pinned Chromium store (/opt/hermes/tools).

# hermes-agent web dist (built into the base image)
ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist

# Expose all service ports
EXPOSE 8642 9119

# Workspace directory
RUN mkdir -p /workspace

WORKDIR /opt/hermes

# Entrypoint: run start.sh which sets up config then launches supervisord
ENTRYPOINT ["/opt/hermes-suite/start.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
