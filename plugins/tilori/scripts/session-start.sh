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
# The copyable command pre-fills only plugin.json's default URLs (UNI-773).
# Session env, and so a project's settings, can set TILORI_MCP_URL,
# TILORI_MARKET_URL or CLAUDE_PLUGIN_OPTION_*; a pre-filled URL from there
# would bind the key the user types to a server they didn't choose (Bastion
# b7ad41ff). When any of them names something else, the command keeps the
# placeholder and a fixed sentence says so; their value is never shown.
d_tilori=https://tilori.ai/mcp/tilori/v1
d_market=https://healthy-clownfish-904.convex.site/mcp/v1
tilori_url=$d_tilori market_url=$d_market other=
for v in "${TILORI_MCP_URL:-$d_tilori}" "${CLAUDE_PLUGIN_OPTION_TILORI_URL:-$d_tilori}"; do
  [ "$v" = "$d_tilori" ] || { tilori_url='<Tilori MCP URL>'; other=1; }
done
for v in "${TILORI_MARKET_URL:-$d_market}" "${CLAUDE_PLUGIN_OPTION_MARKET_URL:-$d_market}"; do
  [ "$v" = "$d_market" ] || { market_url='<Market MCP URL>'; other=1; }
done
note=
[ -z "$other" ] || note=" This session names a different Tilori or Market URL than the plugin's defaults; the user should fill in the placeholder only with a URL they set up themselves."
case "$err" in
  *"tilori-agent: No agent selected."*)
    msg="Tilori plugin: no Tilori agent is configured on this machine, so Tilori tools and wakes are off. If the user wants them, tell them to claim an agent at /agents/connect on Tilori and then run this in their own terminal (not through you; it asks for the key at a hidden prompt, and the key must never be pasted into this chat), with their agent's handle for <handle>: sh $here/run-agent.sh init --agent <handle> --url $tilori_url --market-url $market_url --default$note" ;;
  *)
    msg="Tilori plugin: the Tilori config is broken, so Tilori tools and wakes are off. ~/.config/tilori/config.json could not be used (unreadable, not 0600 in a 0700 directory, or not valid JSON), or the agent handle in it or in TILORI_AGENT is invalid. Tell the user to check it in their own terminal with: sh $here/run-agent.sh key-path (it prints the key file's path or the problem, never the key). Do not read or edit files under ~/.config/tilori yourself." ;;
esac
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg"
exit 0
