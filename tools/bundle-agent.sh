#!/bin/sh
# Builds plugins/tilori/vendor/tilori-agent.js, the tilori-agent CLI bundled
# into one JS file, from a tilori-agent release tag, and records where it came
# from in plugins/tilori/vendor/SOURCE.
#
#   sh tools/bundle-agent.sh v0.1.5             # update the bundle to a new tag
#   sh tools/bundle-agent.sh --verify [<dir>]   # check the bundle in <dir>
#                                               # (default: this checkout)
#
# --verify runs three checks and prints one line for each, then a summary:
#   sha256    the vendored file's sha256 is SOURCE's and the one in the
#             release's tilori-agent.js.sha256 asset, which
#             github-actions[bot] uploaded;
#   SOURCE    SOURCE, minus its comment line, equals that asset, and the tag
#             resolves to SOURCE's commit;
#   --verify  a rebuild from that commit with SOURCE's Bun matches the
#             vendored file byte for byte.
#   bundle ok: <tag> @ <dir's HEAD> (sha256, SOURCE, --verify)
# To review a PR, run it from main against the PR's checkout, so the PR can't
# change the script that checks it:
#   run from main: sh tools/bundle-agent.sh --verify <path to PR checkout>
#
# Reproducible: a fresh clone of the tag, `bun install --frozen-lockfile
# --ignore-scripts`, `bun build --target=bun`. Output depends only on the
# tagged tree and the Bun version, so SOURCE pins the Bun version and
# --verify refuses to compare with a different one. Needs gh (the repo is
# private), git and Bun; uses gh's own login and never prints a token.
# Writes nothing outside the repo except a temp dir. GH and BUN may be
# overridden for tests.
set -eu
here=$(pwd)
cd "$(dirname "$0")/.."
repo=universal-market/tilori-agent
GH=${GH:-gh}
BUN="${BUN:-$(command -v bun || echo "$HOME/.bun/bin/bun")}"

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
usage() { echo "usage: sh tools/bundle-agent.sh <tag> | --verify [<path to checkout>] (to review a PR, run from main)" >&2; exit 2; }
# Clones $tag into $t/src and builds $t/tilori-agent.js; prints the commit.
build() {
  "$GH" repo clone "$repo" "$t/src" -- -q --depth 1 --branch "$tag" -c advice.detachedHead=false >/dev/null 2>&1 || return 1
  (cd "$t/src" && "$BUN" install --frozen-lockfile --ignore-scripts >/dev/null \
    && "$BUN" build src/cli.ts --target=bun --outfile "$t/tilori-agent.js" >/dev/null) || return 1
  git -C "$t/src" rev-parse HEAD
}

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

case "${1:-}" in
  --verify) [ $# -le 2 ] || usage ;;
  v[0-9]*) [ $# -eq 1 ] || usage ;;
  *) usage ;;
esac

