#!/bin/sh
# /tilori:setup (UNI-771): setup.sh checks the handle against Tilori's rule
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
cp "$repo/plugins/tilori/scripts/setup.sh" "$t/s/"
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
  grep -q '^usage: /tilori:setup \[<handle>\]$' "$t/err" || fail "'$h': no usage: $(cat "$t/err")"
done
if run ab cd; then fail "two handles accepted"; fi
[ ! -s "$t/out" ] || fail "two handles: the CLI ran"


# The command text: the same rule, the script by its plugin path, and the
# safety lines a session needs (no key in chat, no fetching the link, only
# when the user typed it).
cmd="$repo/plugins/tilori/commands/setup.md"
for line in \
  'argument-hint: "[<handle>]"' \
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
grep -q 'tell them to run /tilori:setup in this session' "$repo/plugins/tilori/scripts/session-start.sh" \
  || fail "session-start.sh doesn't point at /tilori:setup"
echo "setup-command: ok"
