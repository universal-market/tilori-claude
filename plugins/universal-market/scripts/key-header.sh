#!/bin/sh
# The no-runtime path of the MCP headersHelpers (UNI-769): releases the agent
# key with only sh and base utilities, so the Tilori and Market MCP servers
# connect without Bun, Node or a binary.
#
# It prints {"Authorization":"Bearer <key>"} and exits 0 only when every check
# below passes. Otherwise it prints nothing and exits 1, and the caller asks
# tilori-agent (`run-agent.sh headers`) as before. It can only release where
# tilori-agent would: tilori-agent writes ~/.config/tilori/headers.allow
# whenever it saves config.json, listing exactly the URLs `headers` releases a
# key to, and this script only does exact string matches against it.
#
#   default <agent>          the default agent
#   <agent> <server-url>     this agent's key may go to this URL
#
# The checks:
#   - TILORI_HOME is unset or the default home (other homes must be listed in
#     config.json, which only tilori-agent reads);
#   - the home and agents directories are 0700, and headers.allow,
#     config.json and the key file are 0600, owned by this user, and not
#     symlinks;
#   - config.json is not newer than headers.allow (no hand edit since);
#   - the agent ($TILORI_AGENT, else the default line) is a valid handle;
#   - "<agent> $CLAUDE_CODE_MCP_SERVER_URL" is a line of headers.allow;
#   - the key file is one line of [A-Za-z0-9._~+/=-] characters, as init
#     writes it, so it can go into JSON unescaped.
# The key goes only to stdout. Nothing is printed on failure.
#
# No external command runs before `cd /` and the fixed PATH, so a project
# directory can't supply its own `find` or `id`.
set -u
PATH=/usr/bin:/bin
export PATH
cd / || exit 1

case "${HOME:-}" in /?*) ;; *) exit 1 ;; esac
home="$HOME/.config/tilori"
case "${TILORI_HOME:-}" in "" | "$home" | "$home/") ;; *) exit 1 ;; esac

asked=${CLAUDE_CODE_MCP_SERVER_URL:-}
case "$asked" in https://?* | http://?*) ;; *) exit 1 ;; esac
case "$asked" in *[[:space:]]*) exit 1 ;; esac

uid=$(id -u) || exit 1
case "$uid" in "" | *[!0-9]*) exit 1 ;; esac

# private <path> d|f: a directory at 0700 or a regular file at 0600, owned by
# this user, not a symlink. find -perm with an octal mode matches the mode
# exactly, on GNU and BSD alike.
private() {
  [ -L "$1" ] && return 1
  if [ "$2" = d ]; then
    [ -d "$1" ] || return 1
    mode=700
  else
    [ -f "$1" ] || return 1
    mode=600
  fi
  [ -n "$(find "$1" -prune -user "$uid" -perm "$mode" -print 2>/dev/null)" ]
}

allow="$home/headers.allow"
config="$home/config.json"
private "$home" d || exit 1
private "$home/agents" d || exit 1
private "$allow" f || exit 1
private "$config" f || exit 1
[ -z "$(find "$config" -prune -newer "$allow" -print 2>/dev/null)" ] || exit 1

agent=${TILORI_AGENT:-}
if [ -z "$agent" ]; then
  # An agent named "default" has URL lines; the default line names a handle.
  while IFS=' ' read -r a b rest; do
    if [ "$a" = default ] && [ -z "$rest" ]; then
      case "$b" in *:*) ;; *) agent=$b ;; esac
    fi
  done <"$allow"
fi
case "$agent" in "" | [_-]* | *[!a-z0-9_-]*) exit 1 ;; esac
[ "${#agent}" -le 64 ] || exit 1

found=
while IFS=' ' read -r a u rest; do
  if [ "$a" = "$agent" ] && [ "$u" = "$asked" ] && [ -z "$rest" ]; then found=1; fi
done <"$allow"
[ -n "$found" ] || exit 1

keyfile="$home/agents/$agent.key"
private "$keyfile" f || exit 1
key=
IFS= read -r key <"$keyfile"
case "$key" in "" | *[!A-Za-z0-9._~+/=-]*) exit 1 ;; esac
# Exactly that line and its newline: anything more and tilori-agent decides.
size=$(wc -c <"$keyfile") || exit 1
[ "$((size + 0))" -eq "$((${#key} + 1))" ] || exit 1

printf '{"Authorization":"Bearer %s"}\n' "$key"
