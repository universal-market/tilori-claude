#!/bin/sh
# Runs tilori-agent with the given arguments, safely, from whatever directory
# Claude Code starts it in (usually the project being worked on).
#
# Bun reads bunfig.toml (including `preload` scripts), tsconfig.json and .env
# from the *current directory*. An opened repository could therefore run code
# inside `tilori-agent headers` or redirect TILORI_HOME / TILORI_AGENT /
# TILORI_URL / TILORI_SOCKET. So we:
#   - cd / before starting Bun (no project bunfig.toml, tsconfig.json or .env);
#   - pass --no-env-file to Bun as well;
#   - accept only absolute paths for the CLI and for bun (never ./bun via a
#     "." or empty PATH entry).
# The bundled CLI (vendor/tilori-agent.js) runs under the first of
# (UNI-770):
#   1. bun, as before;
#   2. node 22.18 or later (the first with both import.meta.main and ESM
#      detection without a flag), with NODE_OPTIONS and NODE_PATH cleared,
#      since either could load other code;
#   3. the compiled tilori-agent-<os>-<arch> from the same tilori-agent
#      release, pinned by sha256 in vendor/BINARIES (see fetch-agent.sh).
# Never a tilori-agent found on PATH in its place.
# Exits 127 (printing nothing on stdout) when the CLI or every runtime is
# missing.
#
# No external command may run before `cd /`: with a "." or empty PATH entry a
# project-local ./dirname or ./readlink would run first. So $0 is made
# absolute with shell-only expansions ($PWD, ${0%/*}) and we cd / first.
set -u
case "$0" in
  /*) self=$0 ;;
  *) self="${PWD:-}/$0" ;;
esac
case "$self" in
  /*) ;;
  *) echo "tilori: cannot resolve the script path ($0)" >&2; exit 127 ;;
esac
# The caller's directory, for `tilori-agent claude`, which starts Claude Code
# there rather than in / (UNI-795). Shell-only, like the lines above; the CLI
# uses it only when it is an existing absolute directory.
case "${PWD:-}" in
  /*) TILORI_LAUNCH_CWD=$PWD; export TILORI_LAUNCH_CWD ;;
  *) unset TILORI_LAUNCH_CWD ;;
esac
cd / || exit 127
here=$(cd "${self%/*}" && pwd -P) || exit 127
bin=$("$here/find-agent.sh") || exit 127

find_bun() {
  old_ifs=$IFS; IFS=:
  for d in $PATH; do
    case "$d" in
      /*) if [ -x "$d/bun" ] && [ ! -d "$d/bun" ]; then IFS=$old_ifs; echo "$d/bun"; return 0; fi ;;
    esac
  done
  IFS=$old_ifs
  for d in "${BUN_INSTALL:-}" "$HOME/.bun"; do
    case "$d" in
      /*) if [ -x "$d/bin/bun" ]; then echo "$d/bin/bun"; return 0; fi ;;
    esac
  done
  return 1
}

# node 22.18 or later, by absolute path; NODE_OPTIONS is cleared for the
# version check too.
find_node() {
  old_ifs=$IFS; IFS=:
  for d in $PATH; do
    case "$d" in
      /*) if [ -x "$d/node" ] && [ ! -d "$d/node" ]; then
            IFS=$old_ifs
            v=$(env -u NODE_OPTIONS -u NODE_PATH "$d/node" --version 2>/dev/null) || v=
            if node_ok "$v"; then echo "$d/node"; return 0; fi
            IFS=:
          fi ;;
    esac
  done
  IFS=$old_ifs
  return 1
}
# node_ok v22.18.0: 0 for 22.18 or later.
node_ok() {
  v=${1#v}
  major=${v%%.*}; rest=${v#*.}; minor=${rest%%.*}
  case "$major$minor" in '' | *[!0-9]*) return 1 ;; esac
  [ "$major" -gt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -ge 18 ]; }
}

# The bundled CLI (vendor/tilori-agent.js) and older tilori-agent installs
# (src/cli.ts) run under Bun with --no-env-file, from /. Newer installs ship a
# shell launcher (bin/tilori-agent) that does the same hardening and is
# exec'd directly.
# Follow symlinks one hop at a time with plain readlink (older macOS has no
# readlink -f), from / and on absolute paths only. bun link installs the CLI
# as a relative symlink.
real=$bin
n=0
while [ -L "$real" ]; do
  n=$((n + 1)); [ "$n" -le 40 ] || { echo "tilori: symlink loop at $bin" >&2; exit 127; }
  link=$(readlink "$real") || break
  case "$link" in
    /*) real=$link ;;
    *) real="${real%/*}/$link" ;;
  esac
done
case "$real" in
  *.ts)
    bun=$(find_bun) || { echo "tilori: bun not found (install Bun or put it on PATH)" >&2; exit 127; }
    exec "$bun" --no-env-file "$real" "$@"
    ;;
  *.js)
    if bun=$(find_bun); then exec "$bun" --no-env-file "$real" "$@"; fi
    if node=$(find_node); then
      unset NODE_OPTIONS NODE_PATH
      exec "$node" "$real" "$@"
    fi
    # Only the bundle this plugin ships has pinned binaries.
    if [ "$real" = "${here%/*}/vendor/tilori-agent.js" ]; then
      exe=$(/bin/sh "$here/fetch-agent.sh") || exit 127
      exec "$exe" "$@"
    fi
    echo "tilori: neither bun nor node 22.18+ found (install one, or put it on PATH)" >&2
    exit 127
    ;;
  *)
    exec "$real" "$@"
    ;;
esac
