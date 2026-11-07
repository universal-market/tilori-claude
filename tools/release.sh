#!/bin/sh
# Prepares a plugin release that bundles a tilori-agent tag, locally, and
# stops at the first thing that doesn't match:
#
#   sh tools/release.sh v0.1.11 0.1.15            # steps 1-4, then stop
#   git commit plugins/tilori/vendor               # the "Bundle" commit
#   sh tools/release.sh --finish v0.1.11 0.1.15   # steps 1, 2, 4, then 5-7
#
# It runs in two parts because bundle-agent.sh --verify (step 5) only
# vouches for a committed bundle: the result is for HEAD, so a dirty
# vendor/ is refused (UNI-691). --finish re-checks the tag, the run and the
# asset against the committed SOURCE before verifying it.
#
#   1. the tag's commit is on tilori-agent main, and its src/version.ts
#      says the tag's version (v0.1.12 was tagged without a bump);
#   2. the release-hash workflow at the tag is the reviewed one (its sha256
#      is pinned below), it ran on the tag push for that commit and
#      succeeded, and the release's tilori-agent.js.sha256 asset was
#      uploaded by github-actions[bot] (that workflow, not a person);
#   3. tools/bundle-agent.sh <tag> rebuilds vendor/;
#   4. vendor/SOURCE, without its comment line, equals that asset;
#   5. tools/bundle-agent.sh --verify;
#   6. plugin.json (and the market plugin's, which must match it) gets
#      <plugin-version>, which must be higher;
#   7. the full tests/check.sh (no skips).
# Then it prints a summary for the PR. It never commits, pushes, tags,
# comments or opens a PR: that stays with the author and the lead.
# GH, BUNDLE, CHECK and WORKFLOW_SHA256 may be overridden for tests.
set -eu
cd "$(dirname "$0")/.."
repo=universal-market/tilori-agent
vendor=plugins/tilori/vendor
manifest=plugins/tilori/.claude-plugin/plugin.json
# The market plugin, when present, ships the same bundle and moves to the
# same version with it.
market=plugins/market/.claude-plugin/plugin.json
[ -f "$market" ] || market=
GH=${GH:-gh}
BUNDLE=${BUNDLE:-sh tools/bundle-agent.sh}
CHECK=${CHECK:-sh tests/check.sh}
# sha256 of tilori-agent's .github/workflows/release-hash.yml as last
# reviewed. When that workflow changes, review it and update this pin.
WORKFLOW_SHA256=${WORKFLOW_SHA256:-836aa43ce567e43dee2d16b1b8acd77c8ede640f36fbeffba21275427ea0bc2c}
workflow=.github/workflows/release-hash.yml

die() { echo "release: $*" >&2; exit 1; }
usage() { echo "usage: sh tools/release.sh [--finish] <agent-tag vX.Y.Z> <plugin-version X.Y.Z>" >&2; exit 2; }
semver() { printf '%s' "$1" | grep -Eq '^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$'; }
# 0 when $1 > $2, as numbers (0.1.10 > 0.1.9).
newer() {
  old_ifs=$IFS; IFS=.
  set -- $1 $2
  IFS=$old_ifs
  [ "$1" -ne "$4" ] && { [ "$1" -gt "$4" ]; return; }
  [ "$2" -ne "$5" ] && { [ "$2" -gt "$5" ]; return; }
  [ "$3" -gt "$6" ]
}

finish=
[ "${1:-}" = --finish ] && { finish=1; shift; }
[ $# -eq 2 ] || usage
tag=$1; version=$2
case "$tag" in v*) semver "${tag#v}" || usage ;; *) usage ;; esac
semver "$version" || usage
current=$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$manifest")
semver "$current" || die "can't read the current version from $manifest"
newer "$version" "$current" || die "plugin version $version is not higher than $current"
if [ -n "$market" ]; then
  mcurrent=$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$market")
  [ "$mcurrent" = "$current" ] || die "$market says ${mcurrent:-no version}, $manifest says $current; they move together"
fi
if [ -n "$(git status --porcelain)" ]; then
  [ -n "$finish" ] && die "the working tree has changes; commit plugins/tilori/vendor${market:+ and plugins/market/vendor} (and nothing else) before --finish"
  die "the working tree has changes; start from a clean branch"
fi
[ "$(git branch --show-current)" != main ] || die "on main; make a branch first"

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