if [ "$1" = --verify ]; then
  root=.
  if [ $# -eq 2 ]; then
    case "$2" in /*) root=$2 ;; *) root=$here/$2 ;; esac
  fi
  vendor=$root/plugins/tilori/vendor
  at=
  # One line saying why, then the summary naming the check that failed.
  fail() { check=$1; shift; echo "$*" >&2; echo "bundle FAILED: $check$at" >&2; exit 1; }
  # SOURCE comes from the checkout under review: its values are checked
  # against these shapes before any of them is printed or used in a URL.
  # A key that isn't there exactly once reads as empty, and a value with a
  # newline never matches: grep -x would accept it if any one line did.
  field() { [ "$(grep -c "^$1=" "$vendor/SOURCE")" = 1 ] && sed -n "s/^$1=//p" "$vendor/SOURCE" || true; }
  shaped() {
    case $1 in *'
'*) return 1 ;; esac
    printf '%s' "$1" | grep -Eqx "$2"
  }

  [ -f "$vendor/SOURCE" ] && [ -f "$vendor/tilori-agent.js" ] \
    || fail sha256 "no plugins/tilori/vendor/SOURCE and tilori-agent.js in $root"
  head=$(git -C "$root" rev-parse HEAD 2>/dev/null) || fail sha256 "$root is not a git checkout"
  [ -z "$(git -C "$root" status --porcelain -- plugins/tilori/vendor)" ] \
    || fail sha256 "plugins/tilori/vendor has uncommitted changes, so a result would not be for $head"
  at=" @ $head"
  tag=$(field tag); want_commit=$(field commit); want_bun=$(field bun); want_sha=$(field sha256)
  shaped "$tag" 'v[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}' || fail SOURCE "SOURCE: tag is missing, duplicated or not vX.Y.Z"
  at=" for $tag @ $head"
  [ "$(field repo)" = "$repo" ] || fail SOURCE "SOURCE: repo is missing, duplicated or not $repo"
  shaped "$want_commit" '[0-9a-f]{40}' || fail SOURCE "SOURCE: commit is missing, duplicated or not a 40-character sha"
  shaped "$want_bun" '[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}' || fail SOURCE "SOURCE: bun is missing, duplicated or not X.Y.Z"
  shaped "$want_sha" '[0-9a-f]{64}' || fail SOURCE "SOURCE: sha256 is missing, duplicated or not 64 hex characters"

  # sha256: the vendored file, SOURCE and the release asset agree.
  uploader=$("$GH" api "repos/$repo/releases/tags/$tag" \
    --jq '.assets[] | select(.name == "tilori-agent.js.sha256") | .uploader.login' 2>/dev/null) \
    || fail sha256 "release $tag not found in $repo (or gh can't read it: see \`gh auth status\`); tag and publish it before this PR"
  [ -n "$uploader" ] || fail sha256 "release $tag has no tilori-agent.js.sha256 asset yet; wait for its release-hash run to upload it"
  if [ "$uploader" != "github-actions[bot]" ]; then
    shaped "$uploader" '[A-Za-z0-9-]{1,39}(\[bot\])?' || uploader='an unexpected account'
    fail sha256 "release $tag's tilori-agent.js.sha256 was uploaded by $uploader, not github-actions[bot]"
  fi
  "$GH" release download "$tag" -R "$repo" -p tilori-agent.js.sha256 -D "$t" >/dev/null 2>&1 \
    || fail sha256 "couldn't download tilori-agent.js.sha256 from release $tag"
  asset=$t/tilori-agent.js.sha256
  rel_sha=$(sed -n 's/^sha256=//p' "$asset")
  shaped "$rel_sha" '[0-9a-f]{64}' || fail sha256 "release $tag's tilori-agent.js.sha256 has no sha256= line"
  got=$(sha256 "$vendor/tilori-agent.js")
  [ "$got" = "$rel_sha" ] || fail sha256 "sha256 mismatch: vendored $got, release $tag $rel_sha"
  [ "$want_sha" = "$rel_sha" ] || fail sha256 "sha256 mismatch: SOURCE $want_sha, release $tag $rel_sha"
  echo "sha256 ok: vendored file = SOURCE = release $tag ($got)"

  # SOURCE: equals the asset, and the tag is still SOURCE's commit.
  grep -v '^#' "$vendor/SOURCE" > "$t/source"
  if ! cmp -s "$t/source" "$asset"; then
    differ=
    for k in repo tag commit bun sha256; do
      [ "$(sed -n "s/^$k=//p" "$t/source")" = "$(sed -n "s/^$k=//p" "$asset")" ] || differ="${differ:+$differ, }$k"
    done
    fail SOURCE "SOURCE differs from release $tag's tilori-agent.js.sha256 in: ${differ:-its other lines}"
  fi
  tag_commit=$("$GH" api "repos/$repo/commits/refs/tags/$tag" --jq .sha 2>/dev/null) \
    || fail SOURCE "can't resolve tag $tag in $repo"
  shaped "$tag_commit" '[0-9a-f]{40}' || fail SOURCE "can't resolve tag $tag in $repo"
  [ "$tag_commit" = "$want_commit" ] || fail SOURCE "SOURCE $want_commit is not tag $tag ($tag_commit)"
  echo "SOURCE ok: matches release $tag; $tag = $want_commit"

  # --verify: a rebuild of that commit is the vendored file.
  bun_version=$("$BUN" --version 2>/dev/null) || bun_version=none
  [ "$bun_version" = "$want_bun" ] \
    || fail --verify "SOURCE was built with Bun $want_bun, this is Bun $bun_version; set BUN to a Bun $want_bun binary"
  commit=$(build) || fail --verify "couldn't clone and build $repo at $tag"
  [ "$commit" = "$want_commit" ] \
    || fail --verify "the clone of $tag is at $commit, SOURCE pins $want_commit (tag moved?)"
  sha=$(sha256 "$t/tilori-agent.js")
  [ "$sha" = "$want_sha" ] || fail --verify "rebuild mismatch: rebuild of $tag $sha, SOURCE $want_sha"
  cmp -s "$t/tilori-agent.js" "$vendor/tilori-agent.js" \
    || fail --verify "rebuild mismatch: the vendored file differs from the rebuild of $tag"
  echo "--verify ok: a rebuild of $tag with Bun $want_bun matches byte for byte"
  echo "bundle ok: $tag @ $head (sha256, SOURCE, --verify)"
  exit 0
fi

tag=$1
vendor=plugins/tilori/vendor
[ -x "$BUN" ] || { echo "bundle-agent: bun not found" >&2; exit 1; }
bun_version=$("$BUN" --version)
commit=$(build) || { echo "bundle-agent: couldn't clone and build $repo at $tag" >&2; exit 1; }
sha=$(sha256 "$t/tilori-agent.js")
cp "$t/tilori-agent.js" "$vendor/tilori-agent.js"
chmod 644 "$vendor/tilori-agent.js"
cat > "$vendor/SOURCE" <<SRC
# Generated by tools/bundle-agent.sh; do not edit. Verify with --verify.
repo=$repo
tag=$tag
commit=$commit
bun=$bun_version
sha256=$sha
SRC
echo "bundle-agent: wrote $vendor/tilori-agent.js from $tag ($commit), sha256 $sha"
