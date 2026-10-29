#!/bin/sh
# Plugin and marketplace validation, shell syntax, the bundled CLI (checksum +
# rebuild from its pinned tag), hostile cwd, secret scan. CI runs it with both
# skips set (.github/workflows/check.yml); each skip prints a WARNING.
# TILORI_SKIP_REBUILD=1 skips only the rebuild (needs gh access and the pinned Bun).
# TILORI_SKIP_VALIDATE=1 skips only `claude plugin validate` (needs Claude Code).
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
  echo "== plugin";      "$CLAUDE" plugin validate --strict ./plugins/tilori | tail -1
  echo "== marketplace"; "$CLAUDE" plugin validate . | tail -1
  echo "== wake probe";  "$CLAUDE" plugin validate ./tests/wake-probe/plugin | tail -1
fi
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
echo "== monitor env"; sh tests/monitor-env.sh
echo "== prompt signal"; sh tests/prompt-signal.sh
echo "== config command"; sh tests/config-command.sh
echo "== release script"; sh tests/release.sh
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
