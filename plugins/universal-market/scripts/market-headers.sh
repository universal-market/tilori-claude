#!/bin/sh
# MCP headersHelper for the Universal Market server, part of the tilori
# plugin since UNI-768 (it was the market plugin's headers.sh): prints
# {"Authorization":"Bearer <agent key>"} only if CLAUDE_CODE_MCP_SERVER_URL
# (set by Claude Code for helpers) is exactly "market_url" (or "url") in
# ~/.config/tilori/config.json; tilori-agent decides, with the same checks as
# the Tilori server's helper (UNI-748). The plugin's own market_url setting is
# never trusted on its own: only init, with the key on stdin, sets
# config.json. stderr from tilori-agent is discarded so the key or its path
# details never reach logs.
#
# On any failure it prints the same fixed placeholder as the Tilori server
# (UNI-693), so Claude Code doesn't fall back to OAuth, and says what fixes it.
# ${0%/*}, not dirname: no external command runs from the project directory.
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
# key-header.sh first: no runtime needed (UNI-769). It prints nothing unless
# it can release the key exactly where tilori-agent would; then ask tilori-agent.
if { out=$(/bin/sh "$here/key-header.sh" 2>/dev/null) || out=$("$here/run-agent.sh" headers 2>/dev/null); } && case "$out" in *'"Authorization"'*) true ;; *) false ;; esac; then
  printf '%s\n' "$out"
else
  printf '%s\n' '{"Authorization":"Bearer tilori-no-agent-key"}'
  # Juniper 370ede0e, UNI-860: name the server Claude Code is calling (the
  # placeholder above makes it answer 401 invalid_token), the likely cause and
  # the one next step. The URL is printed only if it carries no credentials.
  srv=${CLAUDE_CODE_MCP_SERVER_URL:-}
  case "$srv" in https://?* | http://?*) case "$srv" in *[@?#[:cntrl:][:space:]]*) srv="the Market server" ;; esac ;; *) srv="the Market server" ;; esac
  echo "market: no key was sent to $srv, so Market will answer 401 invalid_token. Most likely this plugin's market_url differs from the one in ~/.config/tilori/config.json, the only URL the key is sent to, so nothing leaked. Fix: run sh ~/.claude/plugins/data/universal-market-tilori-claude/tilori-agent sync-plugin in a terminal and follow what it prints. If config.json has no market_url, the session start note says what to add; if this agent isn't set up on this machine, run /universal-market:setup." >&2
fi
exit 0
