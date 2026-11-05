[← Overview](../README.md)

# Troubleshooting

## Launcher error messages

| Message | Cause |
|---|---|
| `… is inside the repository …` | A subfolder of a repository was passed. Pass the repository or the parent folder. |
| `No Git repositories found …` | The directory contains no repository. |
| `.git must not be a symlink …` | A `.git` is a symlink. |
| `Linked worktrees are not supported …` | The directory is a linked Git worktree. |
| `Keep sandbox configuration outside the workspace.` | The foxden files are inside the shared directory. |
| `… with newline cannot be …` | A path contains a newline. |
| `… gpu exists, but WSL GPU support is missing.` | GPU turned on, but `/dev/dxg` or `/usr/lib/wsl/lib` is missing on the host. |
| `Invalid GPU adapter name …` | The file `~/.config/foxden/gpu` contains invalid characters. |
| `python3 is required for the VNC proxy.` | python3 is missing on the host. |
| `VNC proxy failed to start.` | The VNC port is taken, for example by a second sandbox. Choose a different `VNC_PORT`. |
| `Cannot find the published wayvnc port.` | The container isn't running. |
| `Layer without Dockerfile: …` | A line in `~/.config/foxden/layers` isn't a directory with a `Dockerfile`. |
| `Keep layers outside the workspace: …` | A layer is inside the shared directory or contains it. |
| `Invalid port … (use HOST:CONTAINER)` | A line in a layer's `ports` file is invalid. |
| `Invalid variable name … in …/env` | A line in `~/.config/foxden/env` isn't a variable name. |
| `WARNING: Start hook failed: …` | A start hook failed or ran longer than 60 seconds. Details with `--desktop-logs`. |

## VNC shows no desktop

Check the desktop logs:

```bash
./foxden.sh ~/projects/my-repo --desktop-logs
```

Check that Sway and wayvnc are running.

After an image rebuild the container is recreated. The VNC
viewer then has to reconnect.

## Image doesn't paste

The proxy log (`--desktop-logs`) shows every Ctrl+V:

| Entry | Meaning |
|---|---|
| `pushed … KB PNG` | The image is in the container. If the program doesn't paste it, it doesn't accept images. |
| `no image-only clipboard` | The clipboard holds no image, or text as well. |
| `powershell.exe unavailable` | On WSL2: WSL interop is turned off. On native Linux: expected, image paste isn't available there yet. |
| `security type …`, `unknown message type …` | The viewer uses encryption or an unknown extension. Images aren't pasted then. |
| no entry | The viewer isn't connected through the proxy (wrong port). |

## Bar or start menu missing

Check in the container whether Waybar is running:

```bash
pgrep -a waybar
```

Errors in `desktop/waybar.jsonc` or `desktop/waybar.css`
show up in the desktop logs.

If the start menu stops responding after a terminal,
Chromium or the file manager was started from the menu:
that's the known issue from
[Graphical desktop](06-desktop.md). Close the program, or
start programs with Alt+Enter or Alt+D.

## IDE shows a white window

Electron IDEs such as the Cursor IDE stay white for a few
seconds at startup until the interface has loaded. If the
window stays white, or black with "launch-failed": was the
IDE started with `--ozone-platform=x11`? With the GPU only
Wayland works, which is the default
([Layers](08-layers.md)).

## Harness command not found

The base image has no coding agent. Check that the layer
that installs it is listed in `~/.config/foxden/layers`
and installs into a system path such as `/usr/local`, not
into `/home/node` ([Layers](08-layers.md)).

## WebGL doesn't work

"Could not create a WebGL context" is expected without a
GPU. With the GPU, check:

```bash
eglinfo -B -p wayland | grep -i renderer
```

If that shows `llvmpipe` instead of `D3D12 (…)`, the GPU
isn't turned on or Mesa falls back to software
([GPU](09-gpu.md)).

## Chromium doesn't start

Check that the Wayland session is running and
`WAYLAND_DISPLAY` is set.

On `No usable sandbox!`, check that the default flags are
there:

```bash
cat /etc/chromium.d/foxden
```

## Logs missing under `/logs`

```bash
docker compose ls
./foxden-logs.sh status
```

The project name in `log-projects.txt` must match the name
from `docker compose ls`.

## Wrong file permissions

The Compose configuration uses the UID and GID of your
host user.

Check:

```bash
id
ls -ld ~/projects/my-repo
```

## Git operations fail

Writes to `.git` are supposed to fail.

Read operations should still work.

Repositories created during a session are only protected
after the container restarts.
