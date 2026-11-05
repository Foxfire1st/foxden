[← Overview](../README.md)

# Security model

## Allowed

- Read, create, change and delete project files in all
  repositories of the shared directory.
- Run development tools, compilers and tests.
- Use Python, Node.js and other project dependencies.
- Open websites and research on the internet.
- Start the browser and graphical applications.
- Take screenshots.
- Use `git status`, `git diff` and `git log`.
- Read exported container logs under `/logs`.

## Restricted

- The Git metadata of every repository in the shared
  directory is mounted read-only.
- Untracked `.env` files are replaced in the container by
  empty, read-only files.
- Host directories outside the shared mounts are not
  mounted.
- Host SSH keys and Git credentials are not passed in.
- The host's Docker socket is not mounted.
- The container runs as an unprivileged Linux user.
- Linux capabilities are dropped.
- `no-new-privileges` is on.
- The GPU is only passed in when it is explicitly turned
  on ([GPU](09-gpu.md)).

## Limits of the isolation

**Git commits**

Every `.git` directory that exists in the shared directory
at startup is mounted read-only, including nested
repositories. Submodules are protected through the `.git`
of their parent repository.

Repositories created during a session are only protected
after the next container start.

Without capabilities the agent can't lift the read-only
protection. In a test, an agent tried to remount `.git`
writable with `sudo` and `mount` after a failed commit.
Both failed.

**Git push**

With unrestricted internet access, Docker alone can't
enforce an absolute ban on Git pushes.

Without remote credentials available, pushes to protected
repositories should fail. The agent can still attempt
pushes or use other credentials it can reach.

**Host files**

Untracked `.env` files are masked in the container (see
[Filesystem and persistence](11-filesystem-and-persistence.md)).
The agent can still read other secrets inside the shared
directory, such as `.npmrc` tokens or private keys.

Credentials, tokens and private keys therefore shouldn't
be in shared directories.

The masking only applies in the agent container. If
project containers on the host run code from the shared
directory, code written by the agent can access their
environment variables and mounts there.

**Container security**

Docker containers share the host's Linux kernel. The
isolation doesn't protect against every possible container
escape or kernel vulnerability.

**GPU (optional)**

With the GPU turned on, the container gets the device
`/dev/dxg` and the WSL libraries under `/usr/lib/wsl`
(read-only). The agent can then reach the GPU interface to
the Windows graphics driver. That's extra attack surface
towards the host, so the GPU is off by default.

## Rules for developers

The technical protections only work if the following rules
are followed.

**1. No Git credentials in the container**

Don't sign in to GitHub, GitLab or other Git remotes in the
container: neither in the terminal (e.g. `gh auth login`)
nor in an IDE inside the container.

The agent home `/home/node` is a shared volume. The agent
can read everything stored there.

An IDE in the container is only for reviewing changes.
Commits and pushes happen on the host.

Signing in to harnesses and IDEs in the container:

- Signing in to the account of your harness or IDE is fine.
  The session is stored in the agent home and readable by
  the agent.
- Open sign-in links in the Windows browser, not in the
  container's Chromium (see rule 4 and
  [Layers](08-layers.md)).
- When asked about the keyring ("OS keyring"), choose the
  weaker encryption. A keyring in the container would run
  as the same user as the agent and wouldn't protect the
  data from it.
- Don't sign in to GitHub or GitLab in the IDE and don't
  store tokens in extensions.

**2. Don't attach the host IDE to the agent container**

Don't connect the host IDE (Cursor or VS Code on Windows)
to the agent container through Dev Containers or "Attach
to Running Container".

By default the extension forwards the host's SSH agent and
a Git credential helper into the container. The agent would
then have the host credentials.

**3. Review agent changes before the host runs them**

The read-only `.git` mount protects `.git/hooks` and
`.git/config`. It doesn't protect against files in the
working tree that host tools run with the developer's
permissions and credentials:

- Hook managers in the working tree: husky (`.husky/`),
  `lefthook.yml`, `.pre-commit-config.yaml`. They run on
  the next `git commit` on the host.
- Newly created, nested `.git` directories. Their
  configuration (e.g. `core.fsmonitor`) can run commands on
  every `git status`, also through the shell prompt or the
  IDE's Git integration.
- Docker configuration: `compose.yaml`, `Dockerfile`.
  `docker compose up` on the host can mount any host path
  or the Docker socket.
- Project configuration the IDE runs automatically, e.g.
  `eslint.config.js`, `prettier.config.js`,
  `.vscode/tasks.json`.
- Anything the developer starts: `npm install`, tests,
  `make`.

Before `git commit`, `docker compose up` or opening the
project in the host IDE, review the changes in the diff,
especially in the files above.

**4. Agent browser access only with test accounts**

The browser in the container belongs to the agent. It can
read and use input, cookies and signed-in sessions. If the
browser profile is in the agent home, sessions survive
restarts.

Treat a signed-in browser session like a key:

- Never sign in to the agent browser with your own work
  account or through single sign-on (e.g. Microsoft Entra
  ID), not even briefly. An SSO session applies to all
  connected applications, possibly including your Git
  host. There the agent could commit through the web IDE
  or create tokens.
- To debug web interfaces, use a separate local test user
  without SSO.
