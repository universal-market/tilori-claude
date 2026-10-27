#!/bin/sh
# Runs tilori-agent with the given arguments. Finds the CLI (find-agent.sh)
# and a Bun to run it with: the CLI's `#!/usr/bin/env bun` shebang only works
# when bun is on PATH, which Claude Code's environment often lacks. Exits 127
# (printing nothing on stdout) when either is missing.
set -u
here=$(dirname "$0")
bin=$("$here/find-agent.sh") || exit 127
if command -v bun >/dev/null 2>&1; then
  exec bun "$bin" "$@"
fi
b="${BUN_INSTALL:-$HOME/.bun}/bin/bun"
if [ -x "$b" ]; then
  exec "$b" "$bin" "$@"
fi
echo "tilori: bun not found (install Bun or put it on PATH)" >&2
exit 127
