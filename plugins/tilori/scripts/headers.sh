#!/bin/sh
# MCP headersHelper: prints {"Authorization":"Bearer <agent key>"} on stdout
# for Claude Code, only if CLAUDE_CODE_MCP_SERVER_URL (set by Claude Code for
# helpers) matches "url" in ~/.config/tilori/config.json, so the key can never
# be sent to another host. The key comes from ~/.config/tilori/agents/<agent>.key;
# tilori-agent refuses it (fails closed) unless the file is 0600, its
# directories are 0700 and all are owned by you. stderr is discarded so the
# key or its path details never reach logs.
#
# On any failure (no agent, no key, a refused key or URL, no bun) it prints a
# fixed placeholder instead of nothing (UNI-693). With no Authorization
# header, Claude Code falls back to OAuth on the server's 401 and marks
# plugin:tilori:tilori "needs authentication" in ~/.claude/mcp-needs-auth-cache.json,
# for every session on the machine. With a header it doesn't: the
# connection just fails. The placeholder is a constant, not a secret; the
# server answers 401 and records nothing.
# ${0%/*}, not dirname: no external command runs from the project directory.
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
# Only output that carries an Authorization header passes: `{}` or other
# headers alone would still leave Claude Code to fall back to OAuth.
if out=$("$here/run-agent.sh" headers 2>/dev/null) && case "$out" in *'"Authorization"'*) true ;; *) false ;; esac; then
  printf '%s\n' "$out"
else
  printf '%s\n' '{"Authorization":"Bearer tilori-no-agent-key"}'
  echo 'tilori: no agent key for this session, so the Tilori MCP stays disconnected (see the plugin README, "No agent key")' >&2
fi
exit 0
