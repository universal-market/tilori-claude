#!/bin/sh
# Prints the absolute path of the compiled tilori-agent for this machine, the
# third runtime choice in run-agent.sh after bun and node (UNI-770). The
# executable comes from the tilori-agent release that vendor/SOURCE names
# (tilori-agent-<os>-<arch>, built by its release-binaries workflow), and its
# sha256 is pinned in vendor/BINARIES, which tools/bundle-agent.sh writes and
# --verify checks against the release.
#
# - Cached in $CLAUDE_PLUGIN_DATA/bin (0700, ours), named after the tag, so a
#   plugin update fetches its own version.
# - Downloaded at most once per version over https only, redirects included
#   (curl --proto '=https' --proto-redir '=https' --tlsv1.2), into a temp
#   file in that directory. It is checked against the pin, given chmod 700,
#   then renamed into place, so a partial or wrong download is never run.
# - Hashed again on every launch: a cached file that no longer matches is
#   refused, not run (and fetched again).
# - The repo and URL are fixed here; only the tag (vX.Y.Z) and the hashes
#   come from vendor/, which ships with the plugin.
# Exits 1 with one line on stderr when anything doesn't check out. Writes
# nothing outside $CLAUDE_PLUGIN_DATA/bin. As in run-agent.sh, no external
# command runs before `cd /` and the fixed PATH.
set -u
PATH=/usr/bin:/bin
export PATH
case "$0" in
  /*) self=$0 ;;
  *) self="${PWD:-}/$0" ;;
esac
case "$self" in /*) ;; *) exit 1 ;; esac
cd / || exit 1
here=$(cd "${self%/*}" && pwd -P) || exit 1
vendor="${here%/*}/vendor"
say() { echo "tilori: $*" >&2; }
REPO=universal-market/tilori-agent
CURL=/usr/bin/curl

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) say "no tilori-agent binary for $(uname -s); install bun or node 22.18+"; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=x64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) say "no tilori-agent binary for $(uname -m); install bun or node 22.18+"; exit 1 ;;
esac
asset="tilori-agent-$os-$arch"

# The tag from SOURCE and this asset's pin from BINARIES, each exactly once
# and of the expected shape.
[ -f "$vendor/SOURCE" ] && [ -f "$vendor/BINARIES" ] \
  || { say "this plugin version pins no tilori-agent binaries; install bun or node 22.18+"; exit 1; }
[ "$(grep -c '^tag=' "$vendor/SOURCE")" = 1 ] || { say "vendor/SOURCE has no single tag line"; exit 1; }
tag=$(sed -n 's/^tag=//p' "$vendor/SOURCE")
printf '%s\n' "$tag" | grep -Eqx 'v[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}' || { say "vendor/SOURCE's tag is not vX.Y.Z"; exit 1; }
[ "$(grep -c "^$asset " "$vendor/BINARIES")" = 1 ] || { say "vendor/BINARIES pins no single $asset"; exit 1; }
want=$(sed -n "s/^$asset //p" "$vendor/BINARIES")
printf '%s\n' "$want" | grep -Eqx '[0-9a-f]{64}' || { say "vendor/BINARIES' $asset pin is not a sha256"; exit 1; }

sha256() {
  if [ -x /usr/bin/sha256sum ]; then h=$(/usr/bin/sha256sum <"$1") || return 1
  elif [ -x /usr/bin/shasum ]; then h=$(/usr/bin/shasum -a 256 <"$1") || return 1
  else return 1; fi
  echo "${h%% *}"
}
# owned <path> <mode>: ours, not a symlink, and exactly that mode.
owned() {
  [ ! -L "$1" ] && [ -O "$1" ] && [ -n "$(find "$1" -prune -perm "$2" -print 2>/dev/null)" ]
}

data=${CLAUDE_PLUGIN_DATA:-}
case "$data" in /*) ;; *) say "CLAUDE_PLUGIN_DATA is not set, so there is nowhere to keep the tilori-agent binary; install bun or node 22.18+"; exit 1 ;; esac
case "$data" in *[!A-Za-z0-9/._+@-]*) say "CLAUDE_PLUGIN_DATA has unexpected characters"; exit 1 ;; esac
umask 077
[ -L "$data" ] && { say "$data is a symlink"; exit 1; }
mkdir -p "$data" 2>/dev/null
[ -d "$data" ] && [ -O "$data" ] || { say "$data is not a directory of yours"; exit 1; }
[ -z "$(find "$data" -prune \( -perm -0020 -o -perm -0002 \) -print 2>/dev/null)" ] \
  || { say "$data is writable by other users"; exit 1; }
dir="$data/bin"
[ -e "$dir" ] || [ -L "$dir" ] || mkdir -m 700 "$dir" 2>/dev/null
[ -d "$dir" ] && owned "$dir" 700 || { say "$dir must be a directory of yours at 0700"; exit 1; }
exe="$dir/tilori-agent-$tag-$os-$arch"

if [ -f "$exe" ] && owned "$exe" 700 && [ "$(sha256 "$exe")" = "$want" ]; then
  echo "$exe"
  exit 0
fi

[ -x "$CURL" ] || { say "curl not found at $CURL, so tilori-agent can't be downloaded; install bun or node 22.18+"; exit 1; }
say "downloading tilori-agent $tag for $os-$arch (once per plugin version)"
tmp=$(mktemp "$dir/.download.XXXXXX") || { say "can't create a file in $dir"; exit 1; }
case "$tmp" in "$dir"/.download.*) ;; *) exit 1 ;; esac
if ! "$CURL" --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --max-time 600 \
  -o "$tmp" "https://github.com/$REPO/releases/download/$tag/$asset" 2>/dev/null; then
  rm -f "$tmp"
  say "couldn't download tilori-agent $tag for $os-$arch; install bun or node 22.18+, or try again"
  exit 1
fi
got=$(sha256 "$tmp") || got=
if [ "$got" != "$want" ]; then
  rm -f "$tmp"
  say "the downloaded tilori-agent $tag for $os-$arch doesn't match its pinned sha256, so it was deleted and not run"
  exit 1
fi
chmod 700 "$tmp" && mv -f "$tmp" "$exe" || { rm -f "$tmp"; say "couldn't install the binary in $dir"; exit 1; }
# Hashed once more where it will run.
[ "$(sha256 "$exe")" = "$want" ] && owned "$exe" 700 || { say "$exe changed after download; not running it"; exit 1; }
echo "$exe"
