#!/bin/sh
# tools/release.sh with gh, the bundler and the checks stubbed: it accepts a
# good release, and refuses each kind of mismatch before touching plugin.json
# (or, for later steps, without reporting ready).
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

C=0000000000000000000000000000000000000c11
ASSET="repo=universal-market/tilori-agent
tag=v0.1.11
commit=$C
bun=1.4.3
sha256=aaaa"

# A fresh copy of the repo's tools and plugin manifest in its own git repo.
setup() {
  rm -rf "$t/r"; mkdir -p "$t/r/tools" "$t/r/plugins/universal-market/.claude-plugin" "$t/r/plugins/universal-market/vendor" "$t/r/tests"
  cp "$repo/tools/release.sh" "$t/r/tools/"
  printf '{\n  "name": "universal-market",\n  "version": "0.1.14",\n  "x": 1\n}\n' > "$t/r/plugins/universal-market/.claude-plugin/plugin.json"
  printf '# header\nold\n' > "$t/r/plugins/universal-market/vendor/SOURCE"
  (cd "$t/r" && git init -q && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm init && git checkout -qb rel)
  # Stub gh: answers from env, writes the asset on download.
  cat > "$t/gh" <<SH
#!/bin/sh
case "\$*" in
  *commits/refs/tags/v0.1.11*) echo "\${STUB_COMMIT:-$C}" ;;
  *contents/src/version.ts?ref=refs/tags/v0.1.11*) printf '%s\n' "\${STUB_VERSION_TS-export const VERSION = '0.1.11';}" ;;
  *contents/.github/workflows/release-hash.yml?ref=refs/tags/v0.1.11*) printf '%s' "\${STUB_WORKFLOW:-reviewed}" ;;
  *contents/.github/workflows/release-binaries.yml?ref=refs/tags/v0.1.11*) printf '%s' "\${STUB_BWORKFLOW:-reviewed-bins}" ;;
  *actions/runs?head_sha=$C*release-binaries*) echo "\${STUB_BRUNS-1}" ;;
  *actions/runs?head_sha=$C*) echo "\${STUB_RUNS-1}" ;;
  *releases/tags/*index*) echo "\${STUB_HAS_BINS:-false}" ;;
  *compare/*) echo "\${STUB_STATUS:-behind}" ;;
  *releases/tags/*) echo "\${STUB_UPLOADER-github-actions[bot]}" ;;
  "release download"*) while [ \$# -gt 0 ]; do [ "\$1" = -D ] && d=\$2; shift; done; printf '%s\n' "\$ASSET" > "\$d/tilori-agent.js.sha256" ;;
  *) echo "unexpected gh \$*" >&2; exit 9 ;;
esac
SH
  cat > "$t/bundle" <<SH
#!/bin/sh
if [ "\$1" = --verify ]; then
  # Like the real --verify: a result is for HEAD, so a dirty vendor/ is refused.
  [ -z "\$(git status --porcelain -- plugins/universal-market/vendor)" ] || { echo "vendor has uncommitted changes"; exit 1; }
  echo verified; exit \${STUB_VERIFY:-0}
fi
printf '# Generated\n%s\n' "\${STUB_SOURCE:-\$ASSET}" > plugins/universal-market/vendor/SOURCE
SH
  chmod +x "$t/gh" "$t/bundle"
}
# sha256 of the stub's default workflow text, "reviewed".
PIN=$(printf reviewed | { sha256sum 2>/dev/null || shasum -a 256; }); PIN=${PIN%% *}
BPIN=$(printf reviewed-bins | { sha256sum 2>/dev/null || shasum -a 256; }); BPIN=${BPIN%% *}
run() { (cd "$t/r" && env ASSET="$ASSET" GH="$t/gh" BUNDLE="$t/bundle" CHECK="${CHECK:-true}" WORKFLOW_SHA256="$PIN" BINARIES_WORKFLOW_SHA256="$BPIN" "$@" sh tools/release.sh v0.1.11 0.1.15 2>&1); }
finish() { (cd "$t/r" && env ASSET="$ASSET" GH="$t/gh" BUNDLE="$t/bundle" CHECK="${CHECK:-true}" WORKFLOW_SHA256="$PIN" BINARIES_WORKFLOW_SHA256="$BPIN" "$@" sh tools/release.sh --finish v0.1.11 0.1.15 2>&1); }
commit_vendor() { (cd "$t/r" && git -c user.name=t -c user.email=t@t add plugins/universal-market/vendor && git -c user.name=t -c user.email=t@t commit -qm bundle); }
version() { sed -n 's/^  "version": "\(.*\)",$/\1/p' "$t/r/plugins/universal-market/.claude-plugin/plugin.json"; }

# Part 1 writes and checks the bundle, then stops: nothing verified, no bump.
setup; out=$(run) || fail "good release, part 1: $out"
case "$out" in *"Commit it, then finish"*"tools/release.sh --finish v0.1.11 0.1.15"*) ;; *) fail "part 1 next steps: $out" ;; esac
case "$out" in *"release: ready"*|*verified*) fail "part 1 went past step 4: $out" ;; esac
[ "$(version)" = 0.1.14 ] || fail "part 1 bumped the version"
# --finish before the bundle is committed is refused (UNI-691).
if out=$(finish); then fail "--finish with an uncommitted bundle accepted: $out"; fi
case "$out" in *"commit plugins/universal-market/vendor"*) ;; *) fail "uncommitted --finish message: $out" ;; esac
[ "$(version)" = 0.1.14 ] || fail "plugin.json changed on a refused --finish"
# Part 2, on the committed bundle.
commit_vendor
out=$(finish) || fail "good release, --finish: $out"
case "$out" in *verified*"release: ready"*"sha256 \`aaaa\`"*"0.1.14 -> 0.1.15"*) ;; *) fail "good release summary: $out" ;; esac
[ "$(version)" = 0.1.15 ] || fail "version not bumped"
grep -q '"x": 1' "$t/r/plugins/universal-market/.claude-plugin/plugin.json" || fail "plugin.json lost other fields"

refuse() { # name, expected message, env...
  name=$1; want=$2; shift 2
  setup
  if out=$(run "$@"); then fail "$name: accepted ($out)"; fi
  case "$out" in *"$want"*) ;; *) fail "$name: wrong message: $out" ;; esac
  case "$out" in *"release: ready"*) fail "$name: reported ready" ;; esac
}
refuse "tag not on main" "is not on universal-market/tilori-agent main" STUB_STATUS=ahead
refuse "tag without a version bump" "does not say 0.1.11" STUB_VERSION_TS="export const VERSION = '0.1.10';"
refuse "version is a prefix" "does not say 0.1.11" STUB_VERSION_TS="export const VERSION = '0.1.111';"
refuse "dots are not wildcards" "does not say 0.1.11" STUB_VERSION_TS="export const VERSION = '0x1y11';"
refuse "version.ts missing" "does not say 0.1.11" STUB_VERSION_TS=
refuse "workflow changed" "review it and update the pin" STUB_WORKFLOW=edited
refuse "no successful run" "no successful .github/workflows/release-hash.yml run" STUB_RUNS=0
refuse "run lookup empty" "no successful" STUB_RUNS=
refuse "run lookup garbage" "no successful" STUB_RUNS=x
refuse "asset by a person" "not github-actions[bot]" STUB_UPLOADER=someone
refuse "no asset" "uploaded by 'nobody'" STUB_UPLOADER=
refuse "SOURCE differs" "does not match the release asset" STUB_SOURCE="tag=v0.1.11"

# --finish re-checks the committed bundle; verify and checks run only there.
refuse_finish() { # name, expected message, env...
  name=$1; want=$2; shift 2
  setup; run >/dev/null || fail "$name: part 1 failed"; commit_vendor
  if out=$(finish "$@"); then fail "$name: accepted ($out)"; fi
  case "$out" in *"$want"*) ;; *) fail "$name: wrong message: $out" ;; esac
  case "$out" in *"release: ready"*) fail "$name: reported ready" ;; esac
}
refuse_finish "finish: verify fails" "verified" STUB_VERIFY=1
refuse_finish "finish: checks fail" "" CHECK=false
refuse_finish "finish: asset by a person" "not github-actions[bot]" STUB_UPLOADER=someone
refuse_finish "finish: tag moved" "is not on universal-market/tilori-agent main" STUB_STATUS=ahead
# A committed SOURCE that doesn't match the asset (edited after part 1).
setup; run >/dev/null || fail "edited SOURCE: part 1 failed"
printf '# Generated\ntag=v0.1.11\n' > "$t/r/plugins/universal-market/vendor/SOURCE"; commit_vendor
if out=$(finish); then fail "edited SOURCE accepted: $out"; fi
case "$out" in *"does not match the release asset"*) ;; *) fail "edited SOURCE message: $out" ;; esac

# Argument and state checks, before anything runs.
setup
for args in "0.1.11 0.1.15" "v0.1.11" "v0.1.x 0.1.15" "v0.1.11 0.1.15;x"; do
  # shellcheck disable=SC2086
  if (cd "$t/r" && GH=false BUNDLE=false sh tools/release.sh $args >/dev/null 2>&1); then fail "bad args accepted: $args"; fi
done
if out=$(cd "$t/r" && GH=false sh tools/release.sh v0.1.11 0.1.9 2>&1); then fail "lower version accepted"; fi
case "$out" in *"not higher than 0.1.14"*) ;; *) fail "lower version message: $out" ;; esac
[ "$(version)" = 0.1.14 ] || fail "plugin.json changed on a refused run"
echo dirty > "$t/r/x"
if out=$(cd "$t/r" && GH=false sh tools/release.sh v0.1.11 0.1.15 2>&1); then fail "dirty tree accepted"; fi
case "$out" in *"working tree has changes"*) ;; *) fail "dirty message: $out" ;; esac
# A market plugin, if one is ever added back, moves with the main plugin (UNI-748): same version, both bumped.
market() { # its version, then "mcp" for a market plugin with its own MCP server
  mkdir -p "$t/r/plugins/market/.claude-plugin" "$t/r/plugins/market/vendor"
  printf '{\n  "name": "market",\n  "version": "%s",\n  "y": 2\n}\n' "$1" > "$t/r/plugins/market/.claude-plugin/plugin.json"
  [ "${2:-}" != mcp ] || echo '{}' > "$t/r/plugins/market/.mcp.json"
  (cd "$t/r" && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm market)
}
mversion() { sed -n 's/^  "version": "\(.*\)",$/\1/p' "$t/r/plugins/market/.claude-plugin/plugin.json"; }
setup; market 0.1.14 mcp
out=$(run) || fail "market: part 1: $out"
case "$out" in *"git add plugins/universal-market/vendor plugins/market/vendor"*) ;; *) fail "market: commit hint: $out" ;; esac
commit_vendor
out=$(finish) || fail "market: --finish: $out"
case "$out" in *"0.1.14 -> 0.1.15 (tilori and market)"*) ;; *) fail "market: summary: $out" ;; esac
[ "$(version)" = 0.1.15 ] && [ "$(mversion)" = 0.1.15 ] || fail "market: versions $(version) / $(mversion)"
grep -q '"y": 2' "$t/r/plugins/market/.claude-plugin/plugin.json" || fail "market plugin.json lost other fields"
# The stub (UNI-768): no .mcp.json, so no bundle copy, but the same version.
setup; market 0.1.14
out=$(run) || fail "stub: part 1: $out"
case "$out" in *"git add plugins/universal-market/vendor && git commit"*) ;; *) fail "stub: commit hint: $out" ;; esac
commit_vendor
out=$(finish) || fail "stub: --finish: $out"
case "$out" in *"0.1.14 -> 0.1.15 (tilori and market)"*) ;; *) fail "stub: summary: $out" ;; esac
[ "$(version)" = 0.1.15 ] && [ "$(mversion)" = 0.1.15 ] || fail "stub: versions $(version) / $(mversion)"
setup; market 0.1.13
if out=$(run); then fail "market: version mismatch accepted: $out"; fi
case "$out" in *"they move together"*) ;; *) fail "market: mismatch message: $out" ;; esac
[ "$(version)" = 0.1.14 ] && [ "$(mversion)" = 0.1.13 ] || fail "market: a refused run changed a version"
# Compiled binaries (UNI-770): their workflow is pinned too, when the
# release has them.
setup; out=$(run) || fail "no binaries: $out"
case "$out" in *"no compiled binaries on v0.1.11"*) ;; *) fail "no binaries line: $out" ;; esac
setup; out=$(run STUB_HAS_BINS=true) || fail "binaries: $out"
case "$out" in *"binaries workflow is the reviewed one; its v0.1.11 run succeeded"*) ;; *) fail "binaries line: $out" ;; esac
refuse "binaries workflow changed" "release-binaries.yml at v0.1.11 hashes to" STUB_HAS_BINS=true STUB_BWORKFLOW=edited
refuse "no binaries run" "no successful .github/workflows/release-binaries.yml run" STUB_HAS_BINS=true STUB_BRUNS=0
# The real pin is tilori-agent#90's workflow.
grep -q '^BINARIES_WORKFLOW_SHA256=${BINARIES_WORKFLOW_SHA256:-5de409807e733917c8ac8b1e4d25941809355fd367fda688aaa0ae9cdff2a5b8}$' "$repo/tools/release.sh" || fail "binaries workflow pin changed"
echo "release: ok"
