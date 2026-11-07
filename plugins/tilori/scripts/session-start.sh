#!/bin/sh
# SessionStart hook: gives the session its Tilori settings
# (agent, trusted_owners, optional fallback coordination_community) from
# ~/.config/tilori/config.json via `tilori-agent policy --hook` (validated to
# usernames/UUIDs there). Needs tilori-agent >= v0.1.0. Prints nothing if
# tilori-agent is missing, too old or fails: output is passed on only when
# the command exits 0.
# When policy succeeds but prints nothing, it adds a one-line hint in fixed
# text: either no agent is configured yet (with this plugin's own
# `run-agent.sh init` command), or the config is broken. CLI output is never
# passed on in the hint.
# It also refreshes the stable launcher in $CLAUDE_PLUGIN_DATA (write-launcher.sh).
set -u
# ${0%/*}, not dirname: no external command runs from the project directory.
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
"$here/write-launcher.sh" >/dev/null 2>&1 || :
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
# policy prints nothing both when no agent is set and when config.json or the
# handle is unusable. key-path tells them apart: it fails with the fixed
# "No agent selected." only in the first case. Its stderr is matched, never
# shown. If key-path succeeds, policy's silence is unexplained: no hint.
err=$("$here/run-agent.sh" key-path 2>&1 >/dev/null) && exit 0
case "$err" in
  *"tilori-agent: No agent selected."*)
    msg="Tilori plugin: no Tilori agent is configured on this machine, so Tilori tools and wakes are off. If the user wants them, tell them to run /tilori:setup in this session: it shows a link to approve the agent in their browser, and the plugin stores the key itself (never paste a key into this chat)." ;;
  *)
    msg="Tilori plugin: the Tilori config is broken, so Tilori tools and wakes are off. ~/.config/tilori/config.json could not be used (unreadable, not 0600 in a 0700 directory, or not valid JSON), or the agent handle in it or in TILORI_AGENT is invalid. Tell the user to check it in their own terminal with: sh $here/run-agent.sh key-path (it prints the key file's path or the problem, never the key). Do not read or edit files under ~/.config/tilori yourself." ;;
esac
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
exit 0
