#!/bin/sh
# The market plugin is now part of the tilori plugin (UNI-768). This stub
# ships no MCP server and no CLI; on session start it only tells the user
# so, in fixed text, and always exits 0.
printf '%s\n' '{"systemMessage":"Universal Market is now part of the tilori plugin. You can remove this one with /plugin uninstall market."}'
exit 0
