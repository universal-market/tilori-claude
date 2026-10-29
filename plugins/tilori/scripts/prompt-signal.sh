#!/bin/sh
# PostToolUse ("activity") and Notification ("blocked") hook: tells the local
# tilori-agent router whether this session is stuck on a prompt, by touching
# an empty file in the router's own run directory:
#   activity-<agent>  after every tool call
#   blocked-<agent>   when a permission or elicitation prompt is shown
# The router logs a session that stays blocked while wakes arrive, and
# `tilori-agent status` shows it (tilori-agent README, "Blocked on a prompt").
#
# It never reads its input (the tool call or the prompt text): stdin is
# closed unread. The agent comes from $TILORI_AGENT, else "default_agent" in
# config.json, the same order as tilori-agent, and must be a valid handle.
# It runs no tilori-agent and no external command except /bin/ls (the cwd is
# the project, and PATH may hold "."). It never creates the directory: only
# the router does, 0700. If the directory is missing, a symlink, not ours or
# not 0700, it does nothing. It prints nothing and always exits 0.
exec </dev/null >/dev/null 2>&1
umask 077
case "${1:-}" in
  activity | blocked) kind=$1 ;;
  *) exit 0 ;;
esac

home=${TILORI_HOME:-${HOME:-}/.config/tilori}
agent=${TILORI_AGENT:-}
if [ -z "$agent" ] && [ -r "$home/config.json" ]; then
  # Shell builtins only; "default_agent" is a top-level string.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'"default_agent"'*)
        agent=${line#*'"default_agent"'}
        agent=${agent#*'"'}
        agent=${agent%%'"'*}
        break ;;
    esac
  done < "$home/config.json"
fi
# The same rule as tilori-agent's validateHandle: 1-64 of [a-z0-9_-], not
# starting with _ or -. Nothing else reaches a path.
case "$agent" in
  '' | [_-]* | *[!a-z0-9_-]*) exit 0 ;;
esac
[ "${#agent}" -le 64 ] || exit 0

# The router's run directory, as tilori-agent's socketPath() finds it.
if [ -n "${TILORI_SOCKET:-}" ]; then
  dir=${TILORI_SOCKET%/*}
elif [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  dir=$XDG_RUNTIME_DIR/tilori
else
  dir=$home/run
fi
case "$dir" in
  /*) ;;
  *) exit 0 ;;
esac
[ -d "$dir" ] && [ ! -L "$dir" ] && [ -O "$dir" ] || exit 0
[ -x /bin/ls ] || exit 0
set -f
set -- $(/bin/ls -ld "$dir")
case "${1:-}" in
  drwx------*) ;;
  *) exit 0 ;;
esac

f=$dir/$kind-$agent
[ -L "$f" ] && exit 0
if [ -e "$f" ]; then
  [ -f "$f" ] && [ -O "$f" ] || exit 0
fi
# Truncating an empty file updates its mtime (POSIX open with O_TRUNC).
: > "$f"
exit 0
