[← Overview](../README.md)

# Browser and screenshots

Chromium is installed in the Docker image and available
from the start menu. From a terminal in the container:

```bash
chromium https://example.com >/tmp/chromium.log 2>&1 &
```

The browser appears on the Sway desktop and is visible
over VNC.

## Chromium without its own sandbox

Chromium starts in the container with the flags
`--ozone-platform=wayland --no-sandbox`. They are in
`/etc/chromium.d/foxden` and apply automatically.

Chromium's own sandbox needs user namespaces or a SUID
helper. Both are blocked by `cap_drop: ALL` and
`no-new-privileges`. Without `--no-sandbox`, Chromium
aborts with `No usable sandbox!`.

The container is the boundary: an attack through a website
gets as far as the agent itself. Loosening the container
for this would weaken the more important boundary between
container and host.

That's why Chromium shows a notice about `--no-sandbox` at
the top. It is expected and can be closed.

Chinese and Japanese characters appear as boxes, because
the fonts for them aren't installed.

## WebGL only with a GPU

Without a GPU, Chromium refuses WebGL. Pages with 3D
graphics then report "Could not create a WebGL context".
With the GPU turned on, WebGL 2 works with hardware
acceleration ([GPU](09-gpu.md)).

## Sign-in links

Programs in the container open links through `xdg-open`
in the container's Chromium, including sign-ins of IDEs.
Don't sign in there: copy the link and open it in
your normal browser ([Security model](02-security-model.md),
rule 4).

## Screenshots

`grim` is installed for screenshots of the whole desktop.

Example inside the container:

```bash
grim /workspace/screenshot.png
```

The screenshot file then also appears in the shared
project directory on the host.

## Playwright MCP

Playwright MCP is installed in the Docker image.

To use it, add it to your harness's MCP configuration (see
[Roadmap](16-roadmap.md)).

Planned uses include:

- Opening websites.
- Using buttons and navigation.
- Filling in forms.
- Scrolling.
- Taking screenshots.
- Retesting applications after code changes.

For visibly controlled browsers, Playwright has to use the
same graphical session as Sway.