- Give the test user only the permissions it needs. The
  backend carries out actions in the interface with the
  application's own credentials, e.g. cloud credentials.
- The agent may know the test user's password. It isn't
  used anywhere else and is kept outside the repositories.
- If an application is only reachable through SSO: use a
  test account without access to the Git host and cloud
  resources, or do without browser access for the agent.
- Sign-in links from programs in the container, such as
  an IDE, open in the container's Chromium. Don't
  sign in there; copy the link and open it in the Windows
  browser.
- Bind debug ports of project containers only to
  `127.0.0.1`. Ports published on `0.0.0.0` are reachable
  from the agent container. A Node.js debugger allows code
  execution in the container, including access to its
  environment variables.

**5. End sessions with** `--stop`

The launcher reports uncommitted changes in all
repositories of the shared directory:

- when the agent container starts,
- at the end of every session, even if it's aborted,
- on `--stop` and `--down`.

It doesn't block anything; the report is a reminder.

A typical day looks like this:

1. Start the computer.
2. Start the local application (e.g. `docker compose up`).
3. Start the agent container.

So the report at agent container start only comes after
the application has started. If changes from the agent's
last session are still in the project, the application has
already loaded them by then.

Review reported changes at the end of the session and
commit, stash or discard them, at the latest before the
next start of the application. Then end the container with
`--stop` or `--down`. When attaching to a running
container, there is no start report.

If the terminal is closed or the computer shuts down, no
report appears. In that case check `git status` before
starting the application.

**6. Use the clipboard over VNC deliberately**

VNC viewers sync the clipboard between Windows and the
container while they're connected:

- Windows → container: everything copied on Windows lands
  in the container right away, including passwords or
  tokens. The agent could read it there.
- Container → Windows: whatever is copied in the container
  lands in the Windows clipboard. Check content before
  pasting it, for example into a terminal.

Recommended TigerVNC settings (Options, "Input"):

- "Send clipboard to server" off. Only turn it on briefly
  when you want to paste something into the container.
- "Accept clipboard from server" on. That way you can still
  copy links from the container to Windows.

Alternatively, disconnect the VNC viewer before copying
something sensitive on Windows. The agent doesn't need the
VNC connection.

VNC doesn't carry images. For that, `vnc-paste-proxy.py`
sits on the host between the VNC viewer and wayvnc
([Graphical desktop](06-desktop.md)):

- An image only reaches the container when Ctrl+V is
  pressed in the VNC window and the Windows clipboard holds
  an image and no text. Copying alone transfers nothing.
- The agent can't trigger this. Key presses it generates in
  the container don't go through the proxy.
- Afterwards the image stays in the container's clipboard
  until something else is copied there. The agent can read
  it.
- "Send clipboard to server" in TigerVNC only applies to
  text.

**7. Keep layers outside shared folders**

Your layers define the agent's image
([Layers](08-layers.md)). If the agent could change a
layer, it could change its own environment and the services
it publishes to the host. The launcher refuses layers inside
the shared folder it starts, or containing it. It can't see
folders shared by other foxden containers.

Layers can only publish ports, always on `127.0.0.1`. They
can't add mounts, devices or other Compose settings. Pages
served from the container are under the agent's control:
open them in a separate browser profile, and don't treat
approvals in them as a security boundary.

## Rules for the agent

The image contains the file `/AGENTS.md` with rules for the
agent. Its source is `agent-rules.md` in this project.

Harnesses that read `AGENTS.md` in all parent directories,
such as the Cursor CLI, find `/AGENTS.md` for every shared
project, in addition to any `AGENTS.md` of the project
itself (found in the code of the Cursor CLI, version
2026.10.22). Harnesses that look elsewhere get the rules
through your layer ([Layers](08-layers.md), "Agent rules").

The file is owned by root and the agent can't change it.
It is deliberately not in `/workspace`: there it would hide
a project file or show up as a new file in the repository.

Summary of the content:

- `.git` is read-only on purpose. Don't get around it,
  leave changes uncommitted, summarize at the end and
  suggest a commit message.
- If something fails because of the sandbox, report it
  instead of getting around it.
- Empty `.env` files are masked; ask for values.
- Read logs under `/logs`; `tail -f` only with `timeout`.
- In the browser only local test accounts, never SSO.

The rules are an addition. The protection itself relies on
the technical barriers.

After a harness update, check that the rules are still
loaded (see the [test report template](../test-reports/00-template.md),
no. 23).

## Why VNC and not WSLg

WSLg can show Linux programs as their own windows on
Windows, also with a GPU. It was rejected for the agent
sandbox because WSLg brings several services of the
Windows desktop into the container at once:

| | VNC (this setup) | WSLg |
|---|---|---|
| Clipboard | text can be turned off in the viewer, images only on Ctrl+V; only while connected | built in |
| Audio incl. microphone | no | yes |
| Agent windows | stay in the VNC window, recognizable as the sandbox | appear as normal Windows windows |
| X11 server | its own in the container | shared with the host's Linux programs |
| Display server | Sway in the container | host infrastructure |
| Disconnect | close the viewer, the agent keeps working | not intended |

VNC is a narrow channel of picture, input and optionally
the clipboard that can be closed at any time.
