#!/bin/sh
# Tests scripts/prompt-signal.sh (the PostToolUse / Notification hook) under
# a temp HOME: it touches only <run dir>/{activity,blocked}-<agent>, never
# reads stdin, never creates the run dir, ignores bad handles, symlinks and
# wide dirs, prints nothing, always exits 0, and runs no command from a
# hostile cwd or a "." PATH entry.
set -eu
cd "$(dirname "$0")/.."
hook="$PWD/plugins/universal-market/scripts/prompt-signal.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
chmod 700 "$t"
fail() { echo "prompt-signal: FAIL: $1" >&2; exit 1; }
marker=PROMPT_SIGNAL_STDIN_MARKER_7f3a
run() { # run <kind> [env...]: stdin carries the marker, like a real payload
  kind=$1; shift
  out=$(printf '{"tool_input":"%s","message":"%s"}\n' "$marker" "$marker" |
    env -i PATH=/usr/bin:/bin HOME="$t/home" "$@" sh "$hook" "$kind" 2>&1) || fail "$kind exited non-zero"
  [ -z "$out" ] || fail "$kind printed: $out"
}
mkdir -p "$t/home" "$t/xdg"
run_dir="$t/xdg/tilori"

# No run dir: nothing created, not even the dir.
run activity TILORI_AGENT=wren XDG_RUNTIME_DIR="$t/xdg"
[ ! -e "$run_dir" ] || fail "created the run dir"

mkdir -m 700 "$run_dir"
run activity TILORI_AGENT=wren XDG_RUNTIME_DIR="$t/xdg"
[ -f "$run_dir/activity-wren" ] || fail "activity not touched"
run blocked TILORI_AGENT=wren XDG_RUNTIME_DIR="$t/xdg"
[ -f "$run_dir/blocked-wren" ] || fail "blocked not touched"
[ -s "$run_dir/blocked-wren" ] && fail "file not empty"

# Touching an existing file moves its mtime forward.
touch -d '2026-01-01 00:00:00' "$run_dir/activity-wren"
run activity TILORI_AGENT=wren XDG_RUNTIME_DIR="$t/xdg"
[ "$run_dir/activity-wren" -nt "$run_dir/blocked-wren" ] || fail "mtime not updated"

# Unknown kinds do nothing.
run other TILORI_AGENT=wren XDG_RUNTIME_DIR="$t/xdg"
[ ! -e "$run_dir/other-wren" ] || fail "unknown kind touched a file"

# The handle: invalid ones never reach a path.
for bad in '../x' 'a/b' 'Wren' '-x' '_x' '' 'a b' "$(printf 'x%.0s' $(seq 65))"; do
  run activity TILORI_AGENT="$bad" XDG_RUNTIME_DIR="$t/xdg"
done
[ "$(ls "$run_dir" | wc -l)" -eq 2 ] || fail "a bad handle touched something: $(ls "$run_dir")"
[ ! -e "$t/xdg/x" ] || fail "path escaped the run dir"

# default_agent from config.json, pretty or compact; TILORI_AGENT wins.
mkdir -p "$t/home/.config/tilori"
printf '{\n  "url": "https://x.invalid/mcp",\n  "default_agent": "pax",\n  "agents": {}\n}\n' > "$t/home/.config/tilori/config.json"
run activity XDG_RUNTIME_DIR="$t/xdg"
[ -f "$run_dir/activity-pax" ] || fail "default_agent (pretty) not used"
printf '{"default_agent":"juniper","url":"x"}' > "$t/home/.config/tilori/config.json"
run blocked XDG_RUNTIME_DIR="$t/xdg"
[ -f "$run_dir/blocked-juniper" ] || fail "default_agent (compact) not used"
rm "$run_dir/blocked-wren"
run blocked TILORI_AGENT=wren XDG_RUNTIME_DIR="$t/xdg"
[ -f "$run_dir/blocked-wren" ] || fail "TILORI_AGENT did not win over default_agent"
printf '{"default_agent":"../../evil"}' > "$t/home/.config/tilori/config.json"
run activity XDG_RUNTIME_DIR="$t/xdg"
[ "$(ls "$run_dir" | wc -l)" -eq 4 ] || fail "a bad default_agent touched something"

