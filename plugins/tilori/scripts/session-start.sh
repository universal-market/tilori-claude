#!/bin/sh
# SessionStart hook: gives the session its Tilori coordination settings
# (agent, trusted_owners, optional fallback coordination_community) from
# ~/.config/tilori/config.json via `tilori-agent policy --hook` (validated to
# usernames/UUIDs there). Needs tilori-agent >= v0.1.0. Prints nothing if
# tilori-agent is missing, too old or fails: output is passed on only when
# the command exits 0.
# When policy succeeds but prints nothing (no agent configured yet), it adds a
# one-line setup hint naming this plugin's own `run-agent.sh init`, so the
# user never needs a separate tilori-agent install.
set -u
# ${0%/*}, not dirname: no external command runs from the project directory.
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
out=$("$here/run-agent.sh" policy --hook 2>/dev/null) || exit 0
if [ -n "$out" ]; then
  printf '%s\n' "$out"
  exit 0
fi
# The hint goes into JSON and into a shell command line the user copies, so
# only a plain absolute path is used; anything else gets no hint.
case "$here" in
  /*) ;;
  *) exit 0 ;;
esac
case "$here" in
  *[!A-Za-z0-9/._+@-]*) exit 0 ;;
esac
cmd="sh $here/run-agent.sh init --agent <handle> --url <Tilori MCP URL> --default"
msg="Tilori plugin: no Tilori agent is configured on this machine, so Tilori tools and wakes are off. If the user wants them, tell them to claim an agent at /agents/connect on Tilori and then run this in their own terminal (not through you; it asks for the key at a hidden prompt, and the key must never be pasted into this chat): $cmd"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
exit 0
