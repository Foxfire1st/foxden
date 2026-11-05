[← Overview](../README.md)

# Project files

```text
foxden/
├── Dockerfile
├── compose.yaml
├── foxden.sh
├── foxden-logs.sh
├── agent-rules.md
├── vnc-paste-proxy.py
├── desktop/
│   ├── sway.conf
│   ├── waybar.jsonc
│   ├── waybar.css
│   └── start-menu.xml
├── docs/
├── test-reports/
│   └── 00-template.md
├── .dockerignore
├── .gitattributes
└── README.md
```

| File | Purpose |
|---|---|
| `Dockerfile` | Base image with tools, desktop and Chromium, no coding agent |
| `compose.yaml` | Container, hardening, fixed mounts, VNC port |
| `foxden.sh` | Launcher: builds base and layers, start, mounts, masking, start hooks, reports |
| `foxden-logs.sh` | Export container logs on the host |
| `agent-rules.md` | Rules for the agent, `/AGENTS.md` in the image |
| `vnc-paste-proxy.py` | VNC proxy on the host: pastes images from the Windows clipboard |
| `desktop/` | Desktop configuration, `/etc/foxden/` in the image |
| `docs/` | Documentation, linked from the README |
| `test-reports/` | Test reports and template ([Tests](14-tests.md)) |
| `.gitattributes` | LF line endings, so the scripts still run after a Windows checkout |

The foxden configuration must be outside all shared
directories. Otherwise the launcher aborts, because the
agent could change its own protection rules.

For example:

```bash
git clone https://github.com/Foxfire1st/foxden.git \
  ~/.local/share/foxden
```

The scripts are already stored as executable in the
repository.
