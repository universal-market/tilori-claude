#!/bin/sh
# /tilori:config: shows or changes this session's own agent's wake settings
# through `tilori-agent config` (UNI-480).
#
#   config.sh                      show
#   config.sh key=<n> [key=<n> …]  set
#   config.sh reset key [key …]    reset to the default
#   config.sh trust_server=on|off  trust every account on this server, or stop
#                                  (UNI-556; alone, and only when the user
#                                  typed it: see commands/config.md)
#
# Every argument is checked here, against the same keys and bounds as the
# CLI, before anything runs. Each one is passed on as its own argv entry,
# never through a shell string, and the CLI checks it again. There is no
# --agent: the agent is the session's own (TILORI_AGENT, then default_agent).
# Exits 2 with a usage line on anything else.
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

# usage [reason]: names what was wrong first, then the usage line.
usage() {
  [ $# -eq 0 ] || echo "tilori: $1" >&2
  echo "usage: /tilori:config [wakes_per_hour=<1-60>] [direct_wakes_per_hour=<0-30>] [reminder.every_minutes=<15-1440>] [stall_minutes=<0-1440>]  |  /tilori:config reset <key> …  |  /tilori:config trust_server=on|off" >&2
  exit 2
}

# bounds <key>: prints "min max", or fails for a key that isn't settable.
bounds() {
  case "$1" in
    wakes_per_hour) echo "1 60" ;;
    direct_wakes_per_hour) echo "0 30" ;;
    reminder.every_minutes) echo "15 1440" ;;
    stall_minutes) echo "0 1440" ;;
    *) return 1 ;;
  esac
}

if [ $# -eq 0 ] || { [ $# -eq 1 ] && [ "$1" = show ]; }; then
  exec "$here/run-agent.sh" config show
fi

# trust_server goes alone, with on or off only.
for a in "$@"; do
  case "$a" in
    trust_server=on | trust_server=off)
      [ $# -eq 1 ] || usage "trust_server=on|off goes alone"
      exec "$here/run-agent.sh" config set "$a"
      ;;
    trust_server | trust_server=*) usage "trust_server takes on or off" ;;
  esac
done

if [ "$1" = reset ]; then
  shift
  [ $# -ge 1 ] || usage
  for a in "$@"; do
    # A reminder is turned off by hand, so its interval has no reset.
    case "$a" in
      reminder.every_minutes) usage "reminder.every_minutes has no reset; turn the reminder off by hand" ;;
    esac
    bounds "$a" >/dev/null || usage "unknown key $a"
  done
  exec "$here/run-agent.sh" config reset "$@"
fi

for a in "$@"; do
  case "$a" in
    *=*) ;;
    *) usage "expected key=<number>" ;;
  esac
  key=${a%%=*}
  value=${a#*=}
  b=$(bounds "$key") || usage "unknown key $key"
  min=${b% *}
  max=${b#* }
  case "$value" in
    '' | *[!0-9]*) usage "$key needs a whole number ($min-$max)" ;;
  esac
  [ "${#value}" -le 5 ] || usage "$key=$value is out of range ($min-$max)"
  # Decimal digits only by now; strip leading zeros so test doesn't misread them.
  n=$value
  while :; do
    case "$n" in
      0?*) n=${n#0} ;;
      *) break ;;
    esac
  done
  [ "$n" -ge "$min" ] && [ "$n" -le "$max" ] || usage "$key=$value is out of range ($min-$max)"
done
exec "$here/run-agent.sh" config set "$@"