echo "== 1. tag on main"
commit=$($GH api "repos/$repo/commits/refs/tags/$tag" --jq .sha)
status=$($GH api "repos/$repo/compare/main...$commit" --jq .status)
case "$status" in identical|behind) ;; *) die "$tag ($commit) is not on $repo main (compare: $status)" ;; esac
$GH api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/src/version.ts?ref=refs/tags/$tag" > "$t/version.ts"
grep -qxF "export const VERSION = '${tag#v}';" "$t/version.ts" || die "src/version.ts at $tag does not say ${tag#v}; was the tag made without a version bump?"
echo "$tag = $commit, on main, src/version.ts says ${tag#v}"

echo "== 2. release-hash run and asset"
$GH api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$workflow?ref=refs/tags/$tag" > "$t/workflow"
wsha=$(sha256sum < "$t/workflow" 2>/dev/null || shasum -a 256 < "$t/workflow")
wsha=${wsha%% *}
[ "$wsha" = "$WORKFLOW_SHA256" ] || die "$workflow at $tag hashes to $wsha, not the reviewed $WORKFLOW_SHA256; review it and update the pin"
# The tag is checked above as v + digits and dots, so it is safe inside jq.
runs=$($GH api "repos/$repo/actions/runs?head_sha=$commit&event=push" --jq "[.workflow_runs[] | select(.path == \"$workflow\" and .head_branch == \"$tag\" and .conclusion == \"success\")] | length")
[ "${runs:-0}" -ge 1 ] 2>/dev/null || die "no successful $workflow run on the $tag push at $commit"
echo "workflow is the reviewed one; its $tag run at $(printf '%.7s' "$commit") succeeded"
uploader=$($GH api "repos/$repo/releases/tags/$tag" --jq '.assets[] | select(.name == "tilori-agent.js.sha256") | .uploader.login')
[ "$uploader" = "github-actions[bot]" ] || die "tilori-agent.js.sha256 on $tag was uploaded by '${uploader:-nobody}', not github-actions[bot]"
$GH release download "$tag" -R "$repo" -p tilori-agent.js.sha256 -D "$t" >/dev/null
echo "uploaded by $uploader"

if [ -z "$finish" ]; then
  echo "== 3. bundle"
  $BUNDLE "$tag"
else
  echo "== 3. bundle: committed (--finish)"
fi

echo "== 4. SOURCE = asset"
grep -v '^#' "$vendor/SOURCE" > "$t/source"
cmp -s "$t/source" "$t/tilori-agent.js.sha256" || { diff "$t/source" "$t/tilori-agent.js.sha256" >&2 || true; die "vendor/SOURCE does not match the release asset"; }
grep -q "^commit=$commit$" "$t/source" || die "SOURCE's commit is not $commit"
sha=$(sed -n 's/^sha256=//p' "$t/source")
echo "sha256 $sha"

if [ -z "$finish" ]; then
  cat <<NEXT

release: bundle written and matches the release asset. Commit it, then finish:
  git add plugins/tilori/vendor${market:+ plugins/market/vendor} && git commit -m "Bundle tilori-agent $tag"
  sh tools/release.sh --finish $tag $version
NEXT
  exit 0
fi

echo "== 5. verify"
$BUNDLE --verify

echo "== 6. version $current -> $version"
sed "s/^  \"version\": \"$current\",\$/  \"version\": \"$version\",/" "$manifest" > "$t/plugin.json"
grep -q "^  \"version\": \"$version\",\$" "$t/plugin.json" || die "couldn't set the version in $manifest"
if [ -n "$market" ]; then
  sed "s/^  \"version\": \"$current\",\$/  \"version\": \"$version\",/" "$market" > "$t/market.json"
  grep -q "^  \"version\": \"$version\",\$" "$t/market.json" || die "couldn't set the version in $market"
fi
cat "$t/plugin.json" > "$manifest"
[ -z "$market" ] || cat "$t/market.json" > "$market"

echo "== 7. checks"
$CHECK

cat <<SUMMARY

release: ready to commit. For the PR body:
- Bundle: tilori-agent $tag at \`$(printf '%.7s' "$commit")\`, on main, with \`src/version.ts\` = ${tag#v}. \`$workflow\` at the tag is the reviewed one (sha256 \`$(printf '%.8s' "$WORKFLOW_SHA256")…\`) and its run on the tag push succeeded. \`vendor/SOURCE\` minus its comment line is identical to the release's \`tilori-agent.js.sha256\` asset (uploaded by github-actions[bot]): sha256 \`$sha\`. \`bundle-agent.sh --verify\` matches a rebuild.
- Version: plugin.json $current -> $version${market:+ (tilori and market)}.
- \`tests/check.sh\` passes (rebuild included).
SUMMARY
