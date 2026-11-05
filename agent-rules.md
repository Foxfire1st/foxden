# foxden sandbox

You are working in a Docker container. The project is at `/workspace`.

## Git

- `.git` is read-only on purpose. The user commits, pushes, switches
  branches and stashes on the host.
- Don't try to get around this: no `mount`, no `sudo`, no copy of the
  repository to commit in, no hunting for Git credentials.
- Leave your changes uncommitted. At the end, summarize which files you
  changed and suggest a commit message.
- Read-only commands (`git status`, `git diff`, `git log`) are allowed.

## Sandbox limits

- If something fails because of the sandbox (read-only, missing
  permissions), don't try to get around it. Tell the user.

## Secrets

- Empty `.env` files are masked on purpose. Ask for values instead of
  searching for them.

## Logs

- Logs of local Docker stacks are read-only at
  `/logs/<project>.log`. Read them with `tail -n …` or `grep`.
- `tail -f` never ends. If needed: `timeout 30 tail -n 0 -F …`.
- You can't restart containers or run commands in them. Ask the user
  to do it.

## Browser

- Sign in to web applications only with local test accounts the user
  gives you, never through single sign-on (e.g. Microsoft Entra ID).
