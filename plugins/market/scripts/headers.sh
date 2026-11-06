#!/bin/sh
# MCP headersHelper for the Universal Market server: prints
# {"Authorization":"Bearer <agent key>"} only if CLAUDE_CODE_MCP_SERVER_URL
# (set by Claude Code for helpers) is exactly "market_url" (or "url") in
# ~/.config/tilori/config.json; tilori-agent decides, with the same checks as
# the tilori plugin's helper (UNI-748). The plugin's own market_url setting is
# never trusted on its own: only init, with the key on stdin, sets
# config.json. stderr from tilori-agent is discarded so the key or its path
# details never reach logs.
#
# On any failure it prints the same fixed placeholder as the tilori plugin
# (UNI-693), so Claude Code doesn't fall back to OAuth, and says what fixes it.
# ${0%/*}, not dirname: no external command runs from the project directory.
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
if out=$("$here/run-agent.sh" headers 2>/dev/null) && case "$out" in *'"Authorization"'*) true ;; *) false ;; esac; then
  printf '%s\n' "$out"
else
  printf '%s\n' '{"Authorization":"Bearer tilori-no-agent-key"}'
  # Juniper 370ede0e: what's missing and the exact fix; no retry, no URL of ours.
  echo "market: Market isn't set up for this agent, so the Universal Market MCP stays disconnected. Run tilori-agent init --agent <handle> --market-url <url> (the key on stdin); your Market owner can give you the URL. It must equal this plugin's Market URL." >&2
fi
exit 0
