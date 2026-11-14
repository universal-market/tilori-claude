#!/bin/sh
# /universal-market:setup (UNI-771): setup.sh checks the handle against Tilori's rule
# before anything runs and passes it to `tilori-agent setup` as one argv
# entry; anything else exits 2 without running the CLI. The command text
# keeps its safety lines.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# setup.sh next to a stub run-agent.sh that prints each argument on a line.
mkdir -p "$t/s"
cp "$repo/plugins/universal-market/scripts/setup.sh" "$t/s/"
printf '#!/bin/sh\necho "cwd=$(pwd)"\nfor a in "$@"; do printf "[%%s]\\n" "$a"; done\n' >"$t/s/run-agent.sh"
chmod +x "$t/s/setup.sh" "$t/s/run-agent.sh"
mkdir -p "$t/proj"
run() { (cd "$t/proj" && env -i HOME="$t" PATH=/usr/bin:/bin LANG=en_US.UTF-8 "$t/s/setup.sh" "$@" >"$t/out" 2>"$t/err"); }

for h in ab a1 my-agent claude-code-vm 0x a-b-c abcdefghijklmnopqrstuvwx; do
  run "$h" || fail "'$h' refused: $(cat "$t/err")"
  [ "$(cat "$t/out")" = "cwd=/
[setup]
[$h]" ] || fail "'$h': $(cat "$t/out")"
done
run || fail "bare: refused"
[ "$(cat "$t/out")" = "cwd=/
[setup]" ] || fail "bare: $(cat "$t/out")"

for h in a abcdefghijklmnopqrstuvwxy -ab ab- a--b Ab AB 'a b' 'a;b' 'a&&b' '$(id)' '`id`' 'a/b' '../x' 'a.b' 'a_b' "$(printf 'a\nb')" "$(printf 'ab\t')" 'é1' 'aé' '' '--help' "ab'cd" 'ab"cd' 'a|b' 'a>b' '*' '?b'; do
  if run "$h"; then fail "'$h' accepted"; fi
  [ ! -s "$t/out" ] || fail "'$h': the CLI ran: $(cat "$t/out")"
  grep -q '^usage: /universal-market:setup \[<handle>\]$' "$t/err" || fail "'$h': no usage: $(cat "$t/err")"
done
if run ab cd; then fail "two handles accepted"; fi
[ ! -s "$t/out" ] || fail "two handles: the CLI ran"


# --url (UNI-818): the key from TILORI_API_KEY goes to `connect` on stdin
# only, never argv, and the CLI's environment no longer has the variable.
# The address is one argv entry of URL characters; never --replace.
printf '#!/bin/sh\necho "cwd=$(pwd)"\nfor a in "$@"; do printf "[%%s]\\n" "$a"; done\necho "env=${TILORI_API_KEY-unset}"\necho "stdin=$(cat)"\n' >"$t/s/run-agent.sh"
K='mcp_sk_test-Ab_9'
runk() { (cd "$t/proj" && env -i HOME="$t" PATH=/usr/bin:/bin LANG=en_US.UTF-8 TILORI_API_KEY="$K" "$t/s/setup.sh" "$@" </dev/null >"$t/out" 2>"$t/err"); }
for u in https://workspaces.example.com/mcp/tilori/v1 http://127.0.0.1:3211/mcp/tilori/v1 'https://x.example/a%2Fb/~c_d-e'; do
  runk --url "$u" || fail "--url '$u' refused: $(cat "$t/err")"
  [ "$(cat "$t/out")" = "cwd=/
[connect]
[--url]
[$u]
env=unset
stdin=$K" ] || fail "--url '$u': $(cat "$t/out")"
done
for u in '' example.com ftp://x.example 'https://' 'https://x.example/?a=b' 'https://x.example/a&b' "https://x.example/'a" 'https://x.example/a b' 'https://x.example/$(id)' 'https://x.example/`id`' 'https://x.example/;id' "$(printf 'https://x.example/\nb')" 'https://é.example' '--replace'; do
  if runk --url "$u"; then fail "--url '$u' accepted"; fi
  [ ! -s "$t/out" ] || fail "--url '$u': the CLI ran: $(cat "$t/out")"
  grep -q '^       /universal-market:setup --url ' "$t/err" || fail "--url '$u': no usage: $(cat "$t/err")"
done
for extra in '--replace' 'x'; do
  if runk --url https://x.example/mcp/tilori/v1 "$extra"; then fail "--url with '$extra' accepted"; fi
  [ ! -s "$t/out" ] || fail "--url with '$extra': the CLI ran"
done
if runk --url; then fail "--url without an address accepted"; fi
[ ! -s "$t/out" ] || fail "--url alone: the CLI ran"
# No key exported: exit 2 with the panel line, nothing run.
for k in unset empty; do
  if [ $k = unset ]; then
    (cd "$t/proj" && env -i HOME="$t" PATH=/usr/bin:/bin "$t/s/setup.sh" --url https://x.example/mcp/tilori/v1 >"$t/out" 2>"$t/err") && fail "no key ($k) accepted"
  else
    (cd "$t/proj" && env -i HOME="$t" PATH=/usr/bin:/bin TILORI_API_KEY= "$t/s/setup.sh" --url https://x.example/mcp/tilori/v1 >"$t/out" 2>"$t/err") && fail "no key ($k) accepted"
  fi
  [ ! -s "$t/out" ] || fail "no key ($k): the CLI ran"
  grep -qF 'Export TILORI_API_KEY in your terminal (the first line in the Connect panel)' "$t/err" || fail "no key ($k): $(cat "$t/err")"
done
# Without --url, the key in the environment changes nothing: setup runs as before.
runk ab || fail "handle with a key exported refused"
grep -qx '\[setup\]' "$t/out" || fail "handle with a key: $(cat "$t/out")"

# The command text: the same rule, the script by its plugin path, and the
# safety lines a session needs (no key in chat, no fetching the link, only
# when the user typed it).
cmd="$repo/plugins/universal-market/commands/setup.md"
for line in \
  'argument-hint: "[<handle>] | --url <address>"' \
  'disable-model-invocation: true' \
  'sh "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" --url' \
  'never add `--replace`' \
  "never put the key, or" \
  "Don't run that command yourself" \
  'sh "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"' \
  "2 to 24" \
  "Don't open it, fetch it or" \
  "never" \
  "ask the user to paste a key" \
  "only when your user typed" \
  'run `/mcp` and reconnect'; do
  grep -qF -- "$line" "$cmd" || fail "commands/setup.md lacks: $line"
done
# The session-start note points at the command, not a terminal init.
grep -q 'tell them to run /universal-market:setup in this session' "$repo/plugins/universal-market/scripts/session-start.sh" \
  || fail "session-start.sh doesn't point at /universal-market:setup"
echo "setup-command: ok"
