#!/bin/sh
# Plugin monitor: every stdout line becomes a notification that wakes the
# session, so only tilori-agent's fixed wake lines go to stdout. Diagnostics
# go to stderr. If tilori-agent or the agent's key is missing, exit quietly.
set -u
here=$(dirname "$0")
bin=$("$here/find-agent.sh") || {
  echo "tilori: tilori-agent is not installed; see the tilori-claude README" >&2
  exit 0
}
exec "$bin" watch --notify-lines
