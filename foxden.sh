#!/usr/bin/env bash
# foxden: sandbox for coding agents. Headless Sway + wayvnc in
# one Docker container, plus your own image layers.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage:
  ./foxden.sh [--mount SPEC]... /path/to/repo                    shell in the container
  ./foxden.sh [--mount SPEC]... /path/to/folder-with-repos       several repositories
  ./foxden.sh /path/to/repo <command>                            e.g. claude, codex, agent
  ./foxden.sh /path/to/repo --desktop
  ./foxden.sh /path/to/repo --desktop-logs
  ./foxden.sh /path/to/repo --stop
  ./foxden.sh /path/to/repo --down

Extra folders/files mounted at /inputs/<name> (read-only by default):
  --mount HOST[:NAME][:ro|rw]      one-off mount (repeatable, before project path)
  ~/.config/foxden/mounts          default mounts, one spec per line

Desktop defaults:
  Resolution: 1920x1080
  VNC:        localhost:5900

Override:
  DESKTOP_WIDTH=2560 DESKTOP_HEIGHT=1440 VNC_PORT=5901 \
    ./foxden.sh /path/to/repo

Your layers (harnesses, IDEs, services), one directory per line:
  ~/.config/foxden/layers

Host variables passed into the container, one name per line:
  ~/.config/foxden/env

Build without cache (fresh downloads):
  FOXDEN_REBUILD=1 ./foxden.sh /path/to/repo --desktop

GPU for programs in the container (WSL2 only):
  echo NVIDIA > ~/.config/foxden/gpu   # on, NVIDIA GPU
  : > ~/.config/foxden/gpu             # on, default GPU
  rm ~/.config/foxden/gpu              # off
HELP
}

# ------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------
CLI_MOUNTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --mount)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "ERROR: --mount requires an argument (HOST[:NAME][:ro|rw])." >&2
        exit 2
      fi
      CLI_MOUNTS+=("$2")
      shift 2
      ;;
    --mount=*)
      value=${1#--mount=}
      if [[ -z "$value" ]]; then
        echo "ERROR: --mount requires an argument (HOST[:NAME][:ro|rw])." >&2
        exit 2
      fi
      CLI_MOUNTS+=("$value")
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi

if (( $(id -u) == 0 )); then
  echo "ERROR: Run as your normal user, not root." >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1 ||
   ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Engine and Compose are required." >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required for the VNC proxy." >&2
  exit 2
fi

if ! PROJECT_DIR=$(realpath -e -- "$1") ||
   [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: Project directory not found: $1" >&2
  exit 2
fi
shift

# A subfolder of a repository would hide its .git from the mounts.
toplevel=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || true)

if [[ -n "$toplevel" && "$toplevel" != "$PROJECT_DIR" ]]; then
  echo "ERROR: $PROJECT_DIR is inside the repository $toplevel." >&2
  echo "Pass the repository root or a folder that contains repositories." >&2
  exit 2
fi

SCRIPT_DIR=$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd -P
)

# Security configuration must live outside the writable project.
if [[ "$SCRIPT_DIR" == "$PROJECT_DIR" ||
      "$SCRIPT_DIR" == "$PROJECT_DIR/"* ]]; then
  echo "ERROR: Keep sandbox configuration outside the workspace." >&2
  exit 2
fi

# ------------------------------------------------------------
# Git repositories
# ------------------------------------------------------------
# PROJECT_DIR is one repository or a folder with several. Every
# .git directory found is mounted read-only.
REPOS=()

while IFS= read -r -d '' rel; do
  repo=$(dirname -- "$rel")

  if [[ $rel == *$'\n'* ]]; then
    echo "ERROR: Path with newline cannot be mounted: $rel" >&2
    exit 2
  fi

  if [[ -L "$PROJECT_DIR/$rel" ]]; then
    echo "ERROR: .git must not be a symlink: $PROJECT_DIR/$rel" >&2
    exit 2
  fi

  # A .git file: submodules keep their Git data in the parent's
  # .git, which is mounted read-only. Linked worktrees are not
  # supported.
  if [[ -f "$PROJECT_DIR/$rel" ]]; then
    if [[ $repo == "." ]]; then
      echo "ERROR: Linked worktrees are not supported: $PROJECT_DIR" >&2
      exit 2
    fi
    continue
  fi

  REPOS+=("$repo")
done < <(
  find "$PROJECT_DIR" \
    \( -name node_modules -o -name vendor -o -name .venv \) -prune \
    -o -name .git -printf '%P\0' -prune |
    sort -z
)

