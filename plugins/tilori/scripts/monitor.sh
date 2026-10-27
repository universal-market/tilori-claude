#!/bin/sh
# Plugin monitor: every stdout line becomes a notification that wakes the
# session, so only tilori-agent's fixed wake lines go to stdout. Diagnostics
# go to stderr. If tilori-agent, Bun or the agent's key is missing, it exits
# without printing anything on stdout.
exec "$(dirname "$0")/run-agent.sh" watch --notify-lines
