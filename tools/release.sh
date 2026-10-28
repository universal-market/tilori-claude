#!/bin/sh
# Prepares a plugin release that bundles a tilori-agent tag, locally, and
# stops at the first thing that doesn't match:
#
#   sh tools/release.sh v0.1.11 0.1.15
#
#   1. the tag's commit is on tilori-agent main;
#   2. the release's tilori-agent.js.sha256 asset was uploaded by
#      github-actions[bot] (the release-hash workflow, not a person);
#   3. tools/bundle-agent.sh <tag> rebuilds vendor/;
#   4. vendor/SOURCE, without its comment line, equals that asset;
#   5. tools/bundle-agent.sh --verify;
#   6. plugin.json gets <plugin-version>, which must be higher;
#   7. the full tests/check.sh (no skips).
# Then it prints a summary for the PR. It never commits, pushes, tags,
# comments or opens a PR: that stays with the author and the lead.
# GH, BUNDLE and CHECK may be overridden for tests.
set -eu
cd "$(dirname "$0")/.."
repo=universal-market/tilori-agent
vendor=plugins/tilori/vendor
manifest=plugins/tilori/.claude-plugin/plugin.json
GH=${GH:-gh}
BUNDLE=${BUNDLE:-sh tools/bundle-agent.sh}
CHECK=${CHECK:-sh tests/check.sh}

die() { echo "release: $*" >&2; exit 1; }
usage() { echo "usage: sh tools/release.sh <agent-tag vX.Y.Z> <plugin-version X.Y.Z>" >&2; exit 2; }
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

[ $# -eq 2 ] || usage
tag=$1; version=$2
case "$tag" in v*) semver "${tag#v}" || usage ;; *) usage ;; esac
semver "$version" || usage
current=$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$manifest")
semver "$current" || die "can't read the current version from $manifest"
newer "$version" "$current" || die "plugin version $version is not higher than $current"
[ -z "$(git status --porcelain)" ] || die "the working tree has changes; start from a clean branch"
[ "$(git branch --show-current)" != main ] || die "on main; make a branch first"

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

echo "== 1. tag on main"
commit=$($GH api "repos/$repo/commits/$tag" --jq .sha)
status=$($GH api "repos/$repo/compare/main...$commit" --jq .status)
case "$status" in identical|behind) ;; *) die "$tag ($commit) is not on $repo main (compare: $status)" ;; esac
echo "$tag = $commit, on main"

echo "== 2. release asset"
uploader=$($GH api "repos/$repo/releases/tags/$tag" --jq '.assets[] | select(.name == "tilori-agent.js.sha256") | .uploader.login')
[ "$uploader" = "github-actions[bot]" ] || die "tilori-agent.js.sha256 on $tag was uploaded by '${uploader:-nobody}', not github-actions[bot]"
$GH release download "$tag" -R "$repo" -p tilori-agent.js.sha256 -D "$t" >/dev/null
echo "uploaded by $uploader"

echo "== 3. bundle"
$BUNDLE "$tag"

echo "== 4. SOURCE = asset"
grep -v '^#' "$vendor/SOURCE" > "$t/source"
cmp -s "$t/source" "$t/tilori-agent.js.sha256" || { diff "$t/source" "$t/tilori-agent.js.sha256" >&2 || true; die "vendor/SOURCE does not match the release asset"; }
grep -q "^commit=$commit$" "$t/source" || die "SOURCE's commit is not $commit"
sha=$(sed -n 's/^sha256=//p' "$t/source")
echo "sha256 $sha"

echo "== 5. verify"
$BUNDLE --verify

echo "== 6. version $current -> $version"
sed "s/^  \"version\": \"$current\",\$/  \"version\": \"$version\",/" "$manifest" > "$t/plugin.json"
grep -q "^  \"version\": \"$version\",\$" "$t/plugin.json" || die "couldn't set the version in $manifest"
cat "$t/plugin.json" > "$manifest"

echo "== 7. checks"
$CHECK

cat <<SUMMARY

release: ready to commit. For the PR body:
- Bundle: tilori-agent $tag at \`$(printf '%.7s' "$commit")\`, on main. \`vendor/SOURCE\` minus its comment line is identical to the release's \`tilori-agent.js.sha256\` asset (uploaded by github-actions[bot]): sha256 \`$sha\`. \`bundle-agent.sh --verify\` matches a rebuild.
- Version: plugin.json $current -> $version.
- \`tests/check.sh\` passes (rebuild included).
SUMMARY
