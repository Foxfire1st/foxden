
# syntax=docker/dockerfile:1

# ============================================================
# Stage 1: Node.js 26
# ============================================================
FROM node:26-trixie-slim AS node_runtime

# ============================================================
# Stage 2: Python 3.15.2 + Debian 13 Trixie
# ============================================================
FROM python:3.15.2-slim-trixie

ARG HOST_UID=1000
ARG HOST_GID=1000

# ------------------------------------------------------------
# Node.js 26 + npm + npx
# ------------------------------------------------------------
COPY --from=node_runtime \
    /usr/local/bin/node /usr/local/bin/node

COPY --from=node_runtime \
    /usr/local/lib/node_modules /usr/local/lib/node_modules

COPY --from=node_runtime \
    /usr/local/include/node /usr/local/include/node

RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js \
        /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js \
        /usr/local/bin/npx

# ------------------------------------------------------------
# Development tools + Sway desktop + Chromium
# ------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      jq \
      ripgrep \
      build-essential \
      libatomic1 \
      unzip \
      procps \
      less \
      \
      sway \
      wayvnc \
      chromium \
      xwayland \
      grim \
      wlrctl \
      wl-clipboard \
      mesa-utils \
      dbus-daemon \
      dbus-user-session \
      \
      foot \
      fuzzel \
      waybar \
      swaybg \
      mako-notifier \
      thunar \
      \
      fonts-dejavu-core \
      fonts-liberation \
      fonts-noto-color-emoji; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Chromium defaults: Wayland, no own sandbox
# The container is the boundary. Chromium's sandbox cannot work
# with cap_drop ALL and no-new-privileges.
# ------------------------------------------------------------
RUN printf '%s\n' \
      'export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --ozone-platform=wayland --no-sandbox"' \
      > /etc/chromium.d/foxden

# ------------------------------------------------------------
# Verify language runtimes
# ------------------------------------------------------------
RUN python --version \
    && pip --version \
    && node --version \
    && npm --version \
    && npx --version

# ------------------------------------------------------------
# Browser automation: Playwright MCP
# ------------------------------------------------------------
RUN npm install --global @playwright/mcp@latest

# ------------------------------------------------------------
# Non-root agent user
# Match WSL host UID/GID for workspace file permissions
# ------------------------------------------------------------
RUN groupadd --gid "$HOST_GID" node \
    && useradd \
      --uid "$HOST_UID" \
      --gid node \
      --shell /bin/bash \
      --create-home node \
    && install -d -m 0700 \
      -o node -g node \
      /tmp/agent-runtime \
    && install -d -m 0755 /etc/foxden/start.d

# ------------------------------------------------------------
# Headless Wayland desktop (software rendering)
# No GPU passthrough required
# ------------------------------------------------------------
ENV XDG_RUNTIME_DIR=/tmp/agent-runtime \
    WLR_BACKENDS=headless \
    WLR_RENDERER=pixman \
    WLR_HEADLESS_OUTPUTS=1 \
    WLR_LIBINPUT_NO_DEVICES=1

# ------------------------------------------------------------
# Switch to unprivileged user
# ------------------------------------------------------------
USER node

# ~/.local/bin for tools installed at runtime into the agent home.
ENV HOME=/home/node \
    PATH="/home/node/.local/bin:${PATH}"

# ------------------------------------------------------------
# No coding agent in the base image
# ------------------------------------------------------------
# Harnesses, IDEs and services come from your own layers, built
# on top of this image by foxden.sh (see docs/08-layers.md).

# ------------------------------------------------------------
# Desktop configuration (Sway + Waybar)
# ------------------------------------------------------------
# Late in the file so config changes don't rebuild the layers
# above. COPY creates root-owned files the agent cannot change.
COPY desktop/ /etc/foxden/

# ------------------------------------------------------------
# Agent rules
# ------------------------------------------------------------
# Harnesses that read AGENTS.md in all parent directories (e.g.
# the Cursor CLI) find /AGENTS.md for every project. Layers wire
# it up for harnesses that look elsewhere.
COPY agent-rules.md /AGENTS.md

# ------------------------------------------------------------
# Workspace
# ------------------------------------------------------------
WORKDIR /workspace

# Desktop, start hooks and agents are started by the launcher.
CMD ["sleep", "infinity"]
