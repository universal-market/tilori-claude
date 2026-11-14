#!/bin/sh
# headers.sh (the MCP headersHelper) never prints nothing (UNI-693): on any
# failure it prints the fixed placeholder, so Claude Code never falls back to
# OAuth and marks the server "needs authentication" for every session. A key
# from run-agent.sh passes through unchanged, and its stderr never shows.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
SENTINEL='{"Authorization":"Bearer tilori-no-agent-key"}'

# A copy of headers.sh next to a stub run-agent.sh.
stub() { # body of the stub
  rm -rf "$t/s"; mkdir -p "$t/s"; cp "$repo/plugins/universal-market/scripts/headers.sh" "$t/s/"
  printf '#!/bin/sh\n%s\n' "$1" > "$t/s/run-agent.sh"; chmod +x "$t/s/headers.sh" "$t/s/run-agent.sh"
}
run() { (cd / && env -i HOME="$t/home" PATH=/usr/bin:/bin "$t/s/headers.sh" 2>"$t/err"); }
NOTE='tilori: no agent key for this session, so the Tilori MCP stays disconnected (see the plugin README, "No agent key")'

stub 'echo "secret detail" >&2; exit 1'
out=$(run) || fail "failing helper exited non-zero"
[ "$out" = "$SENTINEL" ] || fail "failing helper: $out"
# stderr is the fixed note only: never run-agent's own stderr.
[ "$(cat "$t/err")" = "$NOTE" ] || fail "failing helper stderr: $(cat "$t/err")"

stub 'exit 0'
[ "$(run)" = "$SENTINEL" ] || fail "empty helper: $(run)"

# `{}` (no Authorization) still poisons the cache, so it gets the placeholder too.
stub 'echo "{}"'
[ "$(run)" = "$SENTINEL" ] || fail "helper printing {}: $(run)"

stub 'echo "{\"Authorization\":\"Bearer mcp_sk_stub\"}"; echo "secret detail" >&2'
[ "$(run)" = '{"Authorization":"Bearer mcp_sk_stub"}' ] || fail "key not passed through unchanged: $(run)"
[ ! -s "$t/err" ] || fail "key path wrote to stderr: $(cat "$t/err")"

stub 'exit 0'; rm "$t/s/run-agent.sh"
[ "$(run)" = "$SENTINEL" ] || fail "missing run-agent.sh: $(run)"

# The real scripts and bundled CLI, in an empty HOME: no config, no key.
mkdir -m 700 "$t/home"
out=$(cd / && env -i HOME="$t/home" PATH=/usr/bin:/bin:"$(dirname "$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")")" \
  CLAUDE_CODE_MCP_SERVER_URL=https://example.invalid/mcp/tilori/v1 "$repo/plugins/universal-market/scripts/headers.sh" 2>/dev/null) \
  || fail "real headers.sh exited non-zero"
[ "$out" = "$SENTINEL" ] || fail "real headers.sh with no key: $out"
echo "headers-sentinel: ok"
