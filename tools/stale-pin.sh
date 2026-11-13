#!/bin/sh
# Is the vendored tilori-agent behind its latest release? (UNI-881, UNI-874 step 4)
#
#   sh tools/stale-pin.sh pr|scheduled
#
# It compares the tag in plugins/tilori/vendor/SOURCE with tilori-agent's
# published releases (drafts and prereleases left out), read from the GitHub
# API without changing anything. The pin is stale when the first release
# after it came out more than 14 days ago, or when the latest release is more
# than one minor version ahead (any major bump counts) (Keel 333a7312).
#
# Exit codes (Pax 1b398fee point 4):
#   pr         always 0. A stale pin is a ::warning:: in the job, so an
#              unrelated PR, or the release bump PR itself, never goes red.
#   scheduled  1 when the pin is stale, else 0.
# Either mode treats an API or parse error as a ::warning:: and exits 0.
#
# Tests set STALE_PIN_RELEASES (a file holding the releases JSON),
# STALE_PIN_NOW (epoch seconds) and STALE_PIN_SOURCE instead of the network,
# the clock and the vendored file. In CI, GITHUB_TOKEN (read-only) raises the
# API rate limit. It goes to curl on stdin, never on its command line.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
mode=${1:-}
case "$mode" in pr | scheduled) ;; *) echo "usage: sh tools/stale-pin.sh pr|scheduled" >&2; exit 2 ;; esac

DAYS=14
MINORS=1

warn() { echo "::warning title=tilori-agent pin::$*"; exit 0; }

source=${STALE_PIN_SOURCE:-$here/../plugins/tilori/vendor/SOURCE}
[ -f "$source" ] || warn "no $source to read the pin from"
# The first line of each only (Bastion bead9cd0): SOURCE is generated, but a
# second line must not carry a newline into an annotation.
repo=$(sed -n 's/^repo=//p' "$source" | head -n1)
tag=$(sed -n 's/^tag=//p' "$source" | head -n1)
case "$repo" in */*) ;; *) warn "no repo= line in SOURCE" ;; esac
# The same anchored pattern jq uses (Pax 3859200d): a glob would let v1.2.3.4 through.
printf '%s\n' "$tag" | grep -Eqx 'v[0-9]+\.[0-9]+\.[0-9]+' || warn "SOURCE tag '$tag' is not vMAJOR.MINOR.PATCH"

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
if [ -n "${STALE_PIN_RELEASES:-}" ]; then
  cp "$STALE_PIN_RELEASES" "$t/releases.json" || warn "can't read $STALE_PIN_RELEASES"
else
  {
    if [ -n "${GITHUB_TOKEN:-}" ]; then printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN"; fi
  } | curl -fsS --max-time 30 -K - -H 'Accept: application/vnd.github+json' \
    -o "$t/releases.json" "https://api.github.com/repos/$repo/releases?per_page=100" 2>"$t/err" ||
    warn "GitHub API error reading $repo releases: $(head -c 200 "$t/err" | tr -d '\r\n')"
fi
now=${STALE_PIN_NOW:-$(date +%s)}
case "$now" in "" | *[!0-9]*) warn "bad time '$now'" ;; esac

# One line: up|stale|fresh <latest tag> <days since the first newer release> <how far ahead>
verdict=$(jq -r --arg pin "$tag" --argjson now "$now" --argjson days "$DAYS" --argjson minors "$MINORS" '
  def ver: capture("^v(?<a>[0-9]+)\\.(?<b>[0-9]+)\\.(?<c>[0-9]+)$") | [.a, .b, .c] | map(tonumber);
  if type != "array" then error("not a list of releases") else . end
  | ($pin | ver) as $p
  | [ .[] | select(.draft == false and .prerelease == false)
          | select((.tag_name | type) == "string" and (.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")))
          | {tag: .tag_name, v: (.tag_name | ver), at: (.published_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)}
          | select(.v > $p) ] as $newer
  | if ($newer | length) == 0 then "up \($pin) 0 none"
    else
      ($newer | max_by(.v)) as $l
      | ((($now - ($newer | map(.at) | min)) / 86400) | floor) as $d
      | ($l.v[0] > $p[0]) as $major
      | (if $major then "a-major-version" else "\($l.v[1] - $p[1])-minor" end) as $m
      | "\(if $d > $days or $major or ($l.v[1] - $p[1]) > $minors then "stale" else "fresh" end) \($l.tag) \($d) \($m)"
    end
' "$t/releases.json" 2>"$t/err") || warn "can't read the $repo releases: $(head -c 200 "$t/err" | tr -d '\r\n')"

[ -n "$verdict" ] || warn "no result for $tag"
set -- $verdict
state=$1 latest=$2 days=$3 ahead=$4
case "$state" in
  up) echo "tilori-agent pin $tag is the latest release." ;;
  fresh) echo "::notice title=tilori-agent pin::$tag is behind $latest (first newer release $days days ago, $ahead ahead); within the limits of $DAYS days and $MINORS minor version." ;;
  stale)
    msg="$tag is behind $latest: the first newer release came out $days days ago and the latest is $ahead ahead (limits: $DAYS days, $MINORS minor version). Bump it with tools/release.sh."
    if [ "$mode" = scheduled ]; then echo "::error title=tilori-agent pin::$msg"; exit 1; fi
    echo "::warning title=tilori-agent pin::$msg"
    ;;
  *) warn "unexpected result '$verdict'" ;;
esac
exit 0
