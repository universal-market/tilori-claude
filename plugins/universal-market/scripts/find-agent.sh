#!/bin/sh
# Prints the absolute path of the tilori-agent CLI to run. Precedence:
#   1. $TILORI_AGENT_BIN, if absolute (an explicit override, e.g. a dev checkout);
#   2. the CLI bundled with this plugin (vendor/tilori-agent.js, pinned in
#      vendor/SOURCE and released with the plugin);
#   3. tilori-agent on PATH, then Bun's global bin (only if the bundle is
#      missing, e.g. a plugin checkout without vendor/).
# A separately installed tilori-agent is not preferred even if it is newer:
# the bundle is the version this plugin was tested and reviewed with. Set
# TILORI_AGENT_BIN to use another one. Only absolute paths are accepted, so a
# "." or empty PATH entry can never select ./tilori-agent from the project
# directory. Expects to be called by an absolute path from /, as run-agent.sh
# does. Exits 1 (printing nothing) when none is found.
set -u
case "${TILORI_AGENT_BIN:-}" in
  /*) [ -x "$TILORI_AGENT_BIN" ] && { echo "$TILORI_AGENT_BIN"; exit 0; } ;;
esac
case "$0" in
  /*/scripts/*)
    root=${0%/*}; root=${root%/*}
    [ -f "$root/vendor/tilori-agent.js" ] && { echo "$root/vendor/tilori-agent.js"; exit 0; } ;;
esac
p=$(command -v tilori-agent 2>/dev/null) || p=
case "$p" in
  /*) [ -x "$p" ] && { echo "$p"; exit 0; } ;;
esac
[ -x "$HOME/.bun/bin/tilori-agent" ] && case "$HOME" in /*) echo "$HOME/.bun/bin/tilori-agent"; exit 0 ;; esac
exit 1
