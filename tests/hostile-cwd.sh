#!/bin/sh
# Runs the plugin's launcher from a hostile project directory and checks that
# nothing in that directory influences it:
#   - bunfig.toml with a `preload` script (would run code inside Bun),
#   - .env setting TILORI_* variables,
#   - ./bun, ./tilori-agent, ./dirname and ./readlink picked up through "."
#     or an empty PATH entry (no external command may run before cd /).
# A fake tilori-agent (src/cli.ts) reports the cwd and TILORI_EVIL it sees.
# Includes a negative control proving the hostile files do work on plain Bun.
# The first part runs a copy of the scripts without vendor/ (the install-based
# fallback); then a fake bundle in vendor/ (precedence); then the real
# bundled CLI in plugins/tilori/vendor.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
realbun=$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")
[ -x "$realbun" ] || { echo "skip: bun not installed"; exit 0; }

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
plugin="$t/plugin"; mkdir -p "$plugin"
cp -R "$repo/plugins/tilori/scripts" "$plugin/scripts"
scripts="$plugin/scripts"
run="$scripts/run-agent.sh"
h="$t/home"; p="$t/project"; m="$t/markers"
mkdir -p "$h/.bun/bin" "$h/pkg/src" "$p" "$m"
ln -s "$realbun" "$h/.bun/bin/bun"
cat > "$h/pkg/src/cli.ts" <<'TS'
#!/usr/bin/env bun
console.log(`cwd=${process.cwd()} evil=${process.env.TILORI_EVIL ?? 'unset'} args=${process.argv.slice(2).join(',')}`);
TS
chmod +x "$h/pkg/src/cli.ts"
ln -s ../../pkg/src/cli.ts "$h/.bun/bin/tilori-agent"

printf 'preload = ["./evil.ts"]\n' > "$p/bunfig.toml"
printf 'require("fs").writeFileSync(%s, "x");\n' "\"$m/preload\"" > "$p/evil.ts"
printf 'TILORI_EVIL=1\nTILORI_HOME=%s\n' "$p" > "$p/.env"
hostile="bun tilori-agent dirname readlink"
for n in $hostile; do
  printf '#!/bin/sh\ntouch "%s/%s"\necho hijacked\n' "$m" "$n" > "$p/$n"; chmod +x "$p/$n"
done

fail() { echo "FAIL: $*" >&2; exit 1; }
no_markers() { for f in preload $hostile; do [ -e "$m/$f" ] && fail "$1: hostile $f ran"; done; :; }

# Negative control: plain Bun from the project dir honours both files.
(cd "$p" && "$realbun" "$h/pkg/src/cli.ts" >/dev/null 2>&1) || true
[ -e "$m/preload" ] || fail "control: bunfig preload did not run (test is not meaningful)"
out=$(cd "$p" && "$realbun" "$h/pkg/src/cli.ts" 2>/dev/null) || true
case "$out" in *evil=1*) ;; *) fail "control: .env not loaded (test is not meaningful): $out" ;; esac
rm -f "$m/preload"

sys=/usr/bin:/bin
for path in ".:$sys" ":$sys" "$sys:" "$sys::/nonexistent" "$sys"; do
  out=$(cd "$p" && env -i HOME="$h" PATH="$path" sh "$run" headers --x 2>&1) || fail "PATH=$path: exit $? ($out)"
  [ "$out" = "cwd=/ evil=unset args=headers,--x" ] || fail "PATH=$path: unexpected output: $out"
  no_markers "PATH=$path"
done

