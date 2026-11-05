[← Overview](../README.md)

# Prerequisites

- Windows with WSL2 or a native Linux host.
- Docker Engine, without Docker Desktop.
- Docker Compose plugin.
- Git.
- Access to Docker as a normal WSL user.
- A Git repository or a folder with several Git
  repositories, each with a real `.git` directory.
- A VNC viewer for the graphical desktop, e.g. TigerVNC.
- `python3` in WSL for the VNC proxy (included in
  Ubuntu).
- WSL interop, so `powershell.exe` starts from WSL
  (the default). Needed for pasting images.
- Optional for the GPU: a Windows graphics driver with WSL
  support (WSL then has `/dev/dxg`).

Linked Git worktrees with a `.git` file instead of a `.git`
directory are not supported. Submodules are supported.

Projects should preferably live in the Linux filesystem of
WSL, for example under `~/projects`.