if (( ${#REPOS[@]} == 0 )); then
  echo "ERROR: No Git repositories found in $PROJECT_DIR" >&2
  exit 2
fi

# Host and container path of a repository ("." is PROJECT_DIR).
repo_path() {
  if [[ $2 == "." ]]; then
    printf '%s' "$1"
  else
    printf '%s/%s' "$1" "$2"
  fi
}

# ------------------------------------------------------------
# Desktop configuration
# ------------------------------------------------------------
DESKTOP_WIDTH=${DESKTOP_WIDTH:-1920}
DESKTOP_HEIGHT=${DESKTOP_HEIGHT:-1080}
VNC_PORT=${VNC_PORT:-5900}

for setting in DESKTOP_WIDTH DESKTOP_HEIGHT VNC_PORT; do
  value=${!setting}
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "ERROR: $setting must be a positive integer." >&2
    exit 2
  fi
done

if (( DESKTOP_WIDTH < 640 || DESKTOP_WIDTH > 7680 ||
      DESKTOP_HEIGHT < 480 || DESKTOP_HEIGHT > 4320 )); then
  echo "ERROR: Unsupported desktop resolution." >&2
  exit 2
fi

if (( VNC_PORT < 1 || VNC_PORT > 65535 )); then
  echo "ERROR: Invalid VNC port." >&2
  exit 2
fi

# ------------------------------------------------------------
# Optional GPU for programs in the container
# ------------------------------------------------------------
# WSL exposes the GPU as /dev/dxg; Mesa's d3d12 driver uses it.
# Sway itself keeps software rendering (WSL has no DRM device).
# Enabled while this file exists; its content is the adapter
# name (e.g. NVIDIA), empty for the default GPU.
GPU_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/foxden/gpu"
GPU=0
GPU_ADAPTER=''

if [[ -f "$GPU_FILE" ]]; then
  GPU=1
  GPU_ADAPTER=$(tr -d '[:space:]' <"$GPU_FILE")

  if [[ ! -c /dev/dxg || ! -d /usr/lib/wsl/lib ]]; then
    echo "ERROR: $GPU_FILE exists, but WSL GPU support is missing." >&2
    exit 2
  fi

  if [[ ! $GPU_ADAPTER =~ ^[A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: Invalid GPU adapter name in $GPU_FILE" >&2
    exit 2
  fi
fi

# ------------------------------------------------------------
# Layers and passed environment
# ------------------------------------------------------------
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/foxden"
LAYERS_FILE="$CONFIG_DIR/layers"
ENV_FILE="$CONFIG_DIR/env"
MOUNTS_FILE="$CONFIG_DIR/mounts"

# Prints the non-empty lines of a list file without comments
# and surrounding blanks.
list_lines() {
  local line
  [[ -f $1 ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -n $line ]] && printf '%s\n' "$line"
  done <"$1"
}

# Each layer is a directory with a Dockerfile that starts with
# "ARG BASE=foxden-base:local" and "FROM ${BASE}". Layers build
# in list order on top of the base image. They define the
# agent's image, so the agent must not be able to change them.
LAYERS=()
LAYER_PORTS=()

while IFS= read -r entry; do
  [[ $entry == "~/"* ]] && entry="$HOME/${entry#\~/}"

  if ! dir=$(realpath -e -- "$entry" 2>/dev/null) ||
     [[ ! -f "$dir/Dockerfile" ]]; then
    echo "ERROR: Layer without Dockerfile: $entry (listed in $LAYERS_FILE)" >&2
    exit 2
  fi

  if [[ "$dir" == "$PROJECT_DIR" || "$dir" == "$PROJECT_DIR/"* ||
        "$PROJECT_DIR" == "$dir/"* ]]; then
    echo "ERROR: Keep layers outside the workspace: $dir" >&2
    exit 2
  fi

  LAYERS+=("$dir")

  # Optional ports file: HOST:CONTAINER per line, always
  # published on the loopback address only.
  while IFS= read -r port; do
    if [[ ! $port =~ ^([1-9][0-9]{0,4}):([1-9][0-9]{0,4})$ ]] ||
       (( BASH_REMATCH[1] < 1 || BASH_REMATCH[1] > 65535 ||
          BASH_REMATCH[2] < 1 || BASH_REMATCH[2] > 65535 )); then
      echo "ERROR: Invalid port '$port' in $dir/ports (use HOST:CONTAINER)" >&2
      exit 2
    fi
    LAYER_PORTS+=("$port")
  done < <(list_lines "$dir/ports")
done < <(list_lines "$LAYERS_FILE")

# The last layer is the image the container runs.
if (( ${#LAYERS[@]} )); then
  export FOXDEN_IMAGE="foxden-layer${#LAYERS[@]}:local"
else
  export FOXDEN_IMAGE="foxden-base:local"
fi

# Host variables passed to commands and start hooks, e.g. API
# keys. Names only; values come from the launcher's environment.
PASS_ENV=()

while IFS= read -r name; do
  if [[ ! $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "ERROR: Invalid variable name '$name' in $ENV_FILE" >&2
    exit 2
  fi
  PASS_ENV+=("$name")
done < <(list_lines "$ENV_FILE")

# ------------------------------------------------------------
# Docker Compose configuration
# ------------------------------------------------------------
export PROJECT_DIR
export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/foxden"

# Host-side log exports from foxden-logs.sh, mounted read-only at /logs.
export AGENT_LOG_DIR="$STATE_DIR/logs"
mkdir -p -- "$AGENT_LOG_DIR"

REPO_HASH=$(
  printf '%s' "$PROJECT_DIR" |
    sha256sum |
    cut -c1-12
)

export COMPOSE_PROJECT_NAME="foxden_${REPO_HASH}"

# ------------------------------------------------------------
# Extra mounts (/inputs/<name>)
# ------------------------------------------------------------
paths_overlap() {
  [[ "$1" == "$2" || "$1" == "$2/"* || "$2" == "$1/"* ]]
}

HOME_REAL=$(realpath -m -- "$HOME")
CONFIG_DIR_REAL=$(realpath -m -- "$CONFIG_DIR")
STATE_DIR_REAL=$(realpath -m -- "$STATE_DIR")

EXTRA_MOUNT_SRCS=()
EXTRA_MOUNT_NAMES=()
EXTRA_MOUNT_MODES=()
EXTRA_RO_GIT_SRCS=()
EXTRA_RO_GIT_TARGETS=()
declare -A SEEN_MOUNT_NAMES=()

add_extra_mount() {
  local spec=$1
  local origin=$2
  local -a parts=()
  local host='' name='' mode='ro' host_real=''

  if [[ $spec == *$'\n'* ]]; then
    echo "ERROR: Mount specification with newline is not allowed ($origin)." >&2
    exit 2
  fi

  IFS=':' read -r -a parts <<<"${spec}:"

  case ${#parts[@]} in
    1)
      host=${parts[0]}
      ;;
    2)
      host=${parts[0]}
      if [[ -z "${parts[1]}" ]]; then
        echo "ERROR: Invalid extra mount '$spec' ($origin): empty suffix after ':'." >&2
        exit 2
      elif [[ "${parts[1]}" == "ro" || "${parts[1]}" == "rw" ]]; then
        mode=${parts[1]}
      else
        name=${parts[1]}
      fi
      ;;
    3)
      host=${parts[0]}
      name=${parts[1]}
      mode=${parts[2]}
      if [[ "$mode" != "ro" && "$mode" != "rw" ]]; then
        echo "ERROR: Invalid mount mode '$mode' in '$spec' ($origin): use ro or rw." >&2
        exit 2
      fi
      ;;
    *)
      echo "ERROR: Invalid extra mount '$spec' ($origin): use HOST[:NAME][:ro|rw]." >&2
      exit 2
      ;;
  esac

  if [[ -z "$host" ]]; then
    echo "ERROR: Missing host path in extra mount '$spec' ($origin)." >&2
    exit 2
  fi

  if [[ "$host" == "~" ]]; then
    host="$HOME"
  elif [[ "$host" == "~/"* ]]; then
    host="$HOME/${host#\~/}"
  fi

  if ! host_real=$(realpath -e -- "$host" 2>/dev/null); then
    echo "ERROR: Extra mount path not found: $host ($origin)" >&2
    exit 2
  fi

  if [[ $host_real == *$'\n'* ]]; then
    echo "ERROR: Extra mount path with newline cannot be mounted: $host_real ($origin)" >&2
    exit 2
  fi

  if [[ ! -d "$host_real" && ! -f "$host_real" ]]; then
    echo "ERROR: Extra mount must be a regular file or directory: $host_real ($origin)" >&2
    exit 2
  fi

  # Block system roots, home, sandbox config/state, credential dirs, layers, and workspace overlap.
  case "$host_real" in
    /|"$HOME_REAL"|/mnt|/mnt/c|/mnt/c/Users|/mnt/c/Windows|/mnt/c/Windows/*|\
    /etc|/etc/*|/var|/var/*|/usr|/usr/*|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*|/root|/root/*)
      echo "ERROR: Refusing to mount protected host path: $host_real ($origin)" >&2
      exit 2
      ;;
  esac

  local protected
  for protected in \
    "$PROJECT_DIR" \
    "$SCRIPT_DIR" \
    "$CONFIG_DIR_REAL" \
    "$STATE_DIR_REAL" \
    "$HOME_REAL/.ssh" \
    "$HOME_REAL/.gnupg" \
    "$HOME_REAL/.aws" \
    "$HOME_REAL/.azure" \
    "$HOME_REAL/.kube" \
    "$HOME_REAL/.docker" \
    "${LAYERS[@]}"; do
    if paths_overlap "$host_real" "$protected"; then
      echo "ERROR: Refusing to mount host path overlapping '$protected': $host_real ($origin)" >&2
      exit 2
    fi
  done

  if [[ -z "$name" ]]; then
    name=$(basename -- "$host_real")
  fi

  if [[ -z "$name" || "$name" == "." || "$name" == ".." ||
        "$name" == */* || "$name" =~ [[:cntrl:]] ||
        "$name" =~ ^[[:space:]] || "$name" =~ [[:space:]]$ ]]; then
    echo "ERROR: Invalid mount target name '$name' in '$spec' ($origin)." >&2
    exit 2
  fi

  if [[ -n "${SEEN_MOUNT_NAMES[$name]+set}" ]]; then
    echo "ERROR: Duplicate extra mount name '$name' ($origin). Set a custom name with HOST:NAME." >&2
    exit 2
  fi
  SEEN_MOUNT_NAMES[$name]=1

  EXTRA_MOUNT_SRCS+=("$host_real")
  EXTRA_MOUNT_NAMES+=("$name")
  EXTRA_MOUNT_MODES+=("$mode")

  # For writable extra directories, protect any .git metadata read-only.
  if [[ "$mode" == "rw" && -d "$host_real" ]]; then
    local rel repo
    while IFS= read -r -d '' rel; do
      repo=$(dirname -- "$rel")

      if [[ $rel == *$'\n'* ]]; then
        echo "ERROR: Path with newline cannot be mounted: $host_real/$rel ($origin)" >&2
        exit 2
      fi

      if [[ -L "$host_real/$rel" ]]; then
        echo "ERROR: .git must not be a symlink: $host_real/$rel ($origin)" >&2
        exit 2
      fi

      if [[ -f "$host_real/$rel" ]]; then
        if [[ $repo == "." ]]; then
          echo "ERROR: Linked worktrees are not supported in writable extra mounts: $host_real ($origin)" >&2
          exit 2
        fi
        continue
      fi

      EXTRA_RO_GIT_SRCS+=("$(repo_path "$host_real" "$repo")/.git")
      EXTRA_RO_GIT_TARGETS+=("$(repo_path "/inputs/$name" "$repo")/.git")
    done < <(
      find "$host_real" \
        \( -name node_modules -o -name vendor -o -name .venv \) -prune \
        -o -name .git -printf '%P\0' -prune |
        sort -z
    )
  fi
}

while IFS= read -r entry; do
  add_extra_mount "$entry" "listed in $MOUNTS_FILE"
done < <(list_lines "$MOUNTS_FILE")

for entry in "${CLI_MOUNTS[@]}"; do
  add_extra_mount "$entry" "from --mount"
done

# ------------------------------------------------------------
# Secret files hidden from the agent
# ------------------------------------------------------------
# Untracked .env files are covered with a read-only /dev/null
# inside the container. Containers on the host still read the
# real files.
yaml_path() {
  # Single-quoted YAML; $ doubled against Compose interpolation.
  local value=${1//\$/\$\$}
  printf "'%s'" "${value//\'/\'\'}"
}

MASKED_TARGETS=()
MASKED_DISPLAY=()

collect_masked_env() {
  local host_root=$1
  local container_root=$2
  local display_prefix=$3
  local rel

  while IFS= read -r -d '' rel; do
    # Fail closed: such a path cannot be written as a mount target.
    if [[ $rel == *$'\n'* ]]; then
      echo "ERROR: File name with newline cannot be masked: $rel" >&2
      exit 2
    fi

    # Tracked files are in Git history anyway. Git answers for the
    # nearest repository around the file.
    if git --literal-pathspecs -C "$(dirname -- "$host_root/$rel")" \
         ls-files --error-unmatch -- "$(basename -- "$rel")" >/dev/null 2>&1; then
      continue
    fi

    MASKED_TARGETS+=("$container_root/$rel")
    MASKED_DISPLAY+=("${display_prefix}${rel}")
  done < <(
    find "$host_root" \
      \( -name .git -o -name node_modules -o -name vendor -o -name .venv \) -prune \
      -o -type f \( -name '.env*' -o -name '*.env' \) -printf '%P\0'
  )
}

collect_masked_env "$PROJECT_DIR" "/workspace" ""

for i in "${!EXTRA_MOUNT_SRCS[@]}"; do
  if [[ -d "${EXTRA_MOUNT_SRCS[i]}" ]]; then
    collect_masked_env "${EXTRA_MOUNT_SRCS[i]}" "/inputs/${EXTRA_MOUNT_NAMES[i]}" "/inputs/${EXTRA_MOUNT_NAMES[i]}/"
  fi
done

# ------------------------------------------------------------
# Generated mounts: read-only .git directories, extra mounts and masked files
# ------------------------------------------------------------
MOUNT_FILE="$STATE_DIR/mounts-${REPO_HASH}.yaml"

{
  printf 'services:\n  agent:\n    volumes:\n'

  for repo in "${REPOS[@]}"; do
    printf '      - type: bind\n'
    printf '        source: %s\n' "$(yaml_path "$(repo_path "$PROJECT_DIR" "$repo")/.git")"
    printf '        target: %s\n' "$(yaml_path "$(repo_path /workspace "$repo")/.git")"
    printf '        read_only: true\n'
    printf '        bind:\n'
    printf '          create_host_path: false\n'
  done

  for i in "${!EXTRA_MOUNT_SRCS[@]}"; do
    printf '      - type: bind\n'
    printf '        source: %s\n' "$(yaml_path "${EXTRA_MOUNT_SRCS[i]}")"
    printf '        target: %s\n' "$(yaml_path "/inputs/${EXTRA_MOUNT_NAMES[i]}")"
    if [[ "${EXTRA_MOUNT_MODES[i]}" == "ro" ]]; then
      printf '        read_only: true\n'
    fi
    printf '        bind:\n'
    printf '          create_host_path: false\n'
  done

  for i in "${!EXTRA_RO_GIT_SRCS[@]}"; do
    printf '      - type: bind\n'
    printf '        source: %s\n' "$(yaml_path "${EXTRA_RO_GIT_SRCS[i]}")"
    printf '        target: %s\n' "$(yaml_path "${EXTRA_RO_GIT_TARGETS[i]}")"
    printf '        read_only: true\n'
    printf '        bind:\n'
    printf '          create_host_path: false\n'
  done

  for target in "${MASKED_TARGETS[@]}"; do
    printf '      - type: bind\n'
    printf '        source: /dev/null\n'
    printf '        target: %s\n' "$(yaml_path "$target")"
    printf '        read_only: true\n'
  done

  if (( GPU )); then
    printf '      - type: bind\n'
    printf '        source: /usr/lib/wsl\n'
    printf '        target: /usr/lib/wsl\n'
    printf '        read_only: true\n'
    printf '    devices:\n'
    printf '      - /dev/dxg:/dev/dxg\n'
    printf '    environment:\n'
    printf '      GALLIUM_DRIVER: d3d12\n'
    printf '      LD_LIBRARY_PATH: /usr/lib/wsl/lib\n'
    if [[ -n $GPU_ADAPTER ]]; then
      printf '      MESA_D3D12_DEFAULT_ADAPTER_NAME: %s\n' "$(yaml_path "$GPU_ADAPTER")"
    fi
  fi

  # Ports of layers, merged with the VNC port in compose.yaml.
  if (( ${#LAYER_PORTS[@]} )); then
    printf '    ports:\n'
    for port in "${LAYER_PORTS[@]}"; do
      printf '      - "127.0.0.1:%s"\n' "$port"
    done
  fi
} >"$MOUNT_FILE.tmp"

mv -f -- "$MOUNT_FILE.tmp" "$MOUNT_FILE"

COMPOSE=(docker compose -f "$SCRIPT_DIR/compose.yaml" -f "$MOUNT_FILE")

# ------------------------------------------------------------
# Uncommitted changes
# ------------------------------------------------------------
# Prints uncommitted changes of all repositories; returns 1 if
# there are any.
check_clean() {
  local repo changes dirty=0

  for repo in "${REPOS[@]}"; do
    changes=$(git -C "$(repo_path "$PROJECT_DIR" "$repo")" status --porcelain)
    [[ -z "$changes" ]] && continue

    if (( dirty == 0 )); then
      echo "$1 $PROJECT_DIR:" >&2
    fi
    dirty=1

    if [[ $repo == "." ]]; then
      head -n 20 <<<"$changes" >&2
    else
      echo "  $repo:" >&2
      head -n 20 <<<"$changes" | sed 's/^/    /' >&2
    fi
  done

  return "$dirty"
}

# ------------------------------------------------------------
# VNC proxy (image paste from the Windows clipboard on WSL2)
# ------------------------------------------------------------
# VNC carries only text in its clipboard. vnc-paste-proxy.py runs
# on the host between the viewer and wayvnc: on Ctrl+V from the
# viewer it copies a Windows clipboard image into the container.
PROXY_PID_FILE="$STATE_DIR/vnc-proxy-${REPO_HASH}.pid"
PROXY_LOG="$STATE_DIR/vnc-proxy-${REPO_HASH}.log"

# Prints the PID of this sandbox's running proxy. The PID file
# may be stale after a reboot, so check the command line.
proxy_pid() {
  local pid cmdline
  pid=$(cat -- "$PROXY_PID_FILE" 2>/dev/null) || return 1
  [[ $pid =~ ^[0-9]+$ ]] || return 1
  cmdline=$(tr '\0' '\n' 2>/dev/null <"/proc/$pid/cmdline") || return 1
  grep -qxF -- "$SCRIPT_DIR/vnc-paste-proxy.py" <<<"$cmdline" || return 1
  printf '%s' "$pid"
}

stop_proxy() {
  local pid i
  if pid=$(proxy_pid); then
    kill "$pid" 2>/dev/null || true
    for i in $(seq 1 20); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
  fi
  rm -f -- "$PROXY_PID_FILE"
}

# ------------------------------------------------------------
# Management commands
# ------------------------------------------------------------
case "${1:-}" in
  --stop)
    stop_proxy
    "${COMPOSE[@]}" stop agent
    check_clean "WARNING: Uncommitted changes remain in" ||
      echo "Review them before restarting your local app or the sandbox." >&2
    exit 0
    ;;

  --down)
    stop_proxy
    "${COMPOSE[@]}" down
    check_clean "WARNING: Uncommitted changes remain in" ||
      echo "Review them before restarting your local app or the sandbox." >&2
    exit 0
    ;;

  --desktop-logs)
    "${COMPOSE[@]}" exec -T agent bash -c '
      cd /tmp/agent-runtime || exit 0
      for log in sway.log wayvnc.log start-hooks.log; do
        [[ -f $log ]] && tail -v -n 100 "$log"
      done
      true' || true
    printf '\n==> %s <==\n' "$PROXY_LOG"
    tail -n 100 -- "$PROXY_LOG" 2>/dev/null || true
    exit 0
    ;;
esac

# ------------------------------------------------------------
# Uncommitted changes at start
# ------------------------------------------------------------
# Only when the container actually starts, not when attaching
# to a running one.
running=$("${COMPOSE[@]}" ps --status running --quiet agent)

if [[ -z "$running" ]] &&
   ! check_clean "WARNING: Uncommitted changes in"; then
  echo "Review them before (re)starting your local app." >&2
fi

# ------------------------------------------------------------
# Start container
# ------------------------------------------------------------
if (( ${#EXTRA_MOUNT_SRCS[@]} )); then
  printf 'Extra mounts:\n'
  for i in "${!EXTRA_MOUNT_SRCS[@]}"; do
    printf '  /inputs/%s (%s) <- %s\n' \
      "${EXTRA_MOUNT_NAMES[i]}" "${EXTRA_MOUNT_MODES[i]}" "${EXTRA_MOUNT_SRCS[i]}"
  done
fi

if (( ${#MASKED_DISPLAY[@]} )); then
  printf 'Hidden from the agent:\n'
  printf '  %s\n' "${MASKED_DISPLAY[@]}"
fi

if (( GPU )); then
  printf 'GPU: %s\n' "${GPU_ADAPTER:-default}"
fi

# Base image, then each layer on top of the previous image.
# Docker's cache makes this fast when nothing changed.
BUILD_FLAGS=()
BASE_FLAGS=()

# --pull only for the base: layers build on local images.
if [[ ${FOXDEN_REBUILD:-0} == 1 ]]; then
  BUILD_FLAGS=(--no-cache)
  BASE_FLAGS=(--pull)
fi

docker build "${BUILD_FLAGS[@]}" "${BASE_FLAGS[@]}" \
  --build-arg HOST_UID --build-arg HOST_GID \
  -t foxden-base:local "$SCRIPT_DIR"

image=foxden-base:local

for i in "${!LAYERS[@]}"; do
  tag="foxden-layer$((i + 1)):local"
  printf 'Layer %d: %s\n' "$((i + 1))" "${LAYERS[i]}"
  docker build "${BUILD_FLAGS[@]}" \
    --build-arg "BASE=$image" \
    -t "$tag" "${LAYERS[i]}"
  image=$tag
done

"${COMPOSE[@]}" up -d agent

# Host variables from ~/.config/foxden/env that are set.
ENV_ARGS=()

for name in "${PASS_ENV[@]}"; do
  if [[ -n ${!name+set} ]]; then
    ENV_ARGS+=(--env "$name=${!name}")
  fi
done

# ------------------------------------------------------------
# Start headless Sway, wayvnc and start hooks in the container
# ------------------------------------------------------------
"${COMPOSE[@]}" exec -T "${ENV_ARGS[@]}" agent bash -s -- \
  "$DESKTOP_WIDTH" "$DESKTOP_HEIGHT" <<'IN_CONTAINER'

set -euo pipefail

width=$1
height=$2
runtime=${XDG_RUNTIME_DIR:-/tmp/agent-runtime}

mkdir -p "$runtime"
chmod 700 "$runtime"

for tool in sway swaymsg wayvnc dbus-run-session; do
  command -v "$tool" >/dev/null || {
    echo "ERROR: Missing $tool in the image." >&2
    exit 1
  }
done

# Minimal Sway configuration
config="$runtime/sway.conf"

cat > "$config" <<CFG
include /etc/foxden/sway.conf
output * mode --custom ${width}x${height}

# Save the graphical session environment
exec sh -c 'env | grep -E "^(DISPLAY|WAYLAND_DISPLAY|SWAYSOCK)=" > /tmp/agent-runtime/sway-env'
CFG

# Launch Sway only if it is not running.
if ! pgrep -u "$(id -u)" -x sway >/dev/null; then
  rm -f "$runtime/sway-env" "$runtime/desktop.env"

  nohup dbus-run-session -- sway -c "$config" \
    >"$runtime/sway.log" 2>&1 </dev/null &
fi

# ------------------------------------------------------------
# Discover the Wayland and Sway IPC sockets
# ------------------------------------------------------------
wayland=''
sway_sock=''
xdisplay=''

for i in $(seq 1 100); do
  if [[ -f "$runtime/sway-env" ]]; then
    wayland=$(
      sed -n 's/^WAYLAND_DISPLAY=//p' "$runtime/sway-env" |
        head -n 1
    )
    sway_sock=$(
      sed -n 's/^SWAYSOCK=//p' "$runtime/sway-env" |
        head -n 1
    )
    xdisplay=$(
      sed -n 's/^DISPLAY=//p' "$runtime/sway-env" |
        head -n 1
    )
  fi

  # Fallback to socket discovery.
  if [[ -z "$wayland" || ! -S "$runtime/$wayland" ]]; then
    for socket in "$runtime"/wayland-[0-9]*; do
      if [[ -S "$socket" ]]; then
        wayland=${socket##*/}
        break
      fi
    done
  fi

  if [[ -z "$sway_sock" || ! -S "$sway_sock" ]]; then
    for socket in "$runtime"/sway-ipc.*.sock; do
      if [[ -S "$socket" ]]; then
        sway_sock=$socket
        break
      fi
    done
  fi

  if [[ -n "$wayland" &&
        -S "$runtime/$wayland" &&
        -n "$sway_sock" &&
        -S "$sway_sock" ]] &&
     swaymsg -s "$sway_sock" -t get_outputs >/dev/null 2>&1; then
    break
  fi

  sleep 0.2
done

if [[ -z "$wayland" ||
      ! -S "$runtime/$wayland" ||
      -z "$sway_sock" ||
      ! -S "$sway_sock" ]]; then
  echo "ERROR: Sway failed to start." >&2
  tail -n 70 "$runtime/sway.log" >&2 || true
  exit 1
fi

# Apply resolution, including on subsequent launcher runs.
if ! swaymsg -s "$sway_sock" \
  "output * mode --custom ${width}x${height}" >/dev/null; then
  echo "ERROR: Failed to configure resolution." >&2
  tail -n 70 "$runtime/sway.log" >&2 || true
  exit 1
fi

# Share the session environment with later commands.
{
  printf 'WAYLAND_DISPLAY=%s\n' "$wayland"
  printf 'SWAYSOCK=%s\n' "$sway_sock"

  if [[ -n "$xdisplay" ]]; then
    printf 'DISPLAY=%s\n' "$xdisplay"
  fi
} > "$runtime/desktop.env"

chmod 600 "$runtime/desktop.env"

# ------------------------------------------------------------
# Start VNC server
# ------------------------------------------------------------
# Without --max-fps wayvnc sends at most 30 pictures per second.
if ! pgrep -u "$(id -u)" -x wayvnc >/dev/null; then
  nohup env \
    WAYLAND_DISPLAY="$wayland" \
    XDG_RUNTIME_DIR="$runtime" \
    wayvnc --max-fps=60 0.0.0.0 5900 \
    >"$runtime/wayvnc.log" 2>&1 </dev/null &
fi

# Check whether VNC is listening.
ready=false

for i in $(seq 1 100); do
  if ( : > /dev/tcp/127.0.0.1/5900 ) >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 0.2
done

if [[ "$ready" != true ]]; then
  echo "ERROR: wayvnc failed to start." >&2
  tail -n 70 "$runtime/wayvnc.log" >&2 || true
  exit 1
fi

# ------------------------------------------------------------
# Start hooks from layers
# ------------------------------------------------------------
# Run on every launcher start, as the agent user. A hook starts
# its services in the background, returns, and must not start a
# service that is already running.
for hook in /etc/foxden/start.d/*; do
  [[ -f $hook && -x $hook ]] || continue

  if ! (
    export WAYLAND_DISPLAY="$wayland" SWAYSOCK="$sway_sock"
    if [[ -n $xdisplay ]]; then
      export DISPLAY="$xdisplay"
    fi
    cd /workspace
    printf '==> %s\n' "$hook"
    exec timeout 60 "$hook" </dev/null
  ) >>"$runtime/start-hooks.log" 2>&1; then
    echo "WARNING: Start hook failed: $hook (see --desktop-logs)" >&2
  fi
done

printf 'Desktop ready: %sx%s (%s)\n' \
  "$width" "$height" "$wayland"

IN_CONTAINER

# ------------------------------------------------------------
# Start the VNC proxy
# ------------------------------------------------------------
container=$("${COMPOSE[@]}" ps --quiet agent)
upstream=$("${COMPOSE[@]}" port agent 5900)
upstream=${upstream##*:}

if [[ -z $container || ! $upstream =~ ^[0-9]+$ ]]; then
  echo "ERROR: Cannot find the published wayvnc port." >&2
  exit 1
fi

proxy=(python3 "$SCRIPT_DIR/vnc-paste-proxy.py"
  --listen-port "$VNC_PORT"
  --upstream-port "$upstream"
  --container "$container")

# Keep a proxy that already serves this container, so a second
# launcher run does not drop the open VNC connection.
if ! pid=$(proxy_pid) ||
   [[ $(tr '\0' '\n' 2>/dev/null <"/proc/$pid/cmdline") != \
      "$(printf '%s\n' "${proxy[@]}")" ]]; then
  stop_proxy

  # Own session: Ctrl+C and closing the terminal leave it running.
  setsid nohup "${proxy[@]}" >>"$PROXY_LOG" 2>&1 </dev/null &
  pid=$!
  printf '%s\n' "$pid" >"$PROXY_PID_FILE"

  ready=false
  for i in $(seq 1 50); do
    kill -0 "$pid" 2>/dev/null || break
    if ss -Hltnp "sport = :$VNC_PORT" | grep -qF "pid=$pid,"; then
      ready=true
      break
    fi
    sleep 0.1
  done

  if [[ $ready != true ]]; then
    echo "ERROR: VNC proxy failed to start." >&2
    tail -n 20 -- "$PROXY_LOG" >&2 || true
    exit 1
  fi
fi

# ------------------------------------------------------------
# Desktop available
# ------------------------------------------------------------
printf '\nVNC address: localhost:%s\n' "$VNC_PORT"
printf 'Resolution:  %sx%s\n\n' \
  "$DESKTOP_WIDTH" "$DESKTOP_HEIGHT"

if [[ "${1:-}" == "--desktop" ]]; then
  exit 0
fi

# ------------------------------------------------------------
# Your command, or a shell
# ------------------------------------------------------------
EXEC_ARGS=(--workdir /workspace "${ENV_ARGS[@]}")

if [[ $# -eq 0 ]]; then
  set -- bash
fi

# Keep running after Ctrl-C so the reminder below is still shown.
trap ':' INT

status=0

# Load Wayland session variables inside the container.
"${COMPOSE[@]}" exec "${EXEC_ARGS[@]}" agent \
  bash -c '
    if [[ -f /tmp/agent-runtime/desktop.env ]]; then
      while IFS="=" read -r name value; do
        case "$name" in
          WAYLAND_DISPLAY|SWAYSOCK|DISPLAY)
            export "$name=$value"
            ;;
        esac
      done </tmp/agent-runtime/desktop.env
    fi

    exec "$@"
  ' bash "$@" || status=$?

# Also shown when the session was aborted.
check_clean "WARNING: Uncommitted changes in" ||
  echo "Review them before (re)starting your local app." >&2

exit "$status"
