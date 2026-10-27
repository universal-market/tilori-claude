#!/bin/sh
# Writes a stable launcher, $CLAUDE_PLUGIN_DATA/tilori-agent, that runs this
# plugin version's run-agent.sh. Claude Code keeps CLAUDE_PLUGIN_DATA
# (~/.claude/plugins/data/<plugin>) across plugin updates, while the plugin
# directory changes with every version, so a systemd unit for the router can
# point at the launcher. session-start.sh refreshes it at every session start.
# Writes nothing (and exits 0) unless both paths are plain absolute paths
# (so a plugin path with a space gets no launcher) and the data directory is
# private to this user.
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
# The data directory must be ours alone: not a symlink, owned by us, and not
# group- or world-writable (else another user could swap the launcher).
# find without -H does not follow a symlink given on its command line, so a
# symlinked $data also fails the permission check.
umask 077
[ -L "$data" ] && exit 0
mkdir -p "$data" || exit 0
[ -d "$data" ] && [ ! -L "$data" ] && [ -O "$data" ] || exit 0
# Claude Code creates the data directory with the user's umask, often 0775.
# It is ours and not a symlink, so drop group/other write before trusting it
# (others lose write access at once); if that fails, the check below refuses.
chmod go-w "$data" 2>/dev/null || :
loose=$(find "$data" -prune \( -perm -0020 -o -perm -0002 \) -print 2>/dev/null) || exit 0
[ -z "$loose" ] || exit 0
content=$(
  printf '#!/bin/sh\n'
  printf '# Written by the tilori Claude Code plugin at session start; do not edit.\n'
  printf '# Runs the tilori-agent CLI of the plugin version that last started a session.\n'
  printf 'exec /bin/sh %s/run-agent.sh "$@"\n' "$here"
)
# Unchanged: leave the file (and its inode) alone.
if [ -f "$data/tilori-agent" ] && [ ! -L "$data/tilori-agent" ] \
  && printf '%s\n' "$content" | cmp -s - "$data/tilori-agent"; then
  exit 0
fi
# noclobber: the temp name must not exist yet, so a planted file or symlink
# makes the write fail instead of being followed.
tmp="$data/.tilori-agent.$$"
(set -C; printf '%s\n' "$content" > "$tmp") 2>/dev/null || exit 0
chmod 755 "$tmp" && mv -f "$tmp" "$data/tilori-agent" || { rm -f "$tmp"; exit 0; }
exit 0
