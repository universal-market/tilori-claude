#!/bin/sh
# Prints the path of the tilori-agent CLI: $TILORI_AGENT_BIN, then PATH, then
# Bun's global bin. Exits 1 (printing nothing on stdout) when it is missing.
if [ -n "${TILORI_AGENT_BIN:-}" ] && [ -x "$TILORI_AGENT_BIN" ]; then
  echo "$TILORI_AGENT_BIN"; exit 0
fi
if command -v tilori-agent >/dev/null 2>&1; then
  command -v tilori-agent; exit 0
fi
if [ -x "$HOME/.bun/bin/tilori-agent" ]; then
  echo "$HOME/.bun/bin/tilori-agent"; exit 0
fi
exit 1
