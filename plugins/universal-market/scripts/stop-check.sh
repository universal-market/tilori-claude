#!/bin/sh
# The end-of-turn owner-decision check (tilori-agent README,
# "owner_decision_check"; design Tilori ad78d60f):
#   stop-check.sh hook   Stop hook: tilori-agent stop-check --hook
#   stop-check.sh asked  PostToolUse on ask_owner: tilori-agent stop-check --asked
#
# The check is off unless an agent's "owner_decision_check" is true in
# config.json, so a Stop hook on every turn of every session must cost
# nothing when it's off. This gate looks for that key set to true, with shell
# builtins only, and starts tilori-agent only then. tilori-agent decides
# which agent and checks the value exactly; this only skips the common case.
#
# stdin (the hook's JSON) goes to tilori-agent unread here. Nothing runs from
# the project directory (see run-agent.sh). stdout is tilori-agent's: one
# {"decision":"block",…} or nothing. It always exits 0, because a Stop
# hook's exit 2 would block the session.
set -u
case "${1:-}" in
  hook | asked) mode=$1 ;;
  *) exit 0 ;;
esac
case "$0" in
  /*) self=$0 ;;
  *) self="${PWD:-}/$0" ;;
esac
case "$self" in
  /*) ;;
  *) exit 0 ;;
esac
cd / || exit 0

home=${TILORI_HOME:-${HOME:-}/.config/tilori}
on=
if [ -f "$home/config.json" ] && [ ! -L "$home/config.json" ] && [ -r "$home/config.json" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'"owner_decision_check"'*true*) on=1; break ;;
    esac
  done < "$home/config.json"
fi
[ -n "$on" ] || exit 0

"${self%/*}/run-agent.sh" stop-check "--$mode" 2>/dev/null
exit 0
