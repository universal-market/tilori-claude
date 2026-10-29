#!/bin/sh
# Tests scripts/config.sh (/tilori:config) against a stub CLI that records
# its argv: valid input reaches `tilori-agent config` as separate arguments,
# anything else exits 2 without running the CLI, there is no --agent, and a
# hostile cwd or "." PATH entry runs nothing.
set -eu
cd "$(dirname "$0")/.."
script="$PWD/plugins/tilori/scripts/config.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
chmod 700 "$t"
fail() { echo "config-command: FAIL: $1" >&2; exit 1; }
stub="$t/tilori-agent"
log="$t/argv"
cat >"$stub" <<EOF
#!/bin/sh
printf '%s\n' "cwd=\$PWD" "\$@" >"$log"
EOF
chmod +x "$stub"
# A hostile project directory: every external command shadowed.
p="$t/project"
mkdir -p "$p"
for c in sed printf cat sh dirname readlink pwd test; do
  printf '#!/bin/sh\necho EVIL >"%s/evil"\n' "$t" >"$p/$c"
  chmod +x "$p/$c"
done
run() { # run <args...>: prints the exit code; the stub's argv lands in $log
  rm -f "$log"
  (cd "$p" && env -i HOME="$t" PATH=".:/usr/bin:/bin" TILORI_AGENT_BIN="$stub" /bin/sh "$script" "$@" 2>/dev/null) && echo 0 || echo $?
}
argv() { tr '\n' ' ' <"$log" | sed 's/ $//'; }

# Show.
[ "$(run)" = 0 ] || fail "bare show"
[ "$(argv)" = "cwd=/ config show" ] || fail "bare show argv: $(argv)"
[ "$(run show)" = 0 ] && [ "$(argv)" = "cwd=/ config show" ] || fail "show"

# Set, one or several, each its own argument.
[ "$(run wakes_per_hour=35)" = 0 ] || fail "set"
[ "$(argv)" = "cwd=/ config set wakes_per_hour=35" ] || fail "set argv: $(argv)"
[ "$(run wakes_per_hour=60 direct_wakes_per_hour=0 stall_minutes=1440 reminder.every_minutes=15)" = 0 ] || fail "set several"
[ "$(sed -n '$=' "$log")" = 7 ] || fail "set several: $(argv)"
[ "$(run wakes_per_hour=007)" = 0 ] || fail "leading zeros"

# Reset.
[ "$(run reset wakes_per_hour stall_minutes)" = 0 ] || fail "reset"
[ "$(argv)" = "cwd=/ config reset wakes_per_hour stall_minutes" ] || fail "reset argv: $(argv)"

# Refused before the CLI runs: exit 2, no argv recorded.
for bad in \
  "url=https://evil.example" "exec=1" "trusted_owners=1" "inbox=0" "direct_messages=1" \
  "wakes_per_hour=0" "wakes_per_hour=61" "direct_wakes_per_hour=31" "stall_minutes=1441" \
  "reminder.every_minutes=14" "reminder.every_minutes=1441" "wakes_per_hour=999999" \
  "wakes_per_hour=-1" "wakes_per_hour=3.5" "wakes_per_hour=1e2" "wakes_per_hour=" "wakes_per_hour" \
  "wakes_per_hour=35;id" 'wakes_per_hour=$(id)' "wakes_per_hour=35 x" "--agent" "--agent=pax" "set" "show extra"; do
  [ "$(run "$bad")" = 2 ] || fail "accepted: $bad"
  [ ! -e "$log" ] || fail "ran the CLI for: $bad"
done
[ "$(run --agent pax wakes_per_hour=35)" = 2 ] || fail "accepted --agent"
[ "$(run wakes_per_hour=35 url=x)" = 2 ] || fail "accepted a bad key after a good one"
[ ! -e "$log" ] || fail "partial run"
[ "$(run reset)" = 2 ] || fail "bare reset"
[ "$(run reset url)" = 2 ] || fail "reset url"
[ "$(run reset reminder.every_minutes)" = 2 ] || fail "reset reminder"
[ "$(run show wakes_per_hour=35)" = 2 ] || fail "show with args"
# Each refusal names what was wrong before the usage line.
reason() { (cd "$p" && env -i HOME="$t" PATH=".:/usr/bin:/bin" TILORI_AGENT_BIN="$stub" /bin/sh "$script" "$@" 2>&1 >/dev/null | head -1) || :; }
[ "$(reason wakes_per_hour=500)" = "tilori: wakes_per_hour=500 is out of range (1-60)" ] || fail "range reason: $(reason wakes_per_hour=500)"
[ "$(reason wakes_per_hour=999999)" = "tilori: wakes_per_hour=999999 is out of range (1-60)" ] || fail "long reason"
[ "$(reason stall_minutes=x)" = "tilori: stall_minutes needs a whole number (0-1440)" ] || fail "number reason: $(reason stall_minutes=x)"
[ "$(reason foo=1)" = "tilori: unknown key foo" ] || fail "key reason: $(reason foo=1)"
[ "$(reason reset foo)" = "tilori: unknown key foo" ] || fail "reset key reason"
[ "$(reason reset reminder.every_minutes)" = "tilori: reminder.every_minutes has no reset; turn the reminder off by hand" ] || fail "reminder reason"
[ "$(reason --agent)" = "tilori: expected key=<number>" ] || fail "shape reason: $(reason --agent)"
[ ! -e "$t/evil" ] || fail "ran a command from the project directory"
echo "config-command: ok"
