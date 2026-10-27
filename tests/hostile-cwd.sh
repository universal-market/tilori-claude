#!/bin/sh
# Runs the plugin's launcher from a hostile project directory and checks that
# nothing in that directory influences it:
#   - bunfig.toml with a `preload` script (would run code inside Bun),
#   - .env setting TILORI_* variables,
#   - ./bun and ./tilori-agent picked up through "." or an empty PATH entry.
# A fake tilori-agent (src/cli.ts) reports the cwd and TILORI_EVIL it sees.
# Includes a negative control proving the hostile files do work on plain Bun.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd -P)
run="$repo/plugins/tilori/scripts/run-agent.sh"
realbun=$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")
[ -x "$realbun" ] || { echo "skip: bun not installed"; exit 0; }

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
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
for n in bun tilori-agent; do
  printf '#!/bin/sh\ntouch "%s/%s"\necho hijacked\n' "$m" "$n" > "$p/$n"; chmod +x "$p/$n"
done

fail() { echo "FAIL: $*" >&2; exit 1; }

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
  for f in preload bun tilori-agent; do
    [ -e "$m/$f" ] && fail "PATH=$path: hostile $f ran"
  done
  : # ok
done

# A relative TILORI_AGENT_BIN is ignored; an absolute one is used.
out=$(cd "$p" && env -i HOME="$h" PATH="$sys" TILORI_AGENT_BIN=./tilori-agent sh "$run" a 2>&1)
[ "$out" = "cwd=/ evil=unset args=a" ] || fail "relative TILORI_AGENT_BIN: $out"
out=$(cd "$p" && env -i HOME="$t/nohome" PATH="$sys" TILORI_AGENT_BIN="$h/pkg/src/cli.ts" BUN_INSTALL="$h/.bun" sh "$run" b 2>&1)
[ "$out" = "cwd=/ evil=unset args=b" ] || fail "absolute TILORI_AGENT_BIN: $out"
[ -e "$m/tilori-agent" ] && fail "hostile tilori-agent ran"

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
for f in preload bun tilori-agent; do [ -e "$m/$f" ] && fail "symlink chain: hostile $f ran"; done

# Missing CLI: exit 127, nothing on stdout.
rm "$h/.bun/bin/tilori-agent"
set +e; out=$(cd "$p" && env -i HOME="$h" PATH=".:$sys" sh "$run" d 2>/dev/null); rc=$?; set -e
[ "$rc" = 127 ] && [ -z "$out" ] || fail "missing CLI: rc=$rc out=$out"
for f in preload bun tilori-agent; do [ -e "$m/$f" ] && fail "hostile $f ran"; done
echo "hostile-cwd: ok"
