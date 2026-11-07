#!/bin/sh
# run-agent.sh's runtime order for the bundled CLI (UNI-770): bun, then node
# 22.18+, then the pinned compiled binary fetched by fetch-agent.sh. Runs
# copies of the scripts against stub runtimes and a stub curl; nothing is
# downloaded.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
t=$(mktemp -d); trap 'chmod -R u+rwx "$t" 2>/dev/null; rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

# A PATH with the usual tools but no bun or node.
mkdir "$t/tools"
for d in /usr/bin /bin; do
  for f in "$d"/*; do
    n=${f##*/}
    case "$n" in bun | node | nodejs) continue ;; esac
    [ -e "$t/tools/$n" ] || ln -s "$f" "$t/tools/$n"
  done
done
BASE="$t/tools"

case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; esac
case "$(uname -m)" in x86_64 | amd64) arch=x64 ;; aarch64 | arm64) arch=arm64 ;; esac
asset="tilori-agent-$os-$arch"
TAG=v9.8.7

# The "release binary": a script that says it ran.
printf '#!/bin/sh\necho "binary $*"\n' >"$t/exe"
EXE_SHA=$(sha256 "$t/exe")

# A plugin copy: scripts, a stub bundle, SOURCE and BINARIES, and a stub curl
# in place of /usr/bin/curl that logs its arguments and serves $t/serve.
plugin() {
  chmod -R u+rwx "$t/p" "$t/data" 2>/dev/null || true
  rm -rf "$t/p" "$t/data" "$t/curl.log"
  mkdir -p "$t/p/scripts" "$t/p/vendor"
  cp "$repo/plugins/tilori/scripts/run-agent.sh" "$repo/plugins/tilori/scripts/find-agent.sh" "$repo/plugins/tilori/scripts/fetch-agent.sh" "$t/p/scripts/"
  sed "s|^CURL=/usr/bin/curl\$|CURL=$t/curl|" "$repo/plugins/tilori/scripts/fetch-agent.sh" >"$t/p/scripts/fetch-agent.sh"
  grep -q "^CURL=$t/curl\$" "$t/p/scripts/fetch-agent.sh" || fail "couldn't stub curl"
  chmod +x "$t/p/scripts/"*.sh
  echo 'console.log("bundle")' >"$t/p/vendor/tilori-agent.js"
  printf 'repo=universal-market/tilori-agent\ntag=%s\n' "$TAG" >"$t/p/vendor/SOURCE"
  {
    echo '# test'
    for a in tilori-agent-linux-x64 tilori-agent-linux-arm64 tilori-agent-darwin-x64 tilori-agent-darwin-arm64; do
      if [ "$a" = "$asset" ]; then echo "$a $EXE_SHA"; else echo "$a 0000000000000000000000000000000000000000000000000000000000000000"; fi
    done
  } >"$t/p/vendor/BINARIES"
  cp "$t/exe" "$t/serve"
  cat >"$t/curl" <<CURL
#!/bin/sh
echo "\$*" >>"$t/curl.log"
out=
while [ \$# -gt 0 ]; do case "\$1" in -o) out=\$2; shift ;; esac; shift; done
cp "$t/serve" "\$out"
CURL
  chmod +x "$t/curl"
}
# run [VAR=value ...]: run-agent.sh with args "a b", from a project dir.
run() {
  mkdir -p "$t/proj"
  (cd "$t/proj" && env -i HOME="$t/home" PATH="$BASE" CLAUDE_PLUGIN_DATA="$t/data" "$@" "$t/p/scripts/run-agent.sh" a b >"$t/out" 2>"$t/err")
}
mkdir -p "$t/home"

# --- node
mkdir -p "$t/node22" "$t/node20" "$t/node2217"
for v in 22:v22.18.0 20:v20.19.0 2217:v22.17.9; do
  dir=${v%%:*}; ver=${v#*:}
  cat >"$t/node$dir/node" <<NODE
#!/bin/sh
# The version check runs with NODE_OPTIONS cleared too, or this node says it is old.
[ "\$1" = --version ] && { [ -z "\${NODE_OPTIONS+x}" ] || { echo v1.0.0; exit 0; }; echo $ver; exit 0; }
echo "node ${ver} opts=\${NODE_OPTIONS-unset} path=\${NODE_PATH-unset} cwd=\$(pwd) args=\$*"
NODE
  chmod +x "$t/node$dir/node"
done

plugin
run PATH="$t/node22:$BASE" NODE_OPTIONS="--require /tmp/evil.js" NODE_PATH=/tmp/evil || fail "node: exit $?"
[ "$(cat "$t/out")" = "node v22.18.0 opts=unset path=unset cwd=/ args=$t/p/vendor/tilori-agent.js a b" ] || fail "node 22.18: $(cat "$t/out")"
[ ! -e "$t/curl.log" ] || fail "node: curl ran"

# Older node is skipped for the binary.
for d in node20 node2217; do
  plugin
  run PATH="$t/$d:$BASE" || fail "$d: exit $? ($(cat "$t/err"))"
  [ "$(cat "$t/out")" = "binary a b" ] || fail "$d: not skipped: $(cat "$t/out")"
done

# Bun still comes first.
mkdir -p "$t/bun"
printf '#!/bin/sh\necho "bun $*"\n' >"$t/bun/bun"; chmod +x "$t/bun/bun"
plugin
run PATH="$t/bun:$t/node22:$BASE" || fail "bun: exit $?"
[ "$(cat "$t/out")" = "bun --no-env-file $t/p/vendor/tilori-agent.js a b" ] || fail "bun first: $(cat "$t/out")"

# --- binary
plugin
run || fail "download: exit $? ($(cat "$t/err"))"
[ "$(cat "$t/out")" = "binary a b" ] || fail "download: $(cat "$t/out")"
grep -q "downloading tilori-agent $TAG for $os-$arch" "$t/err" || fail "download: no notice: $(cat "$t/err")"
[ "$(cat "$t/curl.log")" = "--proto =https --proto-redir =https --tlsv1.2 -fsSL --max-time 600 -o $(ls -a "$t/data/bin" >/dev/null; echo "$t/data/bin")/$(sed -n 's/.* -o [^ ]*\/\(\.download\.[A-Za-z0-9]*\) .*/\1/p' "$t/curl.log") https://github.com/universal-market/tilori-agent/releases/download/$TAG/$asset" ] \
  || fail "curl arguments: $(cat "$t/curl.log")"
exe="$t/data/bin/tilori-agent-$TAG-$os-$arch"
[ "$(find "$exe" -prune -perm 700 -print)" = "$exe" ] || fail "binary not 0700"
[ "$(find "$t/data/bin" -prune -perm 700 -print)" = "$t/data/bin" ] || fail "bin dir not 0700"
[ -z "$(ls -A "$t/data/bin" | grep '^\.download' || true)" ] || fail "temp file left"

# Cached: no second download.
rm "$t/curl.log"
run || fail "cached: exit $?"
[ "$(cat "$t/out")" = "binary a b" ] || fail "cached: $(cat "$t/out")"
[ ! -e "$t/curl.log" ] || fail "cached: downloaded again"
[ ! -s "$t/err" ] || fail "cached: stderr $(cat "$t/err")"

# A cached file that changed is not run; it is fetched again.
printf '#!/bin/sh\necho tampered\n' >"$exe"
run || fail "tampered: exit $?"
[ "$(cat "$t/out")" = "binary a b" ] || fail "tampered cache ran: $(cat "$t/out")"
[ -s "$t/curl.log" ] || fail "tampered: not fetched again"
chmod 755 "$exe"; rm "$t/curl.log"
run || fail "0755 cache: exit $?"
[ -s "$t/curl.log" ] || fail "0755 cache: not fetched again"
[ "$(find "$exe" -prune -perm 700 -print)" = "$exe" ] || fail "0755 cache: not 0700 after refetch"

# A download that doesn't match the pin is deleted and never run.
plugin
printf '#!/bin/sh\necho evil\n' >"$t/serve"
if run; then fail "mismatch: ran"; fi
[ "$(cat "$t/out")" = "" ] || fail "mismatch: printed $(cat "$t/out")"
grep -q "doesn't match its pinned sha256" "$t/err" || fail "mismatch: $(cat "$t/err")"
[ -z "$(ls -A "$t/data/bin")" ] || fail "mismatch: left $(ls -A "$t/data/bin")"

# A failed download.
plugin
printf '#!/bin/sh\nexit 22\n' >"$t/curl"
if run; then fail "curl failure: ran"; fi
grep -q "couldn't download" "$t/err" || fail "curl failure: $(cat "$t/err")"
[ -z "$(ls -A "$t/data/bin")" ] || fail "curl failure: left $(ls -A "$t/data/bin")"

# Refusals before any download.
refuse() { # <what> <stderr text> [VAR=value ...]
  what=$1; text=$2; shift 2
  if run "$@"; then fail "$what: ran"; fi
  [ ! -s "$t/out" ] || fail "$what: printed $(cat "$t/out")"
  grep -qF "$text" "$t/err" || fail "$what: stderr $(cat "$t/err")"
  [ ! -e "$t/curl.log" ] || fail "$what: curl ran"
}
plugin; rm "$t/p/vendor/BINARIES"; refuse "no BINARIES" "pins no tilori-agent binaries"
plugin; echo "$asset $EXE_SHA" >>"$t/p/vendor/BINARIES"; refuse "a duplicated pin" "pins no single $asset"
plugin; sed -i.bak "s/^$asset .*/$asset nothex/" "$t/p/vendor/BINARIES"; refuse "a malformed pin" "is not a sha256"
plugin; printf 'tag=v1.2.3/../../x\n' >"$t/p/vendor/SOURCE"; refuse "a malformed tag" "tag is not vX.Y.Z"
plugin; printf 'tag=v1.2.3\ntag=v1.2.4\n' >"$t/p/vendor/SOURCE"; refuse "two tags" "no single tag line"
plugin; refuse "no CLAUDE_PLUGIN_DATA" "CLAUDE_PLUGIN_DATA is not set" CLAUDE_PLUGIN_DATA=
plugin; refuse "a relative CLAUDE_PLUGIN_DATA" "CLAUDE_PLUGIN_DATA is not set" CLAUDE_PLUGIN_DATA=data
plugin; refuse "CLAUDE_PLUGIN_DATA with a space" "unexpected characters" CLAUDE_PLUGIN_DATA="$t/da ta"
plugin; mkdir -p "$t/data"; chmod 777 "$t/data"; refuse "a world-writable data dir" "writable by other users"
plugin; mkdir -p "$t/real"; ln -s "$t/real" "$t/data"; refuse "a symlinked data dir" "is a symlink"; rm -rf "$t/real"
plugin; mkdir -p "$t/data" "$t/realbin"; chmod 700 "$t/data" "$t/realbin"; ln -s "$t/realbin" "$t/data/bin"; refuse "a symlinked bin dir" "must be a directory of yours at 0700"; rm -rf "$t/realbin"
plugin; mkdir -p "$t/data/bin"; chmod 700 "$t/data"; chmod 755 "$t/data/bin"; refuse "a bin dir at 0755" "must be a directory of yours at 0700"

# Only the bundle this plugin ships gets the binary: another .js doesn't.
plugin
echo 'console.log(1)' >"$t/other.js"; chmod +x "$t/other.js"
if run TILORI_AGENT_BIN="$t/other.js"; then fail "other js: ran"; fi
grep -q "neither bun nor node 22.18+ found" "$t/err" || fail "other js: $(cat "$t/err")"
[ ! -e "$t/curl.log" ] || fail "other js: curl ran"

# The real fetch-agent.sh uses /usr/bin/curl with the fixed URL.
grep -q '^CURL=/usr/bin/curl$' "$repo/plugins/tilori/scripts/fetch-agent.sh" || fail "fetch-agent.sh: CURL is not /usr/bin/curl"
grep -q '^REPO=universal-market/tilori-agent$' "$repo/plugins/tilori/scripts/fetch-agent.sh" || fail "fetch-agent.sh: REPO changed"
echo "runtimes: ok"
