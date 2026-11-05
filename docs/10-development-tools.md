[← Overview](../README.md)

# Development tools

The image contains, among other things:

- Python 3.15.2 and pip.
- Node.js 26, npm and npx.
- Git.
- curl.
- jq.
- ripgrep.
- Build and compiler tools.
- Chromium.
- Playwright MCP.
- Sway, Waybar, swaybg and mako.
- foot, fuzzel and Thunar.
- wayvnc.
- grim and wlrctl.
- mesa-utils (`eglinfo`, `glxinfo`) to check the GPU.

No coding agent and no IDE: those come from your layers
([Layers](08-layers.md)).

Check versions:

```bash
./foxden.sh ~/projects/my-repo
```

Inside the container:

```bash
python --version
pip --version
node --version
npm --version
git --version
```

Add more languages and tools in your own layers.
