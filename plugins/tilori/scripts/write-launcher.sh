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
# The launcher text for a scripts directory $1. Comparing a file with this
# for the sibling it names is how the no-downgrade guard below checks it.
launcher_text() {
  printf '#!/bin/sh\n'
  printf '# Written by the tilori Claude Code plugin at session start; do not edit.\n'
  printf '# Runs the tilori-agent CLI of the plugin version that last started a session.\n'
  # CLAUDE_PLUGIN_DATA too, for the compiled binary's cache when this runs
  # from a terminal or a service (fetch-agent.sh). Both paths are checked
  # above to hold only safe characters.
  printf 'CLAUDE_PLUGIN_DATA=%s exec /bin/sh %s/run-agent.sh "$@"\n' "$data" "$1"
}
content=$(launcher_text "$here")
# Never move the launcher back to an older plugin version. A session started
# from an older cached version (e.g. one that kept running across an update)
# would otherwise repoint the service at old code (UNI-800). If the launcher
# already names a sibling version directory that still has run-agent.sh and is
# newer than this one, leave it alone. Anything else (unreadable, unparseable,
# missing target, other parent, non-numeric version, loose permissions, edited content) is
# rewritten as before.
if [ -f "$data/tilori-agent" ] && [ ! -L "$data/tilori-agent" ] && [ -O "$data/tilori-agent" ]; then
  cur=$(sed -n 's|^CLAUDE_PLUGIN_DATA=[^ ]* exec /bin/sh \(/[^ ]*\)/run-agent\.sh "\$@"$|\1|p' "$data/tilori-agent" 2>/dev/null | head -n 1)
  # $cur and $here are scripts directories; the version directory is the parent.
  curdir=${cur%/*} mydir=${here%/*}
  if [ -n "$cur" ] && [ "$cur" != "$here" ] && [ "${cur##*/}" = "${here##*/}" ] && [ "${curdir%/*}" = "${mydir%/*}" ] && [ -f "$cur/run-agent.sh" ]; then
    # Dotted numeric compare: succeeds when $1 is strictly newer than $2.
    newer() {
      a=$1 b=$2
      while :; do
        case "$a$b" in *[!0-9.]*) return 1 ;; esac
        [ -n "$a" ] || [ -n "$b" ] || return 1
        x=${a%%.*} y=${b%%.*}
        [ -n "$x" ] || x=0
        [ -n "$y" ] || y=0
        [ "$x" -gt "$y" ] && return 0
        [ "$x" -lt "$y" ] && return 1
        case "$a" in *.*) a=${a#*.} ;; *) a= ;; esac
        case "$b" in *.*) b=${b#*.} ;; *) b= ;; esac
      done
    }
    # Only when the launcher is also not group/world-writable (a find failure
    # counts as loose); otherwise fall through so it is rewritten at mode 755.
    loose=$(find "$data/tilori-agent" -prune \( -perm -0020 -o -perm -0002 \) -print 2>/dev/null) || loose=x
    # ...and its whole content is exactly what we would have written for $cur.
    if [ -z "$loose" ] && printf '%s\n' "$(launcher_text "$cur")" | cmp -s - "$data/tilori-agent" \
      && newer "${curdir##*/}" "${mydir##*/}"; then exit 0; fi
  fi
fi
# Unchanged: leave the file (and its inode) alone, but only if it is a
# regular file we own that nobody else can write; otherwise rewrite it. -f
# also keeps cmp away from a planted FIFO or device.
if [ -f "$data/tilori-agent" ] && [ ! -L "$data/tilori-agent" ] && [ -O "$data/tilori-agent" ]; then
  loose=$(find "$data/tilori-agent" -prune \( -perm -0020 -o -perm -0002 \) -print 2>/dev/null) || loose=x
  if [ -z "$loose" ] && printf '%s\n' "$content" | cmp -s - "$data/tilori-agent"; then
    exit 0
  fi
fi
# mktemp creates a new regular file under a random name with O_EXCL, so a
# planted file, symlink, FIFO or device can't be written through or block us.
tmp=$(mktemp "$data/.tilori-agent.XXXXXX") || exit 0
case "$tmp" in "$data"/.tilori-agent.*) ;; *) exit 0 ;; esac
{ printf '%s\n' "$content" > "$tmp" && chmod 755 "$tmp" && mv -f "$tmp" "$data/tilori-agent"; } 2>/dev/null \
  || { rm -f "$tmp"; exit 0; }
exit 0
