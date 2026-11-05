#!/usr/bin/env bash
# Follow Docker Compose project logs into files the agent sandbox can read
set -euo pipefail

usage() {
  cat <<'HELP'
Usage:
  ./foxden-logs.sh follow             Follow all listed projects in the background
  ./foxden-logs.sh unfollow           Stop all background followers
  ./foxden-logs.sh status             Show which listed projects are followed
  ./foxden-logs.sh <compose-project>  Follow one project in the foreground

Project list, one Compose project name per line (# starts a comment):
  ~/.config/foxden/log-projects.txt

Running projects:
  docker compose ls

Host files:  ~/.local/state/foxden/logs/<compose-project>.log
Sandbox:     /logs/<compose-project>.log
HELP
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

if [[ $1 == "-h" || $1 == "--help" ]]; then
  usage
  exit 0
fi

umask 077

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/foxden"
LOG_DIR="$STATE_DIR/logs"
PID_DIR="$STATE_DIR/followers"
LIST_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/foxden/log-projects.txt"
SCRIPT_PATH=$(realpath -e -- "${BASH_SOURCE[0]}")

mkdir -p -- "$LOG_DIR" "$PID_DIR"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
# Valid Compose project name; also keeps it safe as a file name.
valid_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}

# Prints the PID of a running follower for the project.
# Removes stale PID files, e.g. after a reboot.
follower_pid() {
  local pid_file="$PID_DIR/$1.pid" pid args

  [[ -f "$pid_file" ]] || return 1
  pid=$(<"$pid_file")

  # Check the command line too: PIDs are reused after a reboot.
  if [[ "$pid" =~ ^[0-9]+$ ]] &&
     args=$(ps -o args= -p "$pid") &&
     [[ "$args" == *"foxden-logs.sh $1" ]]; then
    printf '%s\n' "$pid"
    return 0
  fi

  rm -f -- "$pid_file"
  return 1
}

# Reads the project list into PROJECTS.
read_list() {
  local line

  if [[ ! -f "$LIST_FILE" ]]; then
    echo "ERROR: Project list not found: $LIST_FILE" >&2
    echo "Add one Compose project name per line (see docker compose ls)." >&2
    exit 2
  fi

  PROJECTS=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%%#*}
    line=${line//[[:space:]]/}
    [[ -z "$line" ]] && continue

    if ! valid_name "$line"; then
      echo "ERROR: Invalid Compose project name in $LIST_FILE: $line" >&2
      exit 2
    fi

    PROJECTS+=("$line")
  done <"$LIST_FILE"

  if (( ${#PROJECTS[@]} == 0 )); then
    echo "ERROR: No projects listed in $LIST_FILE" >&2
    exit 2
  fi
}

# ------------------------------------------------------------
# follow / unfollow / status
# ------------------------------------------------------------
case "$1" in
  follow)
    read_list

    for project in "${PROJECTS[@]}"; do
      if pid=$(follower_pid "$project"); then
        echo "Already following $project (PID $pid)"
        continue
      fi

      # Own session: keeps running after the terminal closes,
      # and unfollow can stop the whole process group.
      setsid -f bash "$SCRIPT_PATH" "$project" </dev/null >/dev/null 2>&1

      started=false

      for _ in {1..10}; do
        if follower_pid "$project" >/dev/null; then
          started=true
          break
        fi
        sleep 0.2
      done

      if [[ $started == true ]]; then
        echo "Following $project -> /logs/$project.log"
      else
        echo "ERROR: Could not start follower for $project" >&2
      fi
    done
    exit 0
    ;;

  unfollow)
    stopped=0

    for pid_file in "$PID_DIR"/*.pid; do
      [[ -e "$pid_file" ]] || continue
      project=$(basename -- "$pid_file" .pid)

      if pid=$(follower_pid "$project"); then
        # Negative PID: the follower and its docker compose child.
        if kill -TERM -- "-$pid" 2>/dev/null; then
          echo "Stopped $project"
          stopped=$(( stopped + 1 ))
        else
          echo "ERROR: Could not stop $project (PID $pid)" >&2
        fi
      fi
    done

    (( stopped > 0 )) || echo "No followers running"
    exit 0
    ;;

  status)
    read_list

    for project in "${PROJECTS[@]}"; do
      if pid=$(follower_pid "$project"); then
        echo "$project: following (PID $pid)"
      else
        echo "$project: stopped"
      fi
    done
    exit 0
    ;;
esac

# ------------------------------------------------------------
# Follow one project (foreground, or started by follow)
# ------------------------------------------------------------
PROJECT=$1

if ! valid_name "$PROJECT"; then
  echo "ERROR: Invalid Compose project name: $PROJECT" >&2
  exit 2
fi

if pid=$(follower_pid "$PROJECT"); then
  echo "ERROR: $PROJECT is already followed (PID $pid)." >&2
  exit 2
fi

LOG_FILE="$LOG_DIR/$PROJECT.log"
PID_FILE="$PID_DIR/$PROJECT.pid"

echo "$$" >"$PID_FILE"
trap 'rm -f -- "$PID_FILE"' EXIT
trap 'exit 0' INT TERM

# Start with a fresh file on every run.
: > "$LOG_FILE"

# Find containers by project name only. The project's compose
# files are agent-editable and must not be read here.
unset COMPOSE_FILE
cd /

printf 'Following %s -> %s\n' "$PROJECT" "$LOG_FILE"
printf 'Sandbox path: /logs/%s.log (Ctrl-C to stop)\n' "$PROJECT"

since=''

while true; do
  args=(--follow --timestamps --no-color)

  if [[ -n "$since" ]]; then
    args+=(--since "$since")
  else
    args+=(--tail 200)
  fi

  docker compose -p "$PROJECT" logs "${args[@]}" >>"$LOG_FILE" 2>&1 || true

  # Stack stopped or not started yet: resume without duplicating lines.
  since=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
  sleep 2
done
