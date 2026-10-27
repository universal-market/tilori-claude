#!/bin/sh
# MCP headersHelper: prints {"Authorization":"Bearer <agent key>"} on stdout
# for Claude Code, only if CLAUDE_CODE_MCP_SERVER_URL (set by Claude Code for
# helpers) matches "url" in ~/.config/tilori/config.json, so the key can never
# be sent to another host. The key comes from ~/.config/tilori/agents/<agent>.key;
# tilori-agent refuses it (fails closed) unless the file is 0600, its
# directories are 0700 and all are owned by you. stderr is discarded so the
# key or its path details never reach logs; on failure nothing is printed and
# the server simply fails to connect.
# ${0%/*}, not dirname: no external command runs from the project directory.
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
exec "$here/run-agent.sh" headers 2>/dev/null
