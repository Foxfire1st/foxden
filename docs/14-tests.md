[← Overview](../README.md)

# Tests

What the agent can and can't do in the sandbox is recorded
in `test-reports/`:

- `00-template.md`: all checks with command and expected
  result, to fill in.
- `YYYY-MM-DD-test-report.md`: completed test runs with
  actual results.

Areas covered:

- **Working in the project:** change files, read Git,
  internet, read logs, several repositories in a parent
  folder.
- **Git:** commit (also in nested repositories and
  submodules), add a remote, push, credentials.
- **Permissions:** remount `.git`, `sudo`, capabilities.
- **Files:** masked `.env` files, `/logs`, `/AGENTS.md`.
- **Host:** Windows files (WSL2), Docker socket, sandbox
  configuration in the workspace.
- **Agent:** how a harness behaves when asked to commit,
  with and without `/AGENTS.md`.

Test setup with temporary repositories, not with real
projects:

```bash
S=/path/to/foxden/foxden.sh
T=/tmp/foxden-test
M=/tmp/foxden-multi

# Single repository with an ignored .env
mkdir -p "$T" && git -C "$T" init -q
printf '.env\n' > "$T/.gitignore"
git -C "$T" add .gitignore
git -C "$T" -c user.name=Test -c user.email=test@example.invalid commit -qm baseline
echo 'TEST_SECRET=secret' > "$T/.env"
$S "$T"

# Folder with several repositories; a second sandbox
# needs its own VNC port while the first one runs
for r in app lib; do
  git init -q "$M/$r"
  git -C "$M/$r" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m baseline
done
VNC_PORT=5901 $S "$M"

# Clean up
$S "$T" --down; VNC_PORT=5901 $S "$M" --down; rm -rf "$T" "$M"
```

The checks cover individual protections and are not a
complete security audit.
