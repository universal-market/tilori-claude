#!/bin/sh
# Local checks (no CI): plugin and marketplace validation, shell syntax, secret scan.
set -eu
cd "$(dirname "$0")/.."
CLAUDE="${CLAUDE:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
echo "== plugin";      "$CLAUDE" plugin validate --strict ./plugins/tilori | tail -1
echo "== marketplace"; "$CLAUDE" plugin validate . | tail -1
echo "== wake probe";  "$CLAUDE" plugin validate ./tests/wake-probe/plugin | tail -1
echo "== shell";       for f in plugins/tilori/scripts/*.sh tests/wake-probe/plugin/probe.sh; do sh -n "$f"; done
echo "== json";        for f in .claude-plugin/marketplace.json plugins/tilori/.claude-plugin/plugin.json plugins/tilori/.mcp.json plugins/tilori/monitors/monitors.json; do python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f"; done
echo "== secret scan"
if git ls-files -z | xargs -0 grep -nE 'mcp_sk_[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9]|BEGIN (RSA|EC|OPENSSH) PRIVATE' -- 2>/dev/null; then
  echo "possible secret in tracked files" >&2; exit 1
fi
echo ok
