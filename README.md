# foxden

An isolated workspace for coding agents on Linux with
Docker Engine, natively (e.g. Ubuntu) or in WSL2 on
Windows. The agent works in a Linux container with a
desktop, browser and normal internet access. It can change
project files but can't commit or push.

foxden doesn't ship a coding agent. You add the harnesses,
IDEs and services you want as your own Dockerfile layers on
top of the base image.

Prototype for local development.

## Prerequisites

- Linux with Docker Engine (without Docker Desktop): native,
  e.g. Ubuntu, or WSL2 on Windows
- a VNC viewer, e.g. TigerVNC
- a Git repository or a folder with several repositories

Details: [Prerequisites](docs/03-prerequisites.md)

## Quick start

Put foxden outside your projects:

```bash
git clone https://github.com/Foxfire1st/foxden.git \
  ~/.local/share/foxden
S=~/.local/share/foxden/foxden.sh
```

Start the container and desktop. The first build takes a
few minutes:

```bash
$S ~/projects/my-repo --desktop
```

Connect the VNC viewer to `localhost:5900`. The desktop has
a bar with a start menu at the top. On WSL2 you can paste
images from the Windows clipboard there with Ctrl+V.

Add your harness as a layer, for example the Cursor CLI
(more examples in [Layers](docs/08-layers.md)):

```bash
mkdir -p ~/.config/foxden/my-tools
cat > ~/.config/foxden/my-tools/Dockerfile <<'EOF'
ARG BASE=foxden-base:local
FROM ${BASE}
USER root
RUN HOME=/opt/cursor-agent bash -c 'curl -fsSL https://cursor.com/install | bash' \
    && ln -s /opt/cursor-agent/.local/bin/agent /usr/local/bin/agent
USER node
EOF
echo ~/.config/foxden/my-tools > ~/.config/foxden/layers
```

The next start builds the layer. Sign in once and open the
link it shows in your normal browser outside the container
(on WSL2: the Windows browser):

```bash
$S ~/projects/my-repo env NO_OPEN_BROWSER=1 agent login
```

Start the agent:

```bash
$S ~/projects/my-repo agent
```

Without a command, `$S ~/projects/my-repo` opens a shell in
the container.

Several repositories together: pass the parent folder
instead of the repository, e.g. `$S ~/projects/my-product`.

## Day to day

| What | How |
|---|---|
| Shell in the container | `$S ~/projects/my-repo` |
| Harnesses, IDEs, services | your layers, see [Layers](docs/08-layers.md) |
| End a session | `$S ~/projects/my-repo --stop`, reports uncommitted changes |
| Remove the container | `$S ~/projects/my-repo --down` |
| Logs of local Docker stacks | `foxden-logs.sh follow`, see [Container logs](docs/11-filesystem-and-persistence.md#container-logs) |
| Turn on the GPU | `echo NVIDIA > ~/.config/foxden/gpu`, see [GPU](docs/09-gpu.md) |

You review, commit and push the agent's changes on the
host.

## Key rules

1. No Git credentials in the container, not even in an IDE
   in the container.
2. Don't attach the host IDE to the container with Dev
   Containers.
3. Review the agent's changes before the host runs them:
   Git hooks, `compose.yaml`, build scripts.
4. Only test accounts in the container's browser, no SSO.
   Open sign-in links in your normal browser.
5. End sessions with `--stop` and review the changes it
   reports.
6. Turn off "Send clipboard to server" in TigerVNC.
7. Keep your layers outside every folder you share with the
   agent.

Reasons: [Security model](docs/02-security-model.md)

## Documentation

1. [Architecture](docs/01-architecture.md)
2. [Security model](docs/02-security-model.md)
3. [Prerequisites](docs/03-prerequisites.md)
4. [Project files](docs/04-project-files.md)
5. [First start](docs/05-first-start.md)
6. [Graphical desktop](docs/06-desktop.md)
7. [Browser and screenshots](docs/07-browser-and-screenshots.md)
8. [Layers: harnesses, IDEs and services](docs/08-layers.md)
9. [GPU](docs/09-gpu.md)
10. [Development tools](docs/10-development-tools.md)
11. [Filesystem and persistence](docs/11-filesystem-and-persistence.md)
12. [Internet access](docs/12-internet-access.md)
13. [Managing containers](docs/13-managing-containers.md)
14. [Tests](docs/14-tests.md)
15. [Troubleshooting](docs/15-troubleshooting.md)
16. [Roadmap](docs/16-roadmap.md)
17. [Further reading](docs/17-further-reading.md)

Test reports: [test-reports/](test-reports/)
