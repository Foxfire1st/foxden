# Read by /usr/bin/chromium on every start.
# In the image: /etc/chromium.d/foxden-lock
#
# Chromium's profile lock names the host it was taken on. A
# recreated container has a new hostname, so a lock left in the
# home volume makes Chromium refuse the profile as "in use on
# another computer". The home volume belongs to this container
# alone, which makes a lock from another host a leftover.
agent_lock="${XDG_CONFIG_HOME:-$HOME/.config}/chromium/SingletonLock"
case "$(readlink "$agent_lock" 2>/dev/null)" in
  "" | "$(uname -n)"-*) ;;
  *) rm -f "$agent_lock" "${agent_lock%Lock}Socket" "${agent_lock%Lock}Cookie" ;;
esac
unset agent_lock
