#!/bin/sh
# tools/stale-pin.sh against fixed releases and a fixed clock, with no network:
# pr mode never fails, scheduled mode fails only past the limits (14 days, one
# minor version, any major), and bad input is a warning that exits 0.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
tool="$here/../tools/stale-pin.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

DAY=86400
NOW=1800000000 # a fixed "now"
at() { jq -nr --argjson s "$1" '$s | todate'; } # epoch → 2027-01-15T08:00:00Z

# rel <tag> <days before NOW> [draft] [prerelease]
rel() { printf '{"tag_name":"%s","published_at":"%s","draft":%s,"prerelease":%s}' "$1" "$(at $((NOW - $2 * DAY)))" "${3:-false}" "${4:-false}"; }
releases() { printf '['; sep=; for r in "$@"; do printf '%s%s' "$sep" "$r"; sep=,; done; printf ']\n'; }
pin() { printf '# Generated\nrepo=universal-market/tilori-agent\ntag=%s\ncommit=x\nbun=1.4.3\nsha256=y\n' "$1" > "$t/SOURCE"; }

# run <mode> <want exit> <want text> : runs with $t/rel.json and $t/SOURCE
run() {
  set +e
  STALE_PIN_RELEASES=$t/rel.json STALE_PIN_NOW=$NOW STALE_PIN_SOURCE=$t/SOURCE sh "$tool" "$1" > "$t/out" 2>&1
  rc=$?
  set -e
  [ "$rc" -eq "$2" ] || fail "$1: exit $rc, want $2: $(cat "$t/out")"
  grep -qF -- "$3" "$t/out" || fail "$1: want '$3' in: $(cat "$t/out")"
}

# Up to date.
pin v0.1.37
releases "$(rel v0.1.37 3)" "$(rel v0.1.36 4)" > "$t/rel.json"
run pr 0 "pin v0.1.37 is the latest release"
run scheduled 0 "pin v0.1.37 is the latest release"

# Pin newer than any release (a bump PR before its release is out): fine.
pin v0.1.38
run scheduled 0 "pin v0.1.38 is the latest release"

# Behind, within limits: a notice, never a failure.
pin v0.1.36
releases "$(rel v0.1.37 10)" "$(rel v0.1.36 20)" > "$t/rel.json"
run pr 0 "::notice title=tilori-agent pin::v0.1.36 is behind v0.1.37 (first newer release 10 days ago, 0-minor ahead)"
run scheduled 0 "::notice"

# Exactly 14 days is within the limit; 15 is past it. The clock counts from the
# FIRST release after the pin, not the latest.
releases "$(rel v0.1.38 1)" "$(rel v0.1.37 14)" "$(rel v0.1.36 30)" > "$t/rel.json"
run scheduled 0 "::notice title=tilori-agent pin::v0.1.36 is behind v0.1.38 (first newer release 14 days ago"
releases "$(rel v0.1.38 1)" "$(rel v0.1.37 15)" "$(rel v0.1.36 30)" > "$t/rel.json"
run pr 0 "::warning title=tilori-agent pin::v0.1.36 is behind v0.1.38: the first newer release came out 15 days ago"
run scheduled 1 "::error title=tilori-agent pin::v0.1.36 is behind v0.1.38"

# One minor ahead is within the limit; two is past it, even on day 0.
pin v0.1.37
releases "$(rel v0.2.0 0)" > "$t/rel.json"
run scheduled 0 "1-minor ahead"
releases "$(rel v0.3.0 0)" "$(rel v0.2.0 0)" > "$t/rel.json"
run scheduled 1 "2-minor ahead"
run pr 0 "::warning"

# Any major bump is stale.
releases "$(rel v1.0.0 0)" > "$t/rel.json"
run scheduled 1 "a-major-version ahead"

# Drafts, prereleases and odd tags don't count.
releases "$(rel v0.9.0 60 true)" "$(rel v0.8.0 60 false true)" "$(rel nightly 60)" "$(rel v0.1.99-rc1 60)" "$(rel v0.1.37 5)" > "$t/rel.json"
run scheduled 0 "pin v0.1.37 is the latest release"

# Versions compare as numbers, not text: v0.1.10 is after v0.1.9.
pin v0.1.9
releases "$(rel v0.1.10 30)" > "$t/rel.json"
run scheduled 1 "v0.1.9 is behind v0.1.10"

# Fractional seconds in published_at parse.
pin v0.1.36
printf '[{"tag_name":"v0.1.37","published_at":"%s","draft":false,"prerelease":false}]\n' "$(at $((NOW - 20 * DAY)) | sed 's/Z$/.123Z/')" > "$t/rel.json"
run scheduled 1 "20 days ago"

# Errors are warnings in both modes: not JSON, not a list, an API error body.
echo 'not json' > "$t/rel.json"
run scheduled 0 "::warning title=tilori-agent pin::can't read"
echo '{"message":"API rate limit exceeded"}' > "$t/rel.json"
run scheduled 0 "::warning title=tilori-agent pin::can't read"
run pr 0 "::warning"
# ... a missing releases file, a bad SOURCE tag, a missing SOURCE.
rm -f "$t/rel.json"
run scheduled 0 "::warning title=tilori-agent pin::can't read"
echo '[]' > "$t/rel.json"
pin main
run scheduled 0 "is not vMAJOR.MINOR.PATCH"
rm -f "$t/SOURCE"
run scheduled 0 "::warning title=tilori-agent pin::no "

# Usage.
set +e; sh "$tool" > /dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 2 ] || fail "no mode: exit $rc, want 2"

# The token never reaches curl's command line: check the source, since a
# stubbed curl would only prove the stub.
grep -n 'GITHUB_TOKEN' "$tool" | grep -v '^[0-9]*:#' | grep -qv 'printf' && fail "GITHUB_TOKEN used outside the stdin config line"

echo "stale pin ok"
