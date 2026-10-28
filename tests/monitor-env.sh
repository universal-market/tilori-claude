#!/bin/sh
# monitor.sh passes the plugin's own version, the install record path and the
# plugin key to tilori-agent in the environment (and nothing when plugin.json
# has no usable version). A fake CLI prints what it sees.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
realbun=$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")
[ -x "$realbun" ] || { echo "skip: bun not installed"; exit 0; }

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
plugin="$t/plugin"; mkdir -p "$plugin/.claude-plugin"
cp -R "$repo/plugins/tilori/scripts" "$plugin/scripts"
h="$t/home"; mkdir -p "$h/.bun/bin" "$h/pkg/src"
ln -s "$realbun" "$h/.bun/bin/bun"
cat > "$h/pkg/src/cli.ts" <<'TS'
#!/usr/bin/env bun
const e = process.env;
console.log(`v=${e.TILORI_PLUGIN_VERSION ?? '-'} m=${e.TILORI_PLUGIN_MANIFEST ?? '-'} k=${e.TILORI_PLUGIN_KEY ?? '-'} args=${process.argv.slice(2).join(',')}`);
TS
chmod +x "$h/pkg/src/cli.ts"
ln -s ../../pkg/src/cli.ts "$h/.bun/bin/tilori-agent"
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { env -i HOME="$h" PATH=/usr/bin:/bin "$@" "$plugin/scripts/monitor.sh" 2>&1; }

cp "$repo/plugins/tilori/.claude-plugin/plugin.json" "$plugin/.claude-plugin/plugin.json"
v=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$plugin/.claude-plugin/plugin.json")
out=$(run)
[ "$out" = "v=$v m=$h/.claude/plugins/installed_plugins.json k=tilori@tilori-claude args=watch,--notify-lines" ] || fail "real plugin.json: $out"
out=$(run CLAUDE_CONFIG_DIR=/cfg)
[ "$out" = "v=$v m=/cfg/plugins/installed_plugins.json k=tilori@tilori-claude args=watch,--notify-lines" ] || fail "CLAUDE_CONFIG_DIR: $out"

# No usable version: nothing is passed, and inherited values are cleared.
printf '{ "name": "tilori", "version": "0.1.x; touch /tmp/x" }\n' > "$plugin/.claude-plugin/plugin.json"
out=$(run TILORI_PLUGIN_VERSION=9.9.9)
[ "$out" = "v=- m=- k=- args=watch,--notify-lines" ] || fail "bad version: $out"
rm "$plugin/.claude-plugin/plugin.json"
out=$(run)
[ "$out" = "v=- m=- k=- args=watch,--notify-lines" ] || fail "no plugin.json: $out"
echo "monitor-env: ok"
