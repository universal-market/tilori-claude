#!/bin/sh
# Plugin monitor: every stdout line becomes a notification that wakes the
# session, so only tilori-agent's fixed wake lines go to stdout. Diagnostics
# go to stderr. If tilori-agent, Bun or the agent's key is missing, it exits
# without printing anything on stdout.
# ${0%/*}, not dirname: no external command runs from the project directory.
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac

# The plugin version this session runs, read with shell builtins only, plus
# Claude Code's install record: tilori-agent compares the two and says once
# in a wake line when a newer plugin is installed. These are environment
# variables, not flags, so an older tilori-agent just ignores them.
manifest="$here/../.claude-plugin/plugin.json"
version=
if [ -r "$manifest" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'"version"'*) version=${line#*'"version"'}; version=${version#*'"'}; version=${version%%'"'*}; break ;;
    esac
  done < "$manifest"
fi
case "$version" in
  *[!0-9.]* | '') unset TILORI_PLUGIN_VERSION TILORI_PLUGIN_MANIFEST TILORI_PLUGIN_KEY ;;
  *)
    TILORI_PLUGIN_VERSION=$version
    TILORI_PLUGIN_MANIFEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
    TILORI_PLUGIN_KEY=universal-market@tilori-claude
    export TILORI_PLUGIN_VERSION TILORI_PLUGIN_MANIFEST TILORI_PLUGIN_KEY
    ;;
esac
exec "$here/run-agent.sh" watch --notify-lines
