#!/bin/sh
# "+" and "×" of the bar. A desktop is a Sway workspace, numbered
# 1 to 9 like the Alt+1 … 9 bindings. bar.sh explains how the
# open desktops are kept in $desktops.
#   add    switch to the lowest free desktop
#   close  move the windows of the current desktop to its
#          neighbour, switch there and forget the desktop
set -eu

desktops=${XDG_RUNTIME_DIR:-/tmp/agent-runtime}/desktops

case "${1:-}" in
  add)
    for n in 1 2 3 4 5 6 7 8 9; do
      [ -e "$desktops/$n" ] || exec swaymsg -q workspace number "$n"
    done
    ;;
  close)
    current=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused).num')

    # Neighbour: next lower number, else next higher. The last
    # desktop has none and stays.
    target=$(ls "$desktops" | sort -n | awk -v c="$current" '
      $1 < c { t = $1 }
      $1 > c && t == "" { t = $1 }
      END { print t }')
    [ -n "$target" ] || exit 0

    # Matched by number: __focused__ also catches the windows of
    # other desktops while the current one is empty.
    swaymsg -q "[workspace=\"^$current\$\"] move container to workspace number $target" || true
    rm -f "$desktops/$current"
    swaymsg -q workspace number "$target"
    ;;
  *)
    echo "Usage: desktops.sh add|close" >&2
    exit 2
    ;;
esac
