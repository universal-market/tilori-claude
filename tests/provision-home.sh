#!/bin/sh
# live-demo/provision.ts takes only a fresh demo home (UNI-457): an --home with
# config.json or agents/ in it (a dangling symlink counts), or reached through
# a symlink, is refused before any request; a fresh one gets past the check
# and then fails to reach the closed port, writing nothing.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
bun=$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")
[ -x "$bun" ] || { echo "skip: bun not installed"; exit 0; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
u=http://127.0.0.1:9
run() { (cd / && "$bun" "$repo/tests/live-demo/provision.ts" --market $u --convex $u --site $u --home "$1" --agent alice:wren 2>&1) && fail "$1: provision succeeded"; :; }

mkdir -p "$t/with-config" "$t/with-agents/agents" "$t/fresh"
printf '{"url":"keep"}\n' > "$t/with-config/config.json"
ln -s "$t/with-config" "$t/link"
mkdir -p "$t/dangling" && ln -s "$t/nowhere/config.json" "$t/dangling/config.json"
for h in "$t/with-config" "$t/with-agents" "$t/link" "$t/dangling"; do
  out=$(run "$h")
  case "$out" in *"Refusing --home"*) ;; *) fail "$h not refused: $out" ;; esac
done
[ "$(cat "$t/with-config/config.json")" = '{"url":"keep"}' ] || fail "existing config.json changed"
out=$(run "$t/fresh")
case "$out" in *"Refusing --home"*) fail "fresh home refused: $out" ;; esac
# It must have got as far as signing in (the closed port), not died earlier.
case "$out" in *"Unable to connect"*|*ECONNREFUSED*|*ConnectionRefused*) ;; *) fail "fresh home failed before sign-in: $out" ;; esac
[ -z "$(ls -A "$t/fresh")" ] || fail "fresh home written before sign-in"
echo "provision-home: ok"
