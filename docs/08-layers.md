[← Overview](../README.md)

# Layers: harnesses, IDEs and services

The foxden base image contains no coding agent. You add
harnesses, IDEs and services yourself, as Dockerfiles that
build on top of the base. These are called layers.

## How it works

List your layer directories in `~/.config/foxden/layers`,
one per line. `#` starts a comment, `~/` is allowed:

```text
~/.config/foxden/my-tools
~/src/my-dashboard/foxden
```

Each directory contains a `Dockerfile` that starts like
this:

```dockerfile
ARG BASE=foxden-base:local
FROM ${BASE}
```

The launcher builds the base image (`foxden-base:local`),
then each layer in list order as `foxden-layer1:local`,
`foxden-layer2:local`, …, passing the previous image as
`BASE`. The container runs the last image. Without the file
or with an empty list, it runs the base.

The images are built on every start. Docker's cache makes
that fast when nothing changed. If an image changes, the
container is recreated and running sessions end. For fresh
downloads without cache:

```bash
FOXDEN_REBUILD=1 ./foxden.sh ~/projects/my-repo --desktop
```

## Rules for layers

- **Keep layer directories outside every folder you share
  with the agent.** A layer defines the agent's image. The
  launcher refuses a layer that is inside the shared
  folder or contains it. It can't see folders shared by
  other foxden containers, so keep layers out of those too.
- **Install as root into system paths** such as
  `/usr/local` or `/opt`, not into `/home/node`. The agent
  home is a volume that Docker fills from the image only
  when it's first created. Anything added to `/home/node`
  later stays hidden behind an existing volume.
- **End with `USER node`.** The container runs as your host
  user anyway, but builds of later layers expect it.
- Tools installed as root can't update themselves. Update
  them with `FOXDEN_REBUILD=1`.

You can also install tools at runtime in a shell
(`./foxden.sh ~/projects/my-repo`). They end up in the agent
home of that shared folder only.

## Start hooks

Executable files in `/etc/foxden/start.d/` run on every
launcher start: as the agent user, in `/workspace`, after
the desktop is up, with the variables from
`~/.config/foxden/env` (see below).

A hook must:

- start its services in the background (`nohup … &`) and
  return within 60 seconds,
- not start a service that is already running.

The output goes to `start-hooks.log`, shown by
`--desktop-logs`. A failing hook prints a warning; the start
continues.

```dockerfile
ARG BASE=foxden-base:local
FROM ${BASE}
USER root
RUN printf '%s\n' '#!/bin/sh' \
      'pgrep -f my-dashboard >/dev/null && exit 0' \
      'nohup my-dashboard --port 8787 >/tmp/agent-runtime/my-dashboard.log 2>&1 &' \
      > /etc/foxden/start.d/50-my-dashboard \
    && chmod 755 /etc/foxden/start.d/50-my-dashboard
USER node
```

## Ports

A layer directory may contain a `ports` file with
`HOST:CONTAINER` per line:

```text
8787:8787
```

The launcher always publishes these ports on `127.0.0.1`.
Open `http://localhost:8787` in your normal browser (on
WSL2 from Windows).

Layers can't add mounts, devices or other Compose settings.
A Compose file could mount any host path or the Docker
socket.

Pages served from the container are under the agent's
control:

- Open them in a separate browser profile. Browsers don't
  separate cookies by port, so a page on one `localhost`
  port can read cookies of other `localhost` apps.
- Approvals in such a page are not a security boundary. The
  agent runs in the same container and can call the same
  service.

## Passing variables

`~/.config/foxden/env` lists names of host variables, one
per line, e.g. API keys:

```text
ANTHROPIC_API_KEY
OPENAI_API_KEY
CURSOR_API_KEY
```

If a variable is set when you call the launcher, it is
passed to your command and to the start hooks. Values
appear briefly in the host's process list, as arguments of
`docker compose exec`.

## Agent rules

The base image contains the rules from `agent-rules.md` as
`/AGENTS.md`. Harnesses read instructions from different
places:

| Harness | Reads | What to do |
|---|---|---|
| Cursor CLI | `AGENTS.md` in all parent directories | nothing, `/AGENTS.md` is found |
| Claude Code | its system-wide file `/etc/claude-code/CLAUDE.md`, not `AGENTS.md` | link it in the layer, see below |
| Codex | `~/.codex/AGENTS.md` | link it from a start hook, see below |

Files in the agent home can be changed by the agent. The
rules are an addition either way; the protection relies on
the technical barriers.

## Signing in

Open a shell (`./foxden.sh ~/projects/my-repo`) and run the
harness's login. Open the link it shows in your normal
browser outside the container, not in the container's
Chromium.

- Logins that show a code to paste back, or that wait for
  the sign-in on the server, work this way.
