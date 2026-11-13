#!/bin/sh
# The Market server's headers helper, scripts/market-headers.sh in the tilori
# plugin (UNI-748; moved from the market plugin in UNI-768): same contract as the tilori
# helper (tests/headers-sentinel.sh). It never prints nothing, prints the
# fixed placeholder on any failure with the market note on stderr, and passes
# a key from run-agent.sh through unchanged without showing its stderr.
# Whether the key is released for the Market URL is tilori-agent's `headers`
# decision (market_url in config.json), tested in tilori-agent.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
SENTINEL='{"Authorization":"Bearer tilori-no-agent-key"}'
NOTE_TAIL="so Market will answer 401 invalid_token. Most likely this plugin's market_url differs from the one in ~/.config/tilori/config.json, the only URL the key is sent to, so nothing leaked. Fix: run sh ~/.claude/plugins/data/tilori-tilori-claude/tilori-agent sync-plugin in a terminal and follow what it prints. If config.json has no market_url, the session start note says what to add; if this agent isn't set up on this machine, run /tilori:setup."
NOTE="market: no key was sent to the Market server, $NOTE_TAIL"

stub() {
  rm -rf "$t/s"; mkdir -p "$t/s"; cp "$repo/plugins/tilori/scripts/market-headers.sh" "$t/s/headers.sh"
  printf '#!/bin/sh\n%s\n' "$1" > "$t/s/run-agent.sh"; chmod +x "$t/s/headers.sh" "$t/s/run-agent.sh"
}
run() { (cd / && env -i HOME="$t/home" PATH=/usr/bin:/bin "$t/s/headers.sh" 2>"$t/err"); }

# The helper asks tilori-agent for `headers`, nothing else.
stub 'printf "%s\n" "$*" > "$(dirname "$0")/args"; exit 1'
run >/dev/null
[ "$(cat "$t/s/args")" = headers ] || fail "run-agent.sh called with: $(cat "$t/s/args")"

stub 'echo "secret detail" >&2; exit 1'
out=$(run) || fail "failing helper exited non-zero"
[ "$out" = "$SENTINEL" ] || fail "failing helper: $out"
[ "$(cat "$t/err")" = "$NOTE" ] || fail "failing helper stderr: $(cat "$t/err")"

