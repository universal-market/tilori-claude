#!/bin/sh
# Tests scripts/stop-check.sh (the Stop hook and the PostToolUse hook on
# ask_owner) against a stub CLI that records its argv and stdin: it starts
# tilori-agent only when config.json has "owner_decision_check" set to true,
# passes stdin and stdout through, always exits 0, ignores unknown modes and
# a symlinked config.json, and runs nothing from a hostile cwd or "." PATH.
set -eu
cd "$(dirname "$0")/.."
hook="$PWD/plugins/universal-market/scripts/stop-check.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
chmod 700 "$t"
fail() { echo "stop-check-hook: FAIL: $1" >&2; exit 1; }
stub="$t/tilori-agent"
log="$t/argv"
cat >"$stub" <<STUB
#!/bin/sh
printf '%s\n' "cwd=\$PWD" "\$@" >"$log"
cat >"$t/stdin"
printf '{"decision":"block","reason":"r"}\n'
exit 2
STUB
chmod +x "$stub"
p="$t/project"
mkdir -p "$p" "$t/home/.config/tilori"
for c in sed printf cat sh dirname readlink pwd test ls; do
  printf '#!/bin/sh\necho EVIL >"%s/evil"\n' "$t" >"$p/$c"
  chmod +x "$p/$c"
done
cfg="$t/home/.config/tilori/config.json"
run() { # run <mode>: prints stdout; the exit code must be 0
  rm -f "$log" "$t/stdin"
  out=$(printf '{"stop_hook_active":false}' |
    (cd "$p" && env -i HOME="$t/home" PATH=".:/usr/bin:/bin" TILORI_AGENT_BIN="$stub" /bin/sh "$hook" "$@")) ||
    fail "exited non-zero for: $*"
  printf '%s' "$out"
}

# No config, or the key off: nothing runs.
[ -z "$(run hook)" ] && [ ! -e "$log" ] || fail "ran with no config"
printf '{\n  "agents": {\n    "wren": {\n      "owner_decision_check": false\n    }\n  }\n}\n' >"$cfg"
[ -z "$(run hook)" ] && [ ! -e "$log" ] || fail "ran with the check off"

# On: runs stop-check --hook from /, stdin and stdout passed through, exit 0
# even though the CLI exited 2.
printf '{\n  "agents": {\n    "wren": {\n      "owner_decision_check": true\n    }\n  }\n}\n' >"$cfg"
[ "$(run hook)" = '{"decision":"block","reason":"r"}' ] || fail "hook output"
[ "$(tr '\n' ' ' <"$log")" = "cwd=/ stop-check --hook " ] || fail "hook argv: $(cat "$log")"
[ "$(cat "$t/stdin")" = '{"stop_hook_active":false}' ] || fail "stdin not passed"
run asked >/dev/null
[ "$(tr '\n' ' ' <"$log")" = "cwd=/ stop-check --asked " ] || fail "asked argv: $(cat "$log")"

# Unknown modes run nothing.
for bad in "" other --hook HOOK; do
  [ -z "$(run $bad)" ] && [ ! -e "$log" ] || fail "ran for mode: $bad"
done

# A symlinked config.json is not read.
mv "$cfg" "$t/real.json"
ln -s "$t/real.json" "$cfg"
[ -z "$(run hook)" ] && [ ! -e "$log" ] || fail "followed a symlinked config"

[ ! -e "$t/evil" ] || fail "ran a command from the project directory"
echo "stop-check-hook: ok"
