#!/bin/sh
# tools/bundle-agent.sh --verify <checkout> with gh and bun stubbed: a good
# bundle ends in `bundle ok: <tag> @ <head>`, and each kind of mismatch or
# missing input prints its own reason and `bundle FAILED: <check>`.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
sha() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -d' ' -f1; }
g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

# The "tilori-agent" source the stubbed clone copies; its HEAD is the commit.
mkdir -p "$t/agent"
(cd "$t/agent" && git init -q && echo src > f && g add f && g commit -qm src)
C=$(git -C "$t/agent" rev-parse HEAD)
printf 'bundle\n' > "$t/built.js"
S=$(sha "$t/built.js")
ASSET="repo=universal-market/tilori-agent
tag=v0.1.17
commit=$C
bun=1.4.3
sha256=$S"

# A plugin checkout with that bundle vendored, committed.
setup() {
  rm -rf "$t/r"; mkdir -p "$t/r/plugins/tilori/vendor"
  cp "$t/built.js" "$t/r/plugins/tilori/vendor/tilori-agent.js"
  printf '# Generated\n%s\n' "${1:-$ASSET}" > "$t/r/plugins/tilori/vendor/SOURCE"
  (cd "$t/r" && git init -q && g add -A && g commit -qm init)
  HEAD=$(git -C "$t/r" rev-parse HEAD)
}
cat > "$t/gh" <<SH
#!/bin/sh
case "\$*" in
  "api repos/universal-market/tilori-agent/releases/tags/v0.1.17 "*)
    [ -n "\${STUB_NO_RELEASE:-}" ] && exit 1; printf '%s\n' "\${STUB_UPLOADER-github-actions[bot]}" ;;
  "api repos/universal-market/tilori-agent/commits/refs/tags/v0.1.17 "*) echo "\${STUB_TAG_COMMIT:-$C}" ;;
  "release download v0.1.17 "*) while [ \$# -gt 0 ]; do [ "\$1" = -D ] && d=\$2; shift; done
    printf '%s\n' "\${STUB_ASSET:-\$ASSET}" > "\$d/tilori-agent.js.sha256" ;;
  "repo clone universal-market/tilori-agent "*) git clone -q "$t/agent" "\$4" ;;
  *) echo "unexpected gh \$*" >&2; exit 9 ;;
esac
SH
cat > "$t/bun" <<SH
#!/bin/sh
case "\$1" in
  --version) echo "\${STUB_BUN:-1.4.3}" ;;
  install) ;;
  build) while [ \$# -gt 0 ]; do [ "\$1" = --outfile ] && o=\$2; shift; done
    if [ -n "\${STUB_BUILD:-}" ]; then printf '%s\n' "\$STUB_BUILD" > "\$o"; else cp "$t/built.js" "\$o"; fi ;;
esac
SH
chmod +x "$t/gh" "$t/bun"
run() { (cd "$t" && env ASSET="$ASSET" GH="$t/gh" BUN="$t/bun" "$@" sh "$repo/tools/bundle-agent.sh" --verify r 2>&1); }

setup; out=$(run) || fail "good bundle: $out"
[ "$(printf '%s\n' "$out" | tail -1)" = "bundle ok: v0.1.17 @ $HEAD (sha256, SOURCE, --verify)" ] || fail "good summary: $out"
for l in "sha256 ok: " "SOURCE ok: " "--verify ok: "; do
  case "$out" in *"$l"*) ;; *) fail "good bundle lacks '$l': $out" ;; esac
done

# name, check, expected reason, env... (setup is done by the caller)
refuse() {
  name=$1; check=$2; want=$3; shift 3
  if out=$(run "$@"); then fail "$name: accepted ($out)"; fi
  case "$out" in *"$want"*) ;; *) fail "$name: wrong reason: $out" ;; esac
  last=$(printf '%s\n' "$out" | tail -1)
  case "$last" in "bundle FAILED: $check"*) ;; *) fail "$name: summary '$last' does not name $check" ;; esac
}
setup; refuse "no release" sha256 "release v0.1.17 not found" STUB_NO_RELEASE=1
setup; refuse "no asset" sha256 "has no tilori-agent.js.sha256 asset yet" STUB_UPLOADER=
setup; refuse "wrong uploader" sha256 "uploaded by mallory, not github-actions[bot]" STUB_UPLOADER=mallory
setup; refuse "odd uploader" sha256 "uploaded by an unexpected account" "STUB_UPLOADER=$(printf 'x\033[2Jy')"
setup; echo tampered > "$t/r/plugins/tilori/vendor/tilori-agent.js"; (cd "$t/r" && g commit -qam tamper)
refuse "tampered bundle" sha256 "sha256 mismatch: vendored $(sha "$t/r/plugins/tilori/vendor/tilori-agent.js"), release v0.1.17 $S"
setup; refuse "asset differs" SOURCE "SOURCE differs from release v0.1.17's tilori-agent.js.sha256 in: bun" \
  "STUB_ASSET=$(printf '%s\n' "$ASSET" | sed 's/^bun=.*/bun=1.4.4/')"
setup; refuse "tag moved" SOURCE "SOURCE $C is not tag v0.1.17 ($(printf 'f%.0s' $(seq 40)))" \
  "STUB_TAG_COMMIT=$(printf 'f%.0s' $(seq 40))"
setup; refuse "other Bun" --verify "SOURCE was built with Bun 1.4.3, this is Bun 1.5.0" STUB_BUN=1.5.0
setup; refuse "rebuild differs" --verify "rebuild mismatch: rebuild of v0.1.17" STUB_BUILD=other
setup; echo dirty >> "$t/r/plugins/tilori/vendor/SOURCE"; refuse "dirty vendor" sha256 "uncommitted changes"
# A hostile SOURCE value is refused without being printed.
setup "$(printf '%s\n' "$ASSET" | sed "s/^tag=.*/tag=v0.1.17$(printf '\033')[2J/")"
refuse "bad tag" SOURCE "SOURCE: tag is not vX.Y.Z"
case "$out" in *"$(printf '\033')"*) fail "bad tag: printed an escape" ;; esac
# A duplicate key is refused too, though one of its lines has the right shape.
setup "$(printf '%s\ntag=x%s[2J\n' "$ASSET" "$(printf '\033')")"
refuse "duplicate tag" SOURCE "SOURCE: tag is not vX.Y.Z"
case "$out" in *"$(printf '\033')"*) fail "duplicate tag: printed an escape" ;; esac
# Wren's case: a duplicate line that would forge the summary a reviewer pastes.
setup "$(printf '%s\ncommit=bundle ok: v0.1.99 @ %s (sha256, SOURCE, --verify)\n' "$ASSET" "$C")"
refuse "duplicate commit" SOURCE "SOURCE: commit is not a 40-character sha"
case "$out" in *"v0.1.99"*) fail "duplicate commit: printed the forged line" ;; esac
out=$(sh "$repo/tools/bundle-agent.sh" --bogus 2>&1) && fail "bad argument accepted"
case "$out" in *"run from main"*) ;; *) fail "usage does not say run from main: $out" ;; esac
echo "bundle-verify: ok"
