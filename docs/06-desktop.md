[← Overview](../README.md)

# Graphical desktop

The container uses Sway as its Wayland compositor, a
tiling window manager in the style of i3. Sway is the
display server in the container: it provides the virtual
screen, manages the windows and gives wayvnc the picture
as well as mouse and keyboard.

Sway renders in software, so it needs no GPU (WSL2
doesn't provide a DRM device anyway). Programs like Chromium or an IDE can
optionally use the GPU ([GPU](09-gpu.md)).

The desktop has:

- A bar at the top (Waybar) with a start menu, a taskbar
  of open windows, workspaces, CPU, RAM and a clock.
- A start menu with Terminal, Chromium, Files and
  "All programs …" (program search, also lists IDEs from
  your layers).
- A plain dark background.
- Notifications (mako).

Programs: `foot` (terminal), `fuzzel` (program search),
`thunar` (file manager), Chromium, plus whatever your
layers install.

The clock shows UTC, because the container runs in UTC.

**Known issue:** the menu entries Terminal, Chromium and
Files block the bar while the program they started is
open. A second click on "Start" then opens no menu, and the
taskbar doesn't update. Workaround: start programs with Alt+Enter, Alt+D or from
the terminal (see
[Roadmap](16-roadmap.md)).

## Start programs from the console

You can open programs on the desktop from the host without
clicking in the VNC viewer:

```bash
./foxden.sh ~/projects/my-repo swaymsg exec foot
./foxden.sh ~/projects/my-repo swaymsg exec "chromium https://example.com"
```

The window appears on the desktop in the container, so in
the VNC viewer, not as its own window on your desktop. The
console is free again right away.

Separate windows directly on your desktop aren't possible with
VNC; VNC always shows the whole screen. Alt+F switches a
program to full screen, or you can put it on its own
workspace.

## Keyboard shortcuts

The modifier is Alt, because VNC viewers usually keep the
Windows/Super key for themselves.

| Keys | Action |
|---|---|
| Alt+Enter | Terminal |
| Alt+D | Program search |
| Alt+Shift+Q | Close window |
| Alt+1 … 9 | Switch workspace |
| Alt+Shift+1 … 9 | Move window to workspace |
| Alt+arrows, Alt+H/J/K/L | Move focus |
| Alt+Shift+arrows | Move window |
| Alt+F | Full screen |
| Alt+W / Alt+S / Alt+E | Tabbed / stacked / split |
| Alt+B / Alt+V | Next window to the right / below |
| Alt+Shift+Space | Floating window |
| Alt+R | Resize (arrows, then Enter) |
| Alt+Shift+C | Reload configuration |

Your desktop usually intercepts Alt+Tab and Alt+F4.

In the taskbar, a click brings a window to the front and a
middle click closes it.

## Customize the desktop

The configuration is in `desktop/` and is copied into the
image at `/etc/foxden/`:

| File | Content |
|---|---|
| `sway.conf` | Shortcuts, look, autostart |
| `waybar.jsonc` | Layout of the bar |
| `waybar.css` | Colors of the bar |
| `start-menu.xml` | Start menu entries |

New start menu entry: a `GtkMenuItem` in `start-menu.xml`
and a matching command under `menu-actions` in
`waybar.jsonc`. The entry's `id` is the key in
`menu-actions`.

Changes are built into the image the next time the launcher
runs. That recreates the container. Reconnect the VNC
viewer afterwards.

## Default resolution

1920 × 1080 pixels (Full HD)

## Other resolutions

QHD:

```bash
DESKTOP_WIDTH=2560 DESKTOP_HEIGHT=1440 \
./foxden.sh ~/projects/my-repo --desktop
```

4K:

```bash
DESKTOP_WIDTH=3840 DESKTOP_HEIGHT=2160 \
./foxden.sh ~/projects/my-repo --desktop
```

The environment variables are:

| Variable | Default |
|---|---|
| DESKTOP_WIDTH | 1920 |
| DESKTOP_HEIGHT | 1080 |
| VNC_PORT | 5900 |

For software rendering, Full HD is the recommended
starting point.

## VNC connection

Open a VNC viewer on your desktop.

Address:

```text
localhost:5900
```

On WSL2, Windows forwards `localhost` ports to WSL by
default. If it doesn't, check local reachability
separately.

For a different local port:

```bash
VNC_PORT=5901 \
./foxden.sh ~/projects/my-repo --desktop
```

Then:

```text
localhost:5901
```

The viewer connects to the proxy `vnc-paste-proxy.py`,
which the launcher starts on the host. The proxy only
listens on the loopback address and forwards to wayvnc.
wayvnc itself is published on a random port, also only on
the loopback address.

**Important:** wayvnc currently has no extra
authentication configured.

The VNC port must not be exposed publicly.

## Pasting images

Only on WSL2 for now. On native Linux the proxy just
forwards VNC; image paste is on the
[Roadmap](16-roadmap.md).

You can paste an image from the Windows clipboard, such as
a snip taken with Win+Shift+S, into the VNC window with
Ctrl+V, e.g. into the chat of an IDE.

VNC itself only carries text. The proxy spots Ctrl+V from
the viewer, fetches the image as PNG through
`powershell.exe` and puts it into the container's
clipboard with `wl-copy`. Only then does it forward the
key. This takes about 0.1 seconds.

If the clipboard also holds text, for example when copying
Excel cells, TigerVNC's normal text sync applies.

The launcher starts the proxy with the desktop and stops it
with `--stop` and `--down`. Running the launcher again
keeps a running proxy and the VNC connection. The log is
shown by `--desktop-logs`.

Security: [Security model](02-security-model.md), rule 6.
