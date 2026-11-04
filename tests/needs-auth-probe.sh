#!/bin/sh
# UNI-693 probe: Claude Code with the plugin's real headers.sh, no agent key,
# against a local fake MCP server that does OAuth like Tilori, in a throwaway
# HOME. Without the placeholder header, `claude mcp list` reports "Needs
# authentication" and writes ~/.claude/mcp-needs-auth-cache.json, which marks
# the server for every session on the machine. With it, there is no OAuth
# discovery and no cache entry. Needs Claude Code and python3; no network
# beyond 127.0.0.1, and nothing outside the temp HOME is touched.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
CLAUDE="${CLAUDE:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
[ -x "$CLAUDE" ] || { echo "needs-auth-probe: skip (no claude)"; exit 0; }
t=$(mktemp -d); pid=
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; [ -f "$t/out" ] && cat "$t/out" >&2; exit 1; }
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -I "$repo/tests/needs-auth-probe/fake_oauth_server.py" "$port" "$t/requests" & pid=$!
i=0; until python3 -c "import socket,sys; socket.create_connection(('127.0.0.1',$port),1)" 2>/dev/null; do
  i=$((i + 1)); [ $i -lt 50 ] || fail "fake server did not start"; sleep 0.1
done
mkdir -m 700 "$t/home"; mkdir "$t/proj"
printf '{"mcpServers":{"tilori":{"type":"http","url":"http://127.0.0.1:%s/mcp/tilori/v1","headersHelper":"%s"}}}\n' \
  "$port" "$repo/plugins/tilori/scripts/headers.sh" > "$t/home/.claude.json"
: > "$t/requests"
(cd "$t/proj" && env -i HOME="$t/home" PATH=/usr/bin:/bin:"$(dirname "$CLAUDE")" timeout 90 "$CLAUDE" mcp list > "$t/out" 2>&1) || true
grep -q 'tilori:' "$t/out" || fail "claude mcp list did not report the server"
if grep -qi 'needs authentication' "$t/out"; then fail "server marked as needing authentication"; fi
cache="$t/home/.claude/mcp-needs-auth-cache.json"
if [ -e "$cache" ] && grep -q '"tilori"' "$cache"; then fail "mcp-needs-auth-cache.json has a tilori entry"; fi
if grep -q '"p": "/.well-known/' "$t/requests"; then fail "OAuth discovery was attempted"; fi
grep -q '"auth": "Bearer tilori-no-agent-key"' "$t/requests" || fail "the placeholder header was not sent"
echo "needs-auth-probe: ok"
