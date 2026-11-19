# syntax=docker/dockerfile:1

# ============================================================
# Stage 1: Node.js 26
# ============================================================
FROM node:26-trixie-slim AS node_runtime

# ============================================================
# Stage 2: sfwbar (desktop bar), built from source
# ============================================================
# Debian has no package for it. Same base as the final image, so
# the binary fits the libraries installed there.
# To update: set the version and the SHA-256 of its tarball.
FROM python:3.15-slim-trixie AS sfwbar_build

ARG SFWBAR_VERSION=1.0_beta17
ARG SFWBAR_SHA256=a4915bc7dd0873c45d0d6b01b070e39a91fd16cfadf730d6a9e48db68a8cd09e

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      meson \
      ninja-build \
      pkg-config \
      libgtk-3-dev \
      libgtk-layer-shell-dev \
      libjson-c-dev \
      libwayland-dev \
      wayland-protocols; \
    rm -rf /var/lib/apt/lists/*

# All optional modules off: the bar only needs the taskbar, the
# pager and menus.
RUN set -eux; \
    curl -fsSL \
      "https://github.com/LBCrion/sfwbar/archive/refs/tags/v${SFWBAR_VERSION}.tar.gz" \
      -o /tmp/sfwbar.tar.gz; \
    echo "${SFWBAR_SHA256}  /tmp/sfwbar.tar.gz" | sha256sum -c -; \
    mkdir /src; \
    tar -xzf /tmp/sfwbar.tar.gz -C /src --strip-components=1; \
    cd /src; \
    meson setup build \
      --prefix=/usr/local \
      --buildtype=release \
      -Dauto_features=disabled \
      -Dappmenu=disabled; \
    ninja -C build; \
    DESTDIR=/out ninja -C build install

# ============================================================
# Stage 3: Python 3.15 + Debian 13 Trixie
# ============================================================
FROM python:3.15-slim-trixie

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
# libatomic1 and libstdc++6: runtime libraries for Node
# libgtk-3-0t64, libgtk-layer-shell0 and libjson-c5: runtime
# libraries for sfwbar
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
      libstdc++6 \
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
      xfce4-terminal \
      fuzzel \
      libgtk-3-0t64 \
      libgtk-layer-shell0 \
      libjson-c5 \
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
# npm 12 (the Node image still bundles npm 11)
# ------------------------------------------------------------
RUN npm install --global npm@12 \
    && rm -rf /root/.npm

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
RUN npm install --global @playwright/mcp@latest \
    && rm -rf /root/.npm

# ------------------------------------------------------------
# Non-root agent user
# Match the host user's UID/GID for workspace file permissions.
# --non-unique: the host GID may already exist in the image
# (e.g. 100 = users).
# ------------------------------------------------------------
RUN groupadd --non-unique --gid "$HOST_GID" node \
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
# Desktop bar and configuration (Sway + sfwbar)
# ------------------------------------------------------------
# Late in the file so config changes don't rebuild the layers
# above. COPY creates root-owned files the agent cannot change.
COPY --from=sfwbar_build /out/usr/local/ /usr/local/
COPY desktop/ /etc/foxden/

# Defaults that programs only read from their own directories.
COPY desktop/fuzzel.ini /etc/xdg/fuzzel/fuzzel.ini
COPY desktop/xfce4-terminal.xml \
    /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml
COPY desktop/chromium-lock.sh /etc/chromium.d/foxden-lock

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
