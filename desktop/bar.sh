#!/bin/bash
# Starts the bar and looks after two things it cannot do itself.
#
# Desktops: Sway drops an empty workspace as soon as it is left.
# Here a desktop stays until it is closed with "×". The open
# desktops are kept as one empty file each in $desktops, and the
# bar shows those instead of the workspaces Sway has right now.
# desktops.sh adds and removes them.
#
# Screen size: sfwbar keeps its width when the screen size
# changes, e.g. when the VNC viewer's window is resized, so it is
# restarted once the new size has settled.
set -eu

etc=$(dirname "$0")
runtime=${XDG_RUNTIME_DIR:-/tmp/agent-runtime}
desktops=$runtime/desktops
state=$runtime/desktops.state   # read by sfwbar.config

width() {
  swaymsg -t get_outputs | jq '[.[] | select(.active)][0].rect.width'
}

# Only 1 to 9 are desktops of the bar.
open_desktop() {
  case $1 in
    [1-9]) : >"$desktops/$1" ;;
  esac
}

# One line for the bar: d<number>=<0 closed, 1 open, 2 current>
report() {
  local current line n s
  current=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused).num')
  line=
  for n in 1 2 3 4 5 6 7 8 9; do
    s=0
    [ ! -e "$desktops/$n" ] || s=1
    [ "$n" != "$current" ] || s=2
    line+=" d$n=$s"
  done
  printf '%s\n' "$line" >"$state.new"
  mv "$state.new" "$state"
}

# Every workspace Sway has or creates is an open desktop.
mkdir -p "$desktops"
for n in $(swaymsg -t get_workspaces | jq -r '.[].num'); do
  open_desktop "$n"
done
report

current_width=$(width)

sfwbar -f "$etc/sfwbar.config" &
bar=$!

handle() {
  case $1 in
    workspace)
      [ "$2" != init ] || open_desktop "$3"
      report
      ;;
    output)
      resized=1
      ;;
  esac
}

# One line per change: "workspace <change> <number>" or "output".
swaymsg -t subscribe -m '["workspace", "output"]' |
  jq --unbuffered -r '
    if has("current") then "workspace \(.change) \(.current.num // "")"
    else "output" end' |
  while read -r kind change n; do
    resized=0
    handle "$kind" "$change" "$n"
    [ "$resized" = 1 ] || continue

    # Dragging the viewer's window sends many changes in a row;
    # wait until they stop.
    while read -r -t 0.5 kind change n; do
      handle "$kind" "$change" "$n"
    done

    wanted=$(width)
    [ "$wanted" != "$current_width" ] || continue

    current_width=$wanted
    # On SIGHUP sfwbar starts over with the same arguments.
    kill -HUP "$bar" 2>/dev/null || exit 0
  done
