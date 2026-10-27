#!/bin/sh
# SessionStart hook: gives the session its Tilori coordination settings
# (agent, coordination_community, trusted_owners) from
# ~/.config/tilori/config.json via `tilori-agent policy --hook`. Values are
# validated to usernames/UUIDs there. Prints nothing if unconfigured.
set -u
here=$(dirname "$0")
bin=$("$here/find-agent.sh") || exit 0
exec "$bin" policy --hook 2>/dev/null