- Logins that redirect the browser to a `localhost` port in
  the container can't complete from outside. Use the
  harness's device code login or an API key instead.

Sign-ins are stored in the agent home of the shared folder
and are readable by the agent.

## Examples

Put them into one layer or split them across several.
Tested in foxden: Cursor CLI and Cursor IDE. Claude Code and
Codex are not tested here yet.

### Cursor CLI

```dockerfile
ARG BASE=foxden-base:local
FROM ${BASE}
USER root
# The installer uses $HOME: install into /opt, not the agent home.
RUN HOME=/opt/cursor-agent bash -c 'curl -fsSL https://cursor.com/install | bash' \
    && ln -s /opt/cursor-agent/.local/bin/agent /usr/local/bin/agent
USER node
```

Start with `./foxden.sh ~/projects/my-repo agent`. Sign in
with `./foxden.sh ~/projects/my-repo env NO_OPEN_BROWSER=1 agent login`
and open the URL in your normal browser. Alternatively list
`CURSOR_API_KEY` in `~/.config/foxden/env`.

### Cursor IDE

```dockerfile
ARG BASE=foxden-base:local
FROM ${BASE}
USER root
# Official, signed APT repository. Like Chromium, the IDE can't
# use its own sandbox in the hardened container, so it starts
# through the cursor-ide wrapper with --no-sandbox.
RUN set -eux; \
    curl -fsSL https://downloads.cursor.com/keys/anysphere.asc \
      -o /usr/share/keyrings/anysphere.asc; \
    printf '%s\n' \
      'Types: deb' \
      'URIs: https://downloads.cursor.com/aptrepo' \
      'Suites: stable' \
      'Components: main' \
      'Architectures: amd64' \
      'Signed-By: /usr/share/keyrings/anysphere.asc' \
      > /etc/apt/sources.list.d/cursor.sources; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends cursor; \
    rm -rf /var/lib/apt/lists/*; \
    printf '%s\n' \
      '#!/bin/sh' \
      'exec /usr/share/cursor/cursor --no-sandbox "$@"' \
      > /usr/local/bin/cursor-ide; \
    chmod 755 /usr/local/bin/cursor-ide; \
    mkdir -p /usr/local/share/applications; \
    sed 's|^Exec=/usr/share/cursor/cursor|Exec=/usr/local/bin/cursor-ide|' \
      /usr/share/applications/cursor.desktop \
      > /usr/local/share/applications/cursor.desktop
USER node
```

Start it from "All programs …" on the desktop, or from the
host with
`./foxden.sh ~/projects/my-repo swaymsg exec cursor-ide`.
The window stays white for a few seconds until the
interface has loaded.

Sign in:

1. Click "Log In" in the IDE. Chromium opens in the
   container with the sign-in page. Don't sign in there.
2. Copy the link from the address bar (Ctrl+L, Ctrl+C).
   The VNC viewer transfers it to your desktop's clipboard.
3. Open the link in your normal browser and sign in there.
   After a few seconds the IDE in the container is signed
   in.
4. Close the Chromium tab in the container.

If the IDE then asks about the keyring ("An OS keyring
couldn't be identified …"), choose the weaker encryption.
A keyring in the container wouldn't protect the data from
the agent ([Security model](02-security-model.md), rule 1).

With the GPU turned on, the IDE renders on the GPU. With
`--ozone-platform=x11` it doesn't start then (black windows,
"launch-failed"); keep the default, Wayland.

### Claude Code

```dockerfile
ARG BASE=foxden-base:local
FROM ${BASE}
USER root
RUN npm install --global @anthropic-ai/claude-code \
    && mkdir -p /etc/claude-code \
    && ln -s /AGENTS.md /etc/claude-code/CLAUDE.md
USER node
```

Start with `./foxden.sh ~/projects/my-repo claude`. To sign
in, open the link it shows in your normal browser and paste
the code back. Alternatively list `ANTHROPIC_API_KEY` in
`~/.config/foxden/env`.

### Codex

```dockerfile
ARG BASE=foxden-base:local
FROM ${BASE}
USER root
RUN npm install --global @openai/codex
# Codex reads ~/.codex/AGENTS.md in the agent home volume,
# so a start hook links the rules there on every start.
RUN printf '%s\n' '#!/bin/sh' \
      'mkdir -p "$HOME/.codex"' \
      'ln -sf /AGENTS.md "$HOME/.codex/AGENTS.md"' \
      > /etc/foxden/start.d/10-codex-rules \
    && chmod 755 /etc/foxden/start.d/10-codex-rules
USER node
```

Start with `./foxden.sh ~/projects/my-repo codex`. Codex's
browser login redirects to a `localhost` port in the
container and doesn't complete from outside. Use
`codex login --device-auth` (device code login must be
allowed in your ChatGPT security settings) or list
`OPENAI_API_KEY` in `~/.config/foxden/env`.
