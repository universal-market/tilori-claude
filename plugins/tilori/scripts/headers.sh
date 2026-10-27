#!/bin/sh
# MCP headersHelper: prints {"Authorization":"Bearer <agent key>"} on stdout
# for Claude Code. The key comes from ~/.config/tilori/agents/<agent>.key;
# tilori-agent refuses it (fails closed) unless the file is 0600, its
# directories are 0700 and all are owned by you. stderr is discarded so the
# key or its path details never reach logs; on failure nothing is printed and
# the server simply fails to connect.
set -u
here=$(dirname "$0")
bin=$("$here/find-agent.sh") || exit 1
exec "$bin" headers 2>/dev/null
