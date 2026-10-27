#!/bin/sh
# Prints the absolute path of the tilori-agent CLI: $TILORI_AGENT_BIN, then
# PATH, then Bun's global bin. Only absolute paths are accepted, so a "." or
# empty PATH entry can never select ./tilori-agent from the project
# directory. Exits 1 (printing nothing) when none is found.
set -u
case "${TILORI_AGENT_BIN:-}" in
  /*) [ -x "$TILORI_AGENT_BIN" ] && { echo "$TILORI_AGENT_BIN"; exit 0; } ;;
esac
p=$(command -v tilori-agent 2>/dev/null) || p=
case "$p" in
  /*) [ -x "$p" ] && { echo "$p"; exit 0; } ;;
esac
[ -x "$HOME/.bun/bin/tilori-agent" ] && case "$HOME" in /*) echo "$HOME/.bun/bin/tilori-agent"; exit 0 ;; esac
exit 1