# The entry scripts Claude Code runs (by absolute path, not via sh), and
# run-agent.sh by a relative path from the project directory, with PATH
# starting with "." or an empty entry.
rel=$(printf '%s' "$p" | sed 's|[^/][^/]*|..|g'); rel="${rel#/}$scripts"
for path in ".:$sys" ":$sys"; do
  for s in headers.sh session-start.sh; do
    out=$(cd "$p" && env -i HOME="$h" PATH="$path" "$scripts/$s" 2>&1) || fail "$s, PATH=$path: exit $? ($out)"
    case "$s" in
      headers.sh) want="cwd=/ evil=unset args=headers" ;;
      session-start.sh) want="cwd=/ evil=unset args=policy,--hook" ;;
    esac
    [ "$out" = "$want" ] || fail "$s, PATH=$path: unexpected output: $out"
    no_markers "$s, PATH=$path"
  done
  out=$(cd "$p" && env -i HOME="$h" PATH="$path" "$scripts/monitor.sh" 2>&1) || fail "monitor.sh, PATH=$path: exit $? ($out)"
  [ "$out" = "cwd=/ evil=unset args=watch,--notify-lines" ] || fail "monitor.sh, PATH=$path: unexpected output: $out"
  no_markers "monitor.sh, PATH=$path"
  out=$(cd "$p" && env -i HOME="$h" PATH="$path" "$rel/run-agent.sh" r 2>&1) || fail "relative \$0, PATH=$path: exit $? ($out)"
  [ "$out" = "cwd=/ evil=unset args=r" ] || fail "relative \$0, PATH=$path: unexpected output: $out"
  no_markers "relative \$0, PATH=$path"
done

# A relative TILORI_AGENT_BIN is ignored; an absolute one is used.
out=$(cd "$p" && env -i HOME="$h" PATH="$sys" TILORI_AGENT_BIN=./tilori-agent sh "$run" a 2>&1)
[ "$out" = "cwd=/ evil=unset args=a" ] || fail "relative TILORI_AGENT_BIN: $out"
out=$(cd "$p" && env -i HOME="$t/nohome" PATH="$sys" TILORI_AGENT_BIN="$h/pkg/src/cli.ts" BUN_INSTALL="$h/.bun" sh "$run" b 2>&1)
[ "$out" = "cwd=/ evil=unset args=b" ] || fail "absolute TILORI_AGENT_BIN: $out"
no_markers "TILORI_AGENT_BIN"

# The shebang path: a launcher that is not a .ts file is exec'd directly
# (newer tilori-agent ships a hardened shell launcher); still from /.
printf '#!/bin/sh\necho "launcher cwd=$(pwd) args=$*"\n' > "$h/pkg/launcher"; chmod +x "$h/pkg/launcher"
ln -sf ../../pkg/launcher "$h/.bun/bin/tilori-agent"
out=$(cd "$p" && env -i HOME="$h" PATH=".:$sys" sh "$run" c 2>&1)
[ "$out" = "launcher cwd=/ args=c" ] || fail "launcher: $out"

# A chain of relative symlinks to a .ts CLI, with a readlink that rejects -f
# (older macOS): it must still be recognised as .ts and run with bun --no-env-file.
mkdir -p "$t/a/b" "$t/shim"
ln -s "$h/pkg/src/cli.ts" "$t/a/b/real-link"
ln -s b/real-link "$t/a/hop"
ln -sf ../../../a/hop "$h/.bun/bin/tilori-agent"
r=$(command -v readlink)
printf '#!/bin/sh\ncase "$1" in -*) echo "readlink: illegal option" >&2; exit 1 ;; esac\nexec %s "$@"\n' "$r" > "$t/shim/readlink"
chmod +x "$t/shim/readlink"
out=$(cd "$p" && env -i HOME="$h" PATH="$t/shim:.:$sys" sh "$run" e 2>&1) \
  || fail "symlink chain without readlink -f: exit $? ($out)"
[ "$out" = "cwd=/ evil=unset args=e" ] || fail "symlink chain without readlink -f: $out"
no_markers "symlink chain"

# Missing CLI: exit 127, nothing on stdout.
rm "$h/.bun/bin/tilori-agent"
set +e; out=$(cd "$p" && env -i HOME="$h" PATH=".:$sys" sh "$run" d 2>/dev/null); rc=$?; set -e
[ "$rc" = 127 ] && [ -z "$out" ] || fail "missing CLI: rc=$rc out=$out"
no_markers "missing CLI"

