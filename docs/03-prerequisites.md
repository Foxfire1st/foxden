[← Overview](../README.md)

# Prerequisites

- Linux with Docker Engine, without Docker Desktop: native
  (e.g. Ubuntu) or WSL2 on Windows.
- Docker Compose plugin.
- Git.
- Access to Docker as your normal user.
- A Git repository or a folder with several Git
  repositories, each with a real `.git` directory.
- A VNC viewer for the graphical desktop, e.g. TigerVNC.
- `python3` on the host for the VNC proxy (included in
  Ubuntu).
- GNU coreutils, `ss` and `setsid` on the host (included in
  Ubuntu).

Only on WSL2:

- WSL interop, so `powershell.exe` starts from WSL (the
  default). Needed for pasting images from the Windows
  clipboard.
- Optional for the GPU: a Windows graphics driver with WSL
  support (WSL then has `/dev/dxg`).

On native Linux, image paste and the GPU are not available
yet ([Roadmap](16-roadmap.md)). macOS is not supported: the
launcher relies on GNU tools and `/proc`.

Linked Git worktrees with a `.git` file instead of a `.git`
directory are not supported. Submodules are supported.

Projects should live in the Linux filesystem, for example
under `~/projects`. On WSL2, avoid `/mnt/c`.
