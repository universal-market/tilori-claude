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
  "api repos/universal-market/tilori-agent/releases/tags/v0.1.17 "*"@tsv"*)
    [ -n "\${STUB_NO_RELEASE:-}" ] && exit 1; cat "$t/assets.tsv" 2>/dev/null; exit 0 ;;
  "api repos/universal-market/tilori-agent/releases/tags/v0.1.17 "*)
    [ -n "\${STUB_NO_RELEASE:-}" ] && exit 1; printf '%s\n' "\${STUB_UPLOADER-github-actions[bot]}" ;;
  "api repos/universal-market/tilori-agent/commits/refs/tags/v0.1.17 "*) echo "\${STUB_TAG_COMMIT:-$C}" ;;
  "release download v0.1.17 "*) p=; while [ \$# -gt 0 ]; do [ "\$1" = -D ] && d=\$2; [ "\$1" = -p ] && p=\$2; shift; done
    case "\$p" in
      tilori-agent.js.sha256) printf '%s\n' "\${STUB_ASSET:-\$ASSET}" > "\$d/tilori-agent.js.sha256" ;;
      *) [ -f "$t/binassets/\$p" ] || exit 1; cp "$t/binassets/\$p" "\$d/\$p" ;;
    esac ;;
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
refuse "bad tag" SOURCE "SOURCE: tag is missing, duplicated or not vX.Y.Z"
case "$out" in *"$(printf '\033')"*) fail "bad tag: printed an escape" ;; esac
# A duplicate key is refused too, though one of its lines has the right shape.
setup "$(printf '%s\ntag=x%s[2J\n' "$ASSET" "$(printf '\033')")"
refuse "duplicate tag" SOURCE "SOURCE: tag is missing, duplicated or not vX.Y.Z"
case "$out" in *"$(printf '\033')"*) fail "duplicate tag: printed an escape" ;; esac
# Wren's case: a duplicate line that would forge the summary a reviewer pastes.
setup "$(printf '%s\ncommit=bundle ok: v0.1.99 @ %s (sha256, SOURCE, --verify)\n' "$ASSET" "$C")"
refuse "duplicate commit" SOURCE "SOURCE: commit is missing, duplicated or not a 40-character sha"
case "$out" in *"v0.1.99"*) fail "duplicate commit: printed the forged line" ;; esac
# A market plugin with its own MCP server carries a copy (UNI-748):
# identical and committed, or refused. Since UNI-768 it is a stub with no
# .mcp.json, which needs no copy.
market() { mkdir -p "$t/r/plugins/market/vendor"; echo '{}' > "$t/r/plugins/market/.mcp.json"; cp "$t/r/plugins/tilori/vendor/"* "$t/r/plugins/market/vendor/"; }
setup; market; (cd "$t/r" && g add -A && g commit -qm market); HEAD=$(git -C "$t/r" rev-parse HEAD)
out=$(run) || fail "market copy: $out"
[ "$(printf '%s\n' "$out" | tail -1)" = "bundle ok: v0.1.17 @ $HEAD (sha256, SOURCE, --verify)" ] || fail "market copy summary: $out"
setup; market; echo tampered > "$t/r/plugins/market/vendor/tilori-agent.js"; (cd "$t/r" && g add -A && g commit -qm market)
refuse "market bundle differs" sha256 "plugins/market/vendor/tilori-agent.js differs from plugins/tilori/vendor/tilori-agent.js"
setup; market; (cd "$t/r" && g add -A && g commit -qm market); echo x >> "$t/r/plugins/market/vendor/SOURCE"
refuse "dirty market vendor" sha256 "uncommitted changes"
setup; mkdir -p "$t/r/plugins/market"; echo '{}' > "$t/r/plugins/market/.mcp.json"; (cd "$t/r" && g add -A && g commit -qm market)
refuse "market MCP without a bundle" sha256 "plugins/market/vendor/tilori-agent.js differs"
setup; mkdir -p "$t/r/plugins/market/scripts"; touch "$t/r/plugins/market/scripts/notice.sh"; (cd "$t/r" && g add -A && g commit -qm stub); HEAD=$(git -C "$t/r" rev-parse HEAD)
out=$(run) || fail "market stub without a bundle refused: $out"
[ "$(printf '%s\n' "$out" | tail -1)" = "bundle ok: v0.1.17 @ $HEAD (sha256, SOURCE, --verify)" ] || fail "market stub summary: $out"
# Compiled binaries (UNI-770). binrel writes a release with all four
# executables and their .sha256 assets; BINARIES pins them.
BINS="tilori-agent-linux-x64 tilori-agent-linux-arm64 tilori-agent-darwin-x64 tilori-agent-darwin-arm64"
binsha() { printf '%s' "$1" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1; }
binrel() {
  rm -rf "$t/binassets"; mkdir -p "$t/binassets"; : > "$t/assets.tsv"
  for a in $BINS; do
    h=$(binsha "$a")
    printf 'repo=universal-market/tilori-agent\ntag=v0.1.17\ncommit=%s\nbun=1.4.3\nasset=%s\nsha256=%s\n' "$C" "$a" "$h" > "$t/binassets/$a.sha256"
    printf '%s\tgithub-actions[bot]\tsha256:%s\n%s.sha256\tgithub-actions[bot]\t\n' "$a" "$h" "$a" >> "$t/assets.tsv"
  done
}
pin() { { echo '# Generated'; for a in $BINS; do echo "$a $(binsha "$a")"; done; } > "$t/r/plugins/tilori/vendor/BINARIES"; (cd "$t/r" && g add -A && g commit -qm bins); HEAD=$(git -C "$t/r" rev-parse HEAD); }
nobins() { rm -rf "$t/binassets"; rm -f "$t/assets.tsv"; }

