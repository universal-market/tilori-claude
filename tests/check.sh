#!/bin/sh
# Local checks (no CI): plugin and marketplace validation, shell syntax, the
# bundled CLI (checksum + rebuild from its pinned tag), hostile cwd, secret scan.
# TILORI_SKIP_REBUILD=1 skips only the rebuild (needs gh access and the pinned Bun).
set -eu
cd "$(dirname "$0")/.."
CLAUDE="${CLAUDE:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
echo "== plugin";      "$CLAUDE" plugin validate --strict ./plugins/tilori | tail -1
echo "== marketplace"; "$CLAUDE" plugin validate . | tail -1
echo "== wake probe";  "$CLAUDE" plugin validate ./tests/wake-probe/plugin | tail -1
echo "== shell";       for f in plugins/tilori/scripts/*.sh tests/*.sh tools/*.sh tests/wake-probe/plugin/probe.sh; do sh -n "$f"; done
echo "== json";        for f in .claude-plugin/marketplace.json plugins/tilori/.claude-plugin/plugin.json plugins/tilori/.mcp.json plugins/tilori/monitors/monitors.json plugins/tilori/hooks/hooks.json; do python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f"; done
echo "== bundle checksum"
want=$(sed -n 's/^sha256=//p' plugins/tilori/vendor/SOURCE)
got=$( (sha256sum plugins/tilori/vendor/tilori-agent.js 2>/dev/null || shasum -a 256 plugins/tilori/vendor/tilori-agent.js) | cut -d' ' -f1)
[ -n "$want" ] && [ "$got" = "$want" ] || { echo "vendor/tilori-agent.js sha256 $got does not match SOURCE ($want)" >&2; exit 1; }
echo "$got"
echo "== bundle rebuild"
if [ "${TILORI_SKIP_REBUILD:-}" = 1 ]; then
  {
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!! WARNING: TILORI_SKIP_REBUILD=1, the bundle rebuild check was SKIPPED."
    echo "!! vendor/tilori-agent.js matches SOURCE's checksum, but nobody proved it"
    echo "!! is what the pinned tilori-agent tag builds to. Not valid for reviewing"
    echo "!! a change to plugins/tilori/vendor/: rerun without TILORI_SKIP_REBUILD."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  } >&2
  skipped_rebuild=1
else
  sh tools/bundle-agent.sh --verify
fi
echo "== hostile cwd"; sh tests/hostile-cwd.sh
echo "== secret scan"
if git ls-files -z | xargs -0 grep -nE 'mcp_sk_[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9]|BEGIN (RSA|EC|OPENSSH) PRIVATE' -- 2>/dev/null; then
  echo "possible secret in tracked files" >&2; exit 1
fi
if [ "${skipped_rebuild:-}" = 1 ]; then echo "ok (WARNING: bundle rebuild SKIPPED)"; else echo ok; fi
