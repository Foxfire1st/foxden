[← Overview](../README.md)

# Architecture

| Component | Implementation |
|---|---|
| Operating system | Debian 13 Trixie |
| Python | 3.15.x |
| Node.js | 26.x |
| Coding agents, IDEs, services | your own layers on top of the base image ([Layers](08-layers.md)) |
| Desktop | Sway (Wayland) with Waybar and a start menu |
| VNC server | wayvnc |
| VNC proxy | `vnc-paste-proxy.py` on the host, pastes images with Ctrl+V |
| Browser | Chromium |
| Browser automation | Playwright MCP (installed, not yet wired up) |
| GPU | optional, WSL2 only (`/dev/dxg`, Mesa d3d12) |
| Container runtime | Docker Engine + Compose |
| Network | Docker bridge, normal internet access |

Docker Desktop, Docker Sandboxes, extra proxies and
network allowlists are not needed.

## Layout

```text
Host: Linux, native (e.g. Ubuntu) or WSL2 on Windows
├── Editor / IDE
├── VNC viewer
├── Docker Engine
├── VNC proxy (vnc-paste-proxy.py)
├── Project directories
├── Git and host credentials
├── ~/.config/foxden/layers (your layers)
│
└── Docker container
    ├── Debian Trixie
    ├── Python 3.15
    ├── Node.js 26
    ├── your layers: harnesses, IDEs, services
    ├── Sway desktop, Waybar, Chromium
    ├── Playwright MCP
    ├── wayvnc
    ├── /AGENTS.md (rules for the agent, RO)
    ├── /logs (container logs, RO)
    └── /workspace
        ├── project files (RW)
        ├── .git of every repository (RO)
        └── untracked .env files (masked)
```

On WSL2, the editor and the VNC viewer usually run on
Windows, and everything else in WSL.

The desktop and all agent processes run inside the same
container.

Docker still uses the host's kernel (on WSL2, the WSL
kernel). This is container isolation, not a full virtual
machine with its own kernel.
