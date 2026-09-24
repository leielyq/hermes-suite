# =============================================================================
# Hermes Suite — All-in-One Container Image
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
# Stage 3: Install Browser tool dependencies for agent
# npm install + Playwright chromium (needed by browser toolset)
# WhatsApp bridge is removed by default (ENABLE_WHATSAPP_BRIDGE=false).
# Set --build-arg ENABLE_WHATSAPP_BRIDGE=true or use --whatsapp flag in
# build.sh to include it.
# ---------------------------------------------------------------------------
RUN cd /opt/hermes && \
    npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium && \
    if [ "$ENABLE_WHATSAPP_BRIDGE" != "true" ]; then rm -rf /opt/hermes/scripts/whatsapp-bridge; fi && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Stage 4: Install supervisord via uv (not available in Debian Trixie apt)
# We install it into a dedicated venv at /opt/supervisor.
# ---------------------------------------------------------------------------
RUN uv venv /opt/supervisor && \
    uv pip install --python /opt/supervisor/bin/python3 supervisor && \
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
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

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