binrel; setup; pin; out=$(run) || fail "binaries: $out"
case "$out" in *"binaries ok: vendor/BINARIES = release v0.1.17's four .sha256 assets"*) ;; *) fail "binaries ok line: $out" ;; esac
[ "$(printf '%s\n' "$out" | tail -1)" = "bundle ok: v0.1.17 @ $HEAD (sha256, SOURCE, --verify)" ] || fail "binaries summary: $out"
nobins; setup; out=$(run) || fail "no binaries: $out"
case "$out" in *"binaries: none on release v0.1.17, none pinned"*) ;; *) fail "no binaries line: $out" ;; esac
nobins; setup; pin; refuse "BINARIES without release binaries" binaries "vendor/BINARIES pins binaries, but release v0.1.17 has none"
binrel; setup; refuse "release binaries without BINARIES" binaries "release v0.1.17 has binaries but vendor/BINARIES is missing"
binrel; setup; pin; sed -i.bak "s/^tilori-agent-darwin-arm64 .*/tilori-agent-darwin-arm64 $(binsha other)/" "$t/r/plugins/tilori/vendor/BINARIES"; rm -f "$t/r/plugins/tilori/vendor/BINARIES.bak"; (cd "$t/r" && g commit -qam edit)
refuse "a changed pin" binaries "vendor/BINARIES differs from release v0.1.17's .sha256 assets"
binrel; sed -i.bak 's/^\(tilori-agent-linux-x64\)\tgithub-actions\[bot\]/\1\tmallory/' "$t/assets.tsv"; setup; pin
refuse "an executable uploaded by a person" binaries "release v0.1.17's tilori-agent-linux-x64 was uploaded by mallory, not github-actions[bot]"
binrel; sed -i.bak 's/^\(tilori-agent-linux-x64.sha256\)\tgithub-actions\[bot\]/\1\tmallory/' "$t/assets.tsv"; setup; pin
refuse "a .sha256 uploaded by a person" binaries "tilori-agent-linux-x64.sha256 was uploaded by mallory"
binrel; sed -i.bak "s/^\(tilori-agent-darwin-x64\t[^\t]*\t\).*/\1sha256:$(binsha other)/" "$t/assets.tsv"; setup; pin
refuse "GitHub's digest differs" binaries "GitHub's digest of tilori-agent-darwin-x64 on v0.1.17 is not the sha256"
binrel; sed -i.bak "s/^commit=.*/commit=$(printf 'e%.0s' $(seq 40))/" "$t/binassets/tilori-agent-linux-arm64.sha256"; setup; pin
refuse "a .sha256 for another commit" binaries "tilori-agent-linux-arm64.sha256 doesn't say commit=$C"
binrel; sed -i.bak 's/^asset=.*/asset=tilori-agent-linux-x64/' "$t/binassets/tilori-agent-darwin-arm64.sha256"; setup; pin
refuse "a .sha256 for another asset" binaries "tilori-agent-darwin-arm64.sha256 doesn't say asset=tilori-agent-darwin-arm64"
binrel; printf 'commit=%s\n' "$(printf 'e%.0s' $(seq 40))" >> "$t/binassets/tilori-agent-linux-x64.sha256"; setup; pin
refuse "a second commit line" binaries "tilori-agent-linux-x64.sha256 doesn't say commit=$C"
binrel; printf 'sha256=%s\n' "$(binsha x)" >> "$t/binassets/tilori-agent-linux-x64.sha256"; setup; pin
refuse "two sha256 lines" binaries "tilori-agent-linux-x64.sha256 has no single sha256= line"
binrel; grep -v '^tilori-agent-darwin-x64	' "$t/assets.tsv" > "$t/a2"; mv "$t/a2" "$t/assets.tsv"; setup; pin
refuse "a missing executable" binaries "release v0.1.17 has no tilori-agent-darwin-x64"
nobins

# Writing a bundle pins the release's binaries, or none.
gen() {
  rm -rf "$t/gen"; mkdir -p "$t/gen/tools" "$t/gen/plugins/tilori/vendor"
  cp "$repo/tools/bundle-agent.sh" "$t/gen/tools/"
  (cd "$t/gen" && env GH="$t/gh" BUN="$t/bun" sh tools/bundle-agent.sh v0.1.17 2>&1)
}
binrel; out=$(gen) || fail "write with binaries: $out"
[ "$(grep -v '^#' "$t/gen/plugins/tilori/vendor/BINARIES")" = "$(for a in $BINS; do echo "$a $(binsha "$a")"; done)" ] || fail "written BINARIES: $(cat "$t/gen/plugins/tilori/vendor/BINARIES")"
nobins; out=$(gen) || fail "write without binaries: $out"
[ ! -e "$t/gen/plugins/tilori/vendor/BINARIES" ] || fail "BINARIES written for a release without binaries"
case "$out" in *"has no compiled binaries"*) ;; *) fail "no-binaries note: $out" ;; esac
binrel; sed -i.bak 's/\tgithub-actions\[bot\]\tsha256/\tmallory\tsha256/' "$t/assets.tsv"
if out=$(gen); then fail "write with a bad binary: accepted"; fi
[ ! -e "$t/gen/plugins/tilori/vendor/BINARIES" ] || fail "BINARIES written from a bad release"
nobins

out=$(sh "$repo/tools/bundle-agent.sh" --bogus 2>&1) && fail "bad argument accepted"
case "$out" in *"run from main"*) ;; *) fail "usage does not say run from main: $out" ;; esac
echo "bundle-verify: ok"
