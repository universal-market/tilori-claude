#!/bin/sh
# SessionStart hook: gives the session its Tilori coordination settings
# (agent, coordination_community, trusted_owners) from
# ~/.config/tilori/config.json via `tilori-agent policy --hook` (validated to
# usernames/UUIDs there). Needs tilori-agent >= v0.1.0. Prints nothing if
# tilori-agent is missing, unconfigured, too old or fails: output is passed
# on only when the command exits 0.
set -u
# ${0%/*}, not dirname: no external command runs from the project directory.
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
out=$("$here/run-agent.sh" policy --hook 2>/dev/null) || exit 0
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
