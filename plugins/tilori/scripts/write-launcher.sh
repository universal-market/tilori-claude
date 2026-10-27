#!/bin/sh
# Writes a stable launcher, $CLAUDE_PLUGIN_DATA/tilori-agent, that runs this
# plugin version's run-agent.sh. Claude Code keeps CLAUDE_PLUGIN_DATA
# (~/.claude/plugins/data/<plugin>) across plugin updates, while the plugin
# directory changes with every version, so a systemd unit for the router can
# point at the launcher. session-start.sh refreshes it at every session start.
# Writes nothing (and exits 0) unless both paths are plain absolute paths.
# As in run-agent.sh, no external command runs before `cd /`.
set -u
case "$0" in
  /*) self=$0 ;;
  *) self="${PWD:-}/$0" ;;
esac
case "$self" in /*) ;; *) exit 0 ;; esac
data=${CLAUDE_PLUGIN_DATA:-}
case "$data" in /*) ;; *) exit 0 ;; esac
cd / || exit 0
here=$(cd "${self%/*}" && pwd -P) || exit 0
for path in "$here" "$data"; do
  case "$path" in *[!A-Za-z0-9/._+@-]*) exit 0 ;; esac
done
mkdir -p "$data" || exit 0
tmp="$data/.tilori-agent.$$"
{
  printf '#!/bin/sh\n'
  printf '# Written by the tilori Claude Code plugin at session start; do not edit.\n'
  printf '# Runs the tilori-agent CLI of the plugin version that last started a session.\n'
  printf 'exec /bin/sh %s/run-agent.sh "$@"\n' "$here"
} > "$tmp" && chmod 755 "$tmp" && mv -f "$tmp" "$data/tilori-agent" || { rm -f "$tmp"; exit 0; }
exit 0
