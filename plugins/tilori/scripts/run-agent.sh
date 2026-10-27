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
# Exits 127 (printing nothing on stdout) when the CLI or Bun is missing.
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

# Newer tilori-agent versions ship a shell launcher (bin/tilori-agent) that
# does the same hardening and is exec'd directly;
# older versions expose src/cli.ts directly, which needs Bun.
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
  *)
    exec "$real" "$@"
    ;;
esac
