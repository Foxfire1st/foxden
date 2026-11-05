[← Overview](../README.md)

# First start

Start the desktop and container:

```bash
./foxden.sh ~/projects/my-repo --desktop
```

The first start builds the Docker image.

The launcher:

1. Checks the shared directory.
2. Finds all Git repositories in it.
3. Generates the mount list: every `.git` read-only,
   untracked `.env` files masked, optionally the GPU and
   the ports of your layers.
4. Reports uncommitted changes.
5. Builds the base image and your layers
   ([Layers](08-layers.md)).
6. Creates or starts the container.
7. Starts the Sway desktop at the configured resolution.
8. Starts wayvnc and serves the desktop on the local VNC
   port.
9. Runs the start hooks of your layers.

The first build takes a few minutes. The base image is
about 1.7 GB.

## Several repositories together

Instead of a single repository, you can share a folder with
several repositories, for example all repositories of a
product:

```bash
./foxden.sh ~/projects/my-product
```

`/workspace` is then that folder. The agent sees all
repositories and can work in all of them.

The launcher:

- Finds all `.git` directories at any depth and mounts each
  read-only. `node_modules`, `vendor` and `.venv` are
  skipped.
- Protects submodules through the `.git` of the parent
  repository.
- Masks untracked `.env` files in all repositories and
  outside them too.
- Reports uncommitted changes per repository:

```text
WARNING: Uncommitted changes remain in /home/user/projects/my-product:
  app:
     M main.txt
  lib/core:
    ?? new.txt
```

The launcher aborts with an error if:

- the directory is inside a repository (then pass the
  repository itself or the parent folder),
- the directory contains no repository at all,
- a `.git` is a symlink,
- the directory is a linked Git worktree.

Tip: an `AGENTS.md` directly in the parent folder can
describe how the repositories fit together. It isn't in
any repository and doesn't get committed.

## Open a container shell

```bash
./foxden.sh ~/projects/my-repo
```

Without a command, the launcher opens a shell in the
container.

## Start a harness

The base image has no coding agent. Add your harness as a
layer ([Layers](08-layers.md)), then start it by name, for
example:

```bash
./foxden.sh ~/projects/my-repo agent    # Cursor CLI
./foxden.sh ~/projects/my-repo claude   # Claude Code
```

The harness runs inside the agent container.

## Sign in

Run the harness's login in the container shell and open
the link it shows in the Windows browser. Details per
harness: [Layers](08-layers.md), "Signing in".

The agent home is a separate volume per shared directory.
A sign-in therefore only applies to the container of that
directory.

Alternatively, pass API keys from the host: list the
variable names in `~/.config/foxden/env`. The rest of the
host environment is not passed on to the agent.
