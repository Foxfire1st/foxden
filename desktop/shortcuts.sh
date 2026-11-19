#!/bin/sh
# Shortcut overview of the bar: a list above all windows. It
# stays until Esc, Alt+F1, a second click on the button or a
# click outside it. Typing filters.
list=/etc/foxden/shortcuts.txt

# Open, also as program search: close it.
pkill -x fuzzel && exit 0

# A click on the bar's button closes the overview before the bar
# runs this script again. The first run still holds the lock
# then, and the second one must not reopen the overview.
exec 9>"${XDG_RUNTIME_DIR:-/tmp/agent-runtime}/shortcuts.lock"
flock -n 9 || exit 0

# fuzzel closes when it loses the keyboard, which a click outside
# it causes. Moving the pointer onto the bar or another window
# would do the same, so focus stops following the mouse while the
# overview is open. "yes" is Sway's default.
swaymsg -q focus_follows_mouse no
trap 'swaymsg -q focus_follows_mouse yes' EXIT

fuzzel --dmenu \
  --prompt 'Shortcuts  ' \
  --lines "$(wc -l <"$list")" \
  --width 66 \
  --font 'DejaVu Sans Mono:size=12' \
  <"$list" >/dev/null

# Keeps the lock for the second run described above.
sleep 0.3
