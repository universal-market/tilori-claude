#!/bin/sh
# /tilori:setup [<handle>] (UNI-771): signs this machine in to Tilori and
# Universal Market through `tilori-agent setup` (tilori-agent#92).
#
# setup registers the agent, prints the claim link and returns at once; the
# plugin's monitor (`watch --notify-lines`) then waits for the owner's
# approval in the browser, stores the key with init's private writer and
# says "You're live as …". The key never reaches this session: setup prints
# only the link, and nothing here reads ~/.config/tilori.
#
# The handle is checked here against Tilori's rule (2-24 of a-z, 0-9 and
# single hyphens, starting and ending with a letter or digit) before
# anything runs, and passed on as one argv entry, never through a shell
# string; the CLI checks it again. With no handle, setup names the agent
# from the account. Exits 2 with a usage line on anything else.
#
# /tilori:setup --url <tilori-mcp-url> (UNI-818): connects this machine to
# another deployment, such as a workspace, with the agent key the user
# exported as TILORI_API_KEY in the terminal that started Claude Code. The
# key goes to `tilori-agent connect` on stdin only (never argv), and the
# variable is removed from the CLI's environment. The address is one argv
# entry of URL characters only; the CLI checks it fully (HTTPS, or HTTP for
# loopback). Never --replace: switching a home that's set up for another
# deployment is for the terminal only, and connect says how.
set -u
case "$0" in
  /*) self=$0 ;;
  *) self="${PWD:-}/$0" ;;
esac
case "$self" in
  /*) ;;
  *) echo "tilori: cannot resolve the script path ($0)" >&2; exit 127 ;;
esac
# Nothing runs from the project directory (see run-agent.sh).
cd / || exit 127
here=${self%/*}

usage() {
  echo "tilori: agent handles are 2-24 characters: a-z, 0-9 and single hyphens, starting and ending with a letter or digit." >&2
  echo "usage: /tilori:setup [<handle>]" >&2
  echo "       /tilori:setup --url <Tilori MCP address from the Connect panel>" >&2
  exit 2
}

if [ "${1:-}" = --url ]; then
  [ $# -eq 2 ] || usage
  u=$2
  LC_ALL=C
  case "$u" in
    https://?* | http://?*) ;;
    *) usage ;;
  esac
  case "$u" in
    *[!A-Za-z0-9.:/_~%-]*) usage ;;
  esac
  [ "${#u}" -le 2048 ] || usage
  key=${TILORI_API_KEY:-}
  unset TILORI_API_KEY
  if [ -z "$key" ]; then
    echo "No agent key here. Export TILORI_API_KEY in your terminal (the first line in the Connect panel), then start Claude Code again." >&2
    exit 2
  fi
  printf '%s\n' "$key" | "$here/run-agent.sh" connect --url "$u"
  exit $?
fi

[ $# -le 1 ] || usage
if [ $# -eq 0 ]; then
  exec "$here/run-agent.sh" setup
fi
h=$1
# Byte ranges, whatever the user's locale (a-z must not match capitals or
# accented letters).
LC_ALL=C
case "$h" in
  '' | -* | *- | *--* | *[!a-z0-9-]*) usage ;;
esac
[ "${#h}" -ge 2 ] && [ "${#h}" -le 24 ] || usage
exec "$here/run-agent.sh" setup "$h"