# Bundled CLI (vendor/tilori-agent.js): preferred over PATH and ~/.bun, run
# with bun --no-env-file from /; an absolute TILORI_AGENT_BIN still wins.
ln -sf ../../pkg/src/cli.ts "$h/.bun/bin/tilori-agent"
mkdir -p "$plugin/vendor"
cat > "$plugin/vendor/tilori-agent.js" <<'JS'
console.log(`bundle cwd=${process.cwd()} evil=${process.env.TILORI_EVIL ?? 'unset'} args=${process.argv.slice(2).join(',')}`);
JS
for path in ".:$sys" ":$sys" "$sys"; do
  out=$(cd "$p" && env -i HOME="$h" PATH="$path" "$scripts/headers.sh" 2>&1) || fail "bundle headers.sh, PATH=$path: exit $? ($out)"
  [ "$out" = "bundle cwd=/ evil=unset args=headers" ] || fail "bundle headers.sh, PATH=$path: $out"
  out=$(cd "$p" && env -i HOME="$h" PATH="$path" "$scripts/monitor.sh" 2>&1) || fail "bundle monitor.sh, PATH=$path: exit $? ($out)"
  [ "$out" = "bundle cwd=/ evil=unset args=watch,--notify-lines" ] || fail "bundle monitor.sh, PATH=$path: $out"
  out=$(cd "$p" && env -i HOME="$h" PATH="$path" "$rel/run-agent.sh" f 2>&1) || fail "bundle relative \$0, PATH=$path: exit $? ($out)"
  [ "$out" = "bundle cwd=/ evil=unset args=f" ] || fail "bundle relative \$0, PATH=$path: $out"
  no_markers "bundle, PATH=$path"
done
out=$(cd "$p" && env -i HOME="$h" PATH="$sys" TILORI_AGENT_BIN="$h/pkg/src/cli.ts" sh "$run" g 2>&1)
[ "$out" = "cwd=/ evil=unset args=g" ] || fail "TILORI_AGENT_BIN over bundle: $out"
out=$(cd "$p" && env -i HOME="$h" PATH="$sys" TILORI_AGENT_BIN=./tilori-agent sh "$run" h 2>&1)
[ "$out" = "bundle cwd=/ evil=unset args=h" ] || fail "relative TILORI_AGENT_BIN over bundle: $out"
no_markers "bundle precedence"

# No agent configured (policy prints nothing): session-start gives a setup
# hint naming this plugin's run-agent.sh, as valid JSON.
printf '\n' > "$plugin/vendor/tilori-agent.js"
out=$(cd "$p" && env -i HOME="$h" PATH=".:$sys" "$scripts/session-start.sh" 2>&1) || fail "hint: exit $?"
printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' || fail "hint is not JSON: $out"
case "$out" in *"sh $scripts/run-agent.sh init --agent"*) ;; *) fail "hint lacks the init command: $out" ;; esac
no_markers "hint"

# The real bundled CLI from a hostile directory. The project's .env points
# TILORI_HOME at a config naming agent "evilagent"; the control shows plain
# Bun from the project picks it up, and the plugin's path must not.
bundle="$repo/plugins/tilori/vendor/tilori-agent.js"
[ -f "$bundle" ] || fail "missing $bundle"
chmod 700 "$p"
printf '{"default_agent":"evilagent"}\n' > "$p/config.json"; chmod 600 "$p/config.json"
out=$(cd "$p" && env -i HOME="$h" PATH="$sys" "$realbun" "$bundle" policy 2>&1) || true
case "$out" in *evilagent*) ;; *) fail "control: real bundle did not read the project .env (test is not meaningful): $out" ;; esac
rm -f "$m/preload"
out=$(cd "$p" && env -i HOME="$h" PATH=".:$sys" sh "$repo/plugins/tilori/scripts/run-agent.sh" help 2>&1) || fail "real bundle help: exit $? ($out)"
case "$out" in "tilori-agent: wake local coding agents"*) ;; *) fail "real bundle help: $out" ;; esac
no_markers "real bundle help"
out=$(cd "$p" && env -i HOME="$h" PATH=".:$sys" "$repo/plugins/tilori/scripts/session-start.sh" 2>&1) || fail "real bundle session-start: exit $?"
case "$out" in *evilagent*) fail "real bundle read the project .env: $out" ;; esac
case "$out" in *"run-agent.sh init --agent"*) ;; *) fail "real bundle session-start gave no setup hint: $out" ;; esac
no_markers "real bundle session-start"
echo "hostile-cwd: ok"
