[← Overview](../README.md)

# Filesystem and persistence

## Project files

The shared directory is mounted writable at `/workspace`.

Changes in the container show up immediately on the host.

## Git metadata

At startup the launcher finds all `.git` directories in the
shared directory and mounts each with its own read-only
bind mount.

That protects the Git metadata of all repositories from
direct writes from the container.

## Masked secret files

On every run, the launcher searches the shared directory
for files matching the name patterns `.env*` and `*.env`.
It skips the directories `.git`, `node_modules`, `vendor`
and `.venv`.

Every file found that isn't tracked by Git is covered in
the container by a read-only bind mount of `/dev/null`.
The nearest repository decides whether a file is tracked.
Files outside any repository are covered too. Files
tracked by Git stay visible, since they are in the Git
history anyway.

At startup the launcher lists the masked files, for
example:

```text
Hidden from the agent:
  .env
  backend/.env.local
```

In the container:

- Reading returns empty output.
- `ls -l` shows a character device instead of a file.
- Writes are discarded; deleting and renaming fail.

On the host the files stay unchanged. Project containers
on the host still read the real values.

Limitations:

- New `.env` files are only masked the next time the
  launcher runs. If the mount list changes, the container
  is recreated; agent sessions running in it end.
- Only the name patterns above are detected. Other secret
  files (e.g. `.npmrc`, `*.pem`, `*.key`) are not masked.
  The patterns are in the `find` call in `foxden.sh`.
- Paths containing a newline can't be mounted. The
  launcher aborts in that case.
- Code the agent writes that runs in project containers on
  the host can still read their environment variables.

## Agent home

The agent has its own persistent Docker volume:

```text
/home/node
```

It can hold, among other things:

- Sign-ins of harnesses and IDEs.
- Harness settings.
- Settings and extensions of IDEs.
- The browser profile.
- Personal configuration files.
- Tools installed in the home directory.

There is one volume per shared directory.

This directory is not the home directory of the host
user.

## Container logs

The agent has no access to the host's Docker Engine and so
doesn't see any other containers, such as those of your
application stacks.

For debugging, `foxden-logs.sh` on the host writes the
logs of Docker Compose projects into files that are
mounted read-only at `/logs` in the container.

The projects are in a list, one Compose project name per
line; `#` starts a comment:

```bash
mkdir -p ~/.config/foxden
printf 'my-app\n' > ~/.config/foxden/log-projects.txt
```

`docker compose ls` shows running Compose projects and
their names.

The list is outside all projects so that the agent can't
add more stacks.

Commands:

```bash
./foxden-logs.sh follow     # all listed projects in the background
./foxden-logs.sh status     # which projects are followed
./foxden-logs.sh unfollow   # stop all background processes
./foxden-logs.sh my-app     # one project in the foreground
```

| Where | Path |
|---|---|
| Host | `~/.local/state/foxden/logs/<project>.log` |
| Container | `/logs/<project>.log` |

`follow` returns right away. The background processes keep
running after the terminal is closed and end when the host
restarts (on WSL2 also when WSL shuts down). Run `follow` again after that.

- `follow` skips projects that are already followed.
- The foreground mode aborts if the project is already
  followed. Stop it with Ctrl+C.
- `unfollow` stops all running processes, including those
  for projects no longer in the list.

Every line starts with the service name, e.g. `web-1 |`.

Each process starts with the last 200 lines per container,
then follows new output, and keeps running if the stack is
stopped or only started later. The file is emptied when the
process starts.

Read logs in the container:

```bash
tail -n 100 /logs/my-app.log
tail -F /logs/my-app.log
tail -F /logs/my-app.log | grep --line-buffered 'web-1'
```

`tail -F` follows the file continuously and survives the
file being emptied when a process restarts. Stop it with
Ctrl+C.

The agent shouldn't use `tail -F` without a time limit,
since the command never ends:

```bash
timeout 30 tail -n 0 -F /logs/my-app.log
```

Containers are found only by project name. The projects'
Compose files are not read, since the agent can change
them.

Limitations:

- The files grow without a size limit while the processes
  run.
- All agent containers see all exported logs.
- The agent reads everything the applications log,
  including secrets logged by accident.
- The agent can neither restart containers nor run
  commands in them.

The Docker socket is deliberately not mounted: access to
`/var/run/docker.sock` equals root on the host.

## Files on the host

Besides the projects, the launcher and log script create
these files:

| Path | Content |
|---|---|
| `~/.local/state/foxden/mounts-<hash>.yaml` | generated mount list per shared directory |
| `~/.local/state/foxden/logs/` | exported container logs |
| `~/.local/state/foxden/followers/` | PID files of the log processes |
| `~/.config/foxden/log-projects.txt` | list of Compose projects to follow |
| `~/.config/foxden/gpu` | turns on the GPU, content selects the GPU ([GPU](09-gpu.md)) |
| `~/.config/foxden/layers` | your layer directories, built in order ([Layers](08-layers.md)) |
| `~/.config/foxden/env` | names of host variables passed into the container |
| `~/.local/state/foxden/vnc-proxy-<hash>.log` | log of the VNC proxy |

## Share more host files

You can mount specific extra files through `compose.yaml`:

```yaml
- type: bind
  source: /home/user/specs/requirements.md
  target: /inputs/requirements.md
  read_only: true
  bind:
    create_host_path: false
```

Only share files and directories that are actually needed.

Don't mount:

- The whole host home.
- The host root filesystem.
- Windows user directories (`/mnt/c/…` on WSL2).
- Host SSH agent sockets.
- `/var/run/docker.sock`.
