#!/bin/sh
# Plugin and marketplace validation, shell syntax, the bundled CLI (checksum +
# rebuild from its pinned tag), hostile cwd, secret scan. CI runs it with both
# skips set (.github/workflows/check.yml); each skip prints a WARNING.
# TILORI_SKIP_REBUILD=1 skips only the rebuild (needs gh access and the pinned Bun).
# TILORI_SKIP_VALIDATE=1 skips `claude plugin validate` and the needs-auth probe (need Claude Code).
set -eu
cd "$(dirname "$0")/.."
if [ "${TILORI_SKIP_VALIDATE:-}" = 1 ]; then
  {
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!! WARNING: TILORI_SKIP_VALIDATE=1, \`claude plugin validate\` was SKIPPED"
    echo "!! for the plugin, the marketplace and the wake probe. Run it locally."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  } >&2
  skipped_validate=1
else
  CLAUDE="${CLAUDE:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
  echo "== plugin";      "$CLAUDE" plugin validate --strict ./plugins/universal-market | tail -1
  echo "== marketplace"; "$CLAUDE" plugin validate . | tail -1
  echo "== wake probe";  "$CLAUDE" plugin validate ./tests/wake-probe/plugin | tail -1
  echo "== needs-auth probe"; CLAUDE="$CLAUDE" sh tests/needs-auth-probe.sh
fi
echo "== shell";       for f in plugins/universal-market/scripts/*.sh tests/*.sh tools/*.sh tests/wake-probe/plugin/probe.sh; do sh -n "$f"; done
echo "== json";        for f in .claude-plugin/marketplace.json plugins/universal-market/.claude-plugin/plugin.json plugins/universal-market/.mcp.json plugins/universal-market/monitors/monitors.json plugins/universal-market/hooks/hooks.json; do python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f"; done
echo "== bundle checksum"
want=$(sed -n 's/^sha256=//p' plugins/universal-market/vendor/SOURCE)
got=$( (sha256sum plugins/universal-market/vendor/tilori-agent.js 2>/dev/null || shasum -a 256 plugins/universal-market/vendor/tilori-agent.js) | cut -d' ' -f1)
[ -n "$want" ] && [ "$got" = "$want" ] || { echo "vendor/tilori-agent.js sha256 $got does not match SOURCE ($want)" >&2; exit 1; }
echo "$got"
echo "== old plugin names"
# UNI-905 (UNI-874 step 5, Don): the plugin is universal-market, with no
# backwards compatibility. No tracked file outside the vendored bundle may
# name the old id, its MCP server or tool prefix, its commands or skills, or
# its data path, and the old plugin directories are gone. The brackets keep
# this line from matching itself.
for d in plugins/"tilori" plugins/market; do [ ! -e "$d" ] || { echo "$d exists: the plugin is universal-market now" >&2; exit 1; }; done
if git ls-files -z -- . ':!plugins/universal-market/vendor' | xargs -0 grep -nE 'mcp__plugin_tilori[_]|plugin[:]tilori:|/tilori[:]|\btilori[:](tilori|market|contracts|config|setup)\b|tilori[@]tilori-claude|tilori-tilori[-]claude|plugins/tilor[i]\b' -- 2>/dev/null; then
  echo "old plugin name in tracked files: use universal-market (UNI-905)" >&2; exit 1
fi
echo "none"
echo "== bundle rebuild"
if [ "${TILORI_SKIP_REBUILD:-}" = 1 ]; then
  {
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!! WARNING: TILORI_SKIP_REBUILD=1, the bundle rebuild check was SKIPPED."
    echo "!! vendor/tilori-agent.js matches SOURCE's checksum, but nobody proved it"
    echo "!! is what the pinned tilori-agent tag builds to. Not valid for reviewing"
    echo "!! a change to plugins/universal-market/vendor/: rerun without TILORI_SKIP_REBUILD."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  } >&2
  skipped_rebuild=1
else
  sh tools/bundle-agent.sh --verify
fi
echo "== hostile cwd"; sh tests/hostile-cwd.sh
echo "== monitor env"; sh tests/monitor-env.sh
echo "== prompt signal"; sh tests/prompt-signal.sh
echo "== headers sentinel"; sh tests/headers-sentinel.sh
echo "== market headers"; sh tests/market-headers.sh
echo "== key header (no runtime)"; sh tests/key-header.sh
echo "== runtimes (bun, node, binary)"; sh tests/runtimes.sh
echo "== setup command"; sh tests/setup-command.sh
echo "== config command"; sh tests/config-command.sh
echo "== release script"; sh tests/release.sh
echo "== bundle verify"; sh tests/bundle-verify.sh
echo "== stale pin"; sh tests/stale-pin.sh
echo "== provision home"; sh tests/provision-home.sh
echo "== secret scan"
# Prints file:line only, never the matched text (CI logs are readable by
# anyone with repo access).
secret_re='mcp_sk_[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9]|sk-or-v1-[0-9a-f]{20,}|BEGIN (RSA|EC|OPENSSH) PRIVATE'
files=$(git ls-files -z | xargs -0 grep -lE "$secret_re" -- 2>/dev/null) || true
if [ -n "$files" ]; then
  printf '%s\n' "$files" | while IFS= read -r f; do
    grep -naE "$secret_re" -- "$f" | cut -d: -f1 | while read -r n; do printf '%s:%s\n' "$f" "$n"; done
  done >&2
  echo "possible secret in tracked files" >&2; exit 1
fi
skipped=
[ "${skipped_validate:-}" = 1 ] && skipped="validate"
[ "${skipped_rebuild:-}" = 1 ] && skipped="${skipped:+$skipped, }bundle rebuild"
if [ -n "$skipped" ]; then echo "ok (WARNING: SKIPPED $skipped)"; else echo ok; fi