# UNI-860: the note names the server Claude Code called, never one with credentials.
stub 'exit 1'
(cd / && env -i HOME="$t/home" PATH=/usr/bin:/bin CLAUDE_CODE_MCP_SERVER_URL=https://m.example.test/mcp/v1 "$t/s/headers.sh" 2>"$t/err" >/dev/null)
[ "$(cat "$t/err")" = "market: no key was sent to https://m.example.test/mcp/v1, $NOTE_TAIL" ] || fail "note without server: $(cat "$t/err")"
(cd / && env -i HOME="$t/home" PATH=/usr/bin:/bin CLAUDE_CODE_MCP_SERVER_URL='https://u:pw@m.example.test/mcp/v1?k=1' "$t/s/headers.sh" 2>"$t/err" >/dev/null)
[ "$(cat "$t/err")" = "$NOTE" ] || fail "credentialed URL printed: $(cat "$t/err")"
# UNI-867: control characters (ESC, CR) and a plain space in the URL never reach stderr.
(cd / && env -i HOME="$t/home" PATH=/usr/bin:/bin CLAUDE_CODE_MCP_SERVER_URL="$(printf 'https://m.example.test/\033[31mx')" "$t/s/headers.sh" 2>"$t/err" >/dev/null)
[ "$(cat "$t/err")" = "$NOTE" ] || fail "control character URL printed: $(cat "$t/err")"
(cd / && env -i HOME="$t/home" PATH=/usr/bin:/bin CLAUDE_CODE_MCP_SERVER_URL="$(printf 'https://m.example.test/a\rb')" "$t/s/headers.sh" 2>"$t/err" >/dev/null)
[ "$(cat "$t/err")" = "$NOTE" ] || fail "CR URL printed: $(cat "$t/err")"
(cd / && env -i HOME="$t/home" PATH=/usr/bin:/bin CLAUDE_CODE_MCP_SERVER_URL='https://m.example.test/a b' "$t/s/headers.sh" 2>"$t/err" >/dev/null)
[ "$(cat "$t/err")" = "$NOTE" ] || fail "space URL printed: $(cat "$t/err")"

stub 'exit 0'
[ "$(run)" = "$SENTINEL" ] || fail "empty helper: $(run)"
stub 'echo "{}"'
[ "$(run)" = "$SENTINEL" ] || fail "helper printing {}: $(run)"

stub 'echo "{\"Authorization\":\"Bearer mcp_sk_stub\"}"; echo "secret detail" >&2'
[ "$(run)" = '{"Authorization":"Bearer mcp_sk_stub"}' ] || fail "key not passed through unchanged: $(run)"
[ ! -s "$t/err" ] || fail "key path wrote to stderr: $(cat "$t/err")"

stub 'exit 0'; rm "$t/s/run-agent.sh"
[ "$(run)" = "$SENTINEL" ] || fail "missing run-agent.sh: $(run)"

# The server entries (UNI-768): both in the tilori plugin. Market:
# TILORI_MARKET_URL for a second home (UNI-751), else the plugin's URL
# setting, whose default is production's; this helper.
python3 - "$repo/plugins/tilori" <<'PY' || fail ".mcp.json or plugin.json shape"
import json, sys
root = sys.argv[1]
mcp = json.load(open(root + "/.mcp.json"))["mcpServers"]
assert list(mcp) == ["tilori", "market"], mcp
s = mcp["market"]
assert s["type"] == "http" and s["url"] == "${TILORI_MARKET_URL:-${user_config.market_url}}", s
assert s["headersHelper"] == "\"${CLAUDE_PLUGIN_ROOT}/scripts/market-headers.sh\"", s
assert "headers" not in s, s
t = mcp["tilori"]
assert t["url"] == "${TILORI_MCP_URL:-${user_config.tilori_url}}", t
assert t["headersHelper"] == "\"${CLAUDE_PLUGIN_ROOT}/scripts/headers.sh\"", t
uc = json.load(open(root + "/.claude-plugin/plugin.json"))["userConfig"]
assert list(uc) == ["tilori_url", "market_url"], uc
assert uc["tilori_url"]["default"] == "https://tilori.ai/mcp/tilori/v1", uc
m = uc["market_url"]["default"]
assert m.startswith("https://") and m.endswith("/mcp/v1"), uc
PY

# The real scripts and bundled CLI, in an empty HOME: no config, no key.
mkdir -m 700 "$t/home"
out=$(cd / && env -i HOME="$t/home" PATH=/usr/bin:/bin:"$(dirname "$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")")" \
  CLAUDE_CODE_MCP_SERVER_URL=https://example.invalid/mcp/v1 "$repo/plugins/tilori/scripts/market-headers.sh" 2>/dev/null) \
  || fail "real headers.sh exited non-zero"
[ "$out" = "$SENTINEL" ] || fail "real headers.sh with no key: $out"

# The real scripts and bundled CLI with a configured agent (Bastion
# 163fc9b5): the key goes only to the Market URL that init recorded.
cfg="$t/home2/.config/tilori"
mkdir -p "$cfg/agents"; chmod 700 "$t/home2" "$t/home2/.config" "$cfg" "$cfg/agents"
cat > "$cfg/config.json" <<JSON
{
  "url": "https://tilori.example.test/mcp/tilori/v1",
  "market_url": "https://market.example.test/mcp/v1",
  "default_agent": "probe"
}
JSON
chmod 600 "$cfg/config.json"
printf '%s\n' mcp_sk_market_headers_probe_dummy > "$cfg/agents/probe.key"; chmod 600 "$cfg/agents/probe.key"
real() { # server URL
  (cd / && env -i HOME="$t/home2" PATH=/usr/bin:/bin:"$(dirname "$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")")" \
    CLAUDE_CODE_MCP_SERVER_URL="$1" "$repo/plugins/tilori/scripts/market-headers.sh" 2>/dev/null)
}
KEYED='{"Authorization":"Bearer mcp_sk_market_headers_probe_dummy"}'
out=$(real https://market.example.test/mcp/v1) || fail "real headers.sh exited non-zero"
[ "$out" = "$KEYED" ] || fail "market_url did not get the key: $out"
[ "$(real https://evil.example.test/mcp/v1)" = "$SENTINEL" ] || fail "another host on /mcp/v1 got: $(real https://evil.example.test/mcp/v1)"
[ "$(real https://market.example.test/mcp/v2)" = "$SENTINEL" ] || fail "another path got the key"
python3 - "$cfg/config.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); del c["market_url"]
open(p, "w").write(json.dumps(c, indent=2) + "\n")
PY
[ "$(real https://market.example.test/mcp/v1)" = "$SENTINEL" ] || fail "market_url unset still got: $(real https://market.example.test/mcp/v1)"
echo "market-headers: ok"