# The run dir as tilori-agent finds it: TILORI_SOCKET's dir, then XDG, then
# $TILORI_HOME/run (or ~/.config/tilori/run).
mkdir -m 700 "$t/sock" "$t/home/.config/tilori/run"
run activity TILORI_AGENT=wren TILORI_SOCKET="$t/sock/router.sock" XDG_RUNTIME_DIR="$t/xdg"
[ -f "$t/sock/activity-wren" ] || fail "TILORI_SOCKET dir not used"
run activity TILORI_AGENT=wren
[ -f "$t/home/.config/tilori/run/activity-wren" ] || fail "~/.config/tilori/run not used"
run activity TILORI_AGENT=wren TILORI_SOCKET=relative/router.sock
[ ! -e relative ] || fail "relative dir used"

# A second home (UNI-751) has its own run dir, even with XDG set; the default
# home named through TILORI_HOME (directly or via a symlink) keeps XDG's.
mkdir -m 700 "$t/prod" "$t/prod/run"
rm -f "$run_dir/activity-wren"
run activity TILORI_AGENT=wren TILORI_HOME="$t/prod" XDG_RUNTIME_DIR="$t/xdg"
[ -f "$t/prod/run/activity-wren" ] || fail "other home's run dir not used"
[ ! -e "$run_dir/activity-wren" ] || fail "other home touched the shared XDG run dir"
run activity TILORI_AGENT=wren TILORI_HOME="$t/home/.config/tilori" XDG_RUNTIME_DIR="$t/xdg"
[ -f "$run_dir/activity-wren" ] || fail "default home via TILORI_HOME did not keep XDG"
rm "$run_dir/activity-wren"
ln -s "$t/home/.config/tilori" "$t/default-alias"
run activity TILORI_AGENT=wren TILORI_HOME="$t/default-alias" XDG_RUNTIME_DIR="$t/xdg"
[ -f "$run_dir/activity-wren" ] || fail "default home via a symlink did not keep XDG"

# A wide dir, a symlinked dir and a symlinked file are left alone.
mkdir -m 755 "$t/wide" && mkdir "$t/wide/tilori" && chmod 755 "$t/wide/tilori"
run activity TILORI_AGENT=wren XDG_RUNTIME_DIR="$t/wide"
[ ! -e "$t/wide/tilori/activity-wren" ] || fail "touched in a non-0700 dir"
mkdir -m 700 "$t/real" "$t/link"
ln -s "$t/real" "$t/link/tilori"
run activity TILORI_AGENT=wren XDG_RUNTIME_DIR="$t/link"
[ ! -e "$t/real/activity-wren" ] || fail "followed a symlinked run dir"
: > "$t/target"; touch -d '2026-01-01 00:00:00' "$t/target"
ln -s "$t/target" "$run_dir/blocked-pax"
run blocked TILORI_AGENT=pax XDG_RUNTIME_DIR="$t/xdg"
[ "$t/target" -nt "$run_dir/activity-wren" ] && fail "followed a symlinked file"

# stdin is never read: the marker appears nowhere.
grep -rq "$marker" "$t" && fail "stdin content reached a file"

# Hostile cwd and a "." PATH entry: no command from the project runs.
mkdir -p "$t/proj"
for n in ls touch cat sh date stat; do
  printf '#!/bin/sh\n: > "%s/ran-%s"\n' "$t" "$n" > "$t/proj/$n"; chmod +x "$t/proj/$n"
done
(cd "$t/proj" && printf '%s' "$marker" |
  env -i PATH=.:/usr/bin:/bin HOME="$t/home" TILORI_AGENT=wren XDG_RUNTIME_DIR="$t/xdg" /bin/sh "$hook" activity) ||
  fail "hostile cwd: non-zero exit"
for n in ls touch cat sh date stat; do [ ! -e "$t/ran-$n" ] || fail "hostile cwd: ./$n ran"; done

echo "prompt-signal: ok"
