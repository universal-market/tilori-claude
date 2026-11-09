#!/bin/sh
# key-header.sh (UNI-769): the no-runtime key release. It prints the header
# only on an exact headers.allow match with private files; on anything else it
# prints nothing, exits 1, and the helpers fall back to tilori-agent.
set -eu
case "$0" in */*) here=${0%/*} ;; *) here=. ;; esac
repo=$(cd "$here/.." && pwd -P)
scripts="$repo/plugins/tilori/scripts"
t=$(mktemp -d); trap 'chmod -R u+rwx "$t" 2>/dev/null; rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

KEY='mcp_sk_fake.Key-123~+/='
OTHER='mcp_sk_other_agent'
URL='https://tilori.example/mcp/tilori/v1'
MARKET='https://market.example/mcp/v1'
h="$t/home"
th="$h/.config/tilori"

# A home laid out as tilori-agent writes it.
fresh() {
  chmod -R u+rwx "$t" 2>/dev/null || true
  rm -rf "$h"; mkdir -p "$th/agents"
  chmod 700 "$h" "$h/.config" "$th" "$th/agents"
  printf '{"url":"%s","market_url":"%s","default_agent":"wren"}\n' "$URL" "$MARKET" >"$th/config.json"
  printf '%s\n' "$KEY" >"$th/agents/wren.key"
  printf '%s\n' "$OTHER" >"$th/agents/keel.key"
  # One second older, so the newer-than check isn't decided by mtime ties.
  touch -t 202601010000 "$th/config.json"
  {
    echo 'default wren'
    echo "keel $URL"
    echo "wren $URL"
    echo "wren $MARKET"
  } >"$th/headers.allow"
  chmod 600 "$th/config.json" "$th/headers.allow" "$th/agents/wren.key" "$th/agents/keel.key"
}

# run [VAR=value ...]: key-header.sh from /, in a clean environment.
run() {
  (cd / && env -i HOME="$h" PATH=/usr/bin:/bin CLAUDE_CODE_MCP_SERVER_URL="$URL" "$@" /bin/sh "$scripts/key-header.sh" >"$t/out" 2>"$t/err")
}
released() { # <what> <key> [VAR=value ...]
  what=$1; want=$2; shift 2
  run "$@" || fail "$what: refused"
  [ "$(cat "$t/out")" = "{\"Authorization\":\"Bearer $want\"}" ] || fail "$what: printed $(cat "$t/out")"
  [ ! -s "$t/err" ] || fail "$what: wrote to stderr"
}
refused() { # <what> [VAR=value ...]
  what=$1; shift
  if run "$@"; then fail "$what: released"; fi
  [ ! -s "$t/out" ] || fail "$what: printed on stdout"
  [ ! -s "$t/err" ] || fail "$what: wrote to stderr"
}

# Matches.
fresh
released "default agent, Tilori URL" "$KEY"
released "default agent, Market URL" "$KEY" CLAUDE_CODE_MCP_SERVER_URL="$MARKET"
released "TILORI_AGENT" "$OTHER" TILORI_AGENT=keel
released "TILORI_HOME naming the default home" "$KEY" TILORI_HOME="$th"

# The URL must match a line exactly, for this agent.
fresh
refused "no server URL" CLAUDE_CODE_MCP_SERVER_URL=
refused "another host" CLAUDE_CODE_MCP_SERVER_URL=https://evil.example/mcp/tilori/v1
refused "same host, another path" CLAUDE_CODE_MCP_SERVER_URL=https://tilori.example/mcp/v1
refused "a trailing slash (tilori-agent decides)" CLAUDE_CODE_MCP_SERVER_URL="$URL/"
refused "a prefix of the URL" CLAUDE_CODE_MCP_SERVER_URL=https://tilori.example/mcp
refused "the URL plus a query" CLAUDE_CODE_MCP_SERVER_URL="$URL?x=1"
refused "the URL with a space" CLAUDE_CODE_MCP_SERVER_URL="$URL x"
refused "not http(s)" CLAUDE_CODE_MCP_SERVER_URL=file:///etc/passwd
refused "Market URL for an agent without that line" TILORI_AGENT=keel CLAUDE_CODE_MCP_SERVER_URL="$MARKET"
refused "an agent with no lines" TILORI_AGENT=lark
refused "another TILORI_HOME" TILORI_HOME="$t/elsewhere"
refused "no HOME" HOME=

# Handles with shell metacharacters or path parts never reach a path or a command.
for bad in 'wren;touch$IFS/tmp/x' '../wren' 'wren/../keel' '$(id)' 'Wren' '-wren' '_wren' 'wren keel' "$(printf 'wren\nkeel')" '*' 'wr?n'; do
  refused "handle '$bad'" TILORI_AGENT="$bad"
done
# Leading "-" or "_" is refused even with a key file and a line for it.
for bad in -wren _wren; do
  fresh
  printf '%s\n' "$KEY" >"$th/agents/$bad.key"; chmod 600 "$th/agents/$bad.key"
  echo "$bad $URL" >>"$th/headers.allow"
  refused "handle '$bad' with a key and a line" TILORI_AGENT="$bad"
done
fresh
long=$(printf 'a%.0s' $(seq 1 65))
printf '%s\n' "$KEY" >"$th/agents/$long.key"; chmod 600 "$th/agents/$long.key"
echo "$long $URL" >>"$th/headers.allow"
refused "a 65-character handle" TILORI_AGENT="$long"
fresh
printf 'default ../wren\nwren %s\n' "$URL" >"$th/headers.allow"
refused "a default line with a path"
printf 'default $(id)\n' >"$th/headers.allow"
refused "a default line with a command"
printf 'wren %s\n' "$URL" >"$th/headers.allow"
refused "no default line and no TILORI_AGENT"
printf 'default wren\nwren %s extra\n' "$URL" >"$th/headers.allow"
refused "a line with a third field"

# An agent named "default" has URL lines; the default line names a handle.
fresh
printf '%s\n' "$OTHER" >"$th/agents/default.key"; chmod 600 "$th/agents/default.key"
printf 'default %s\ndefault wren\nwren %s\n' "$URL" "$URL" >"$th/headers.allow"
released "an agent named default" "$OTHER" TILORI_AGENT=default
released "the default line beside an agent named default" "$KEY"

# Private files only: modes, symlinks, types.
for f in headers.allow config.json agents/wren.key; do
  fresh; chmod 644 "$th/$f"; refused "$f at 0644"
  fresh; chmod 640 "$th/$f"; refused "$f at 0640"
  fresh; chmod 400 "$th/$f"; refused "$f at 0400 (tilori-agent decides)"
  fresh; mv "$th/$f" "$t/real"; ln -s "$t/real" "$th/$f"; refused "$f as a symlink"; rm -f "$t/real"
  fresh; rm "$th/$f"; refused "$f missing"
  fresh; rm "$th/$f"; mkdir -m 700 "$th/$f"; refused "$f as a directory"
done
fresh; chmod 755 "$th"; refused "the home at 0755"
fresh; chmod 750 "$th/agents"; refused "agents at 0750"
fresh; mv "$th/agents" "$t/agents"; ln -s "$t/agents" "$th/agents"; refused "agents as a symlink"; rm -rf "$t/agents"
fresh; mv "$th" "$t/th"; ln -s "$t/th" "$th"; refused "the home as a symlink"; rm -rf "$t/th"
# A file owned by another user can't be made here without root; the owner
# check is the same find call as the mode check (-user <uid> -perm <mode>).

# A config.json edited by hand after tilori-agent wrote the sidecar.
fresh; touch "$th/config.json"; touch -t 202601010000 "$th/headers.allow"
refused "config.json newer than headers.allow"

# Keys exactly as init writes them.
for bad in "mcp_sk with space" 'mcp_sk_"quote' 'mcp_sk_\back' 'mcp_sk_{x}' ''; do
  fresh; printf '%s\n' "$bad" >"$th/agents/wren.key"; refused "key '$bad'"
done
fresh; printf '%s' "$KEY" >"$th/agents/wren.key"; refused "a key with no newline (tilori-agent decides)"
fresh; printf '%s\n\n' "$KEY" >"$th/agents/wren.key"; refused "a key with a second line"
fresh; printf '%s\nmore\n' "$KEY" >"$th/agents/wren.key"; refused "a key file with more text"
fresh; printf '%s\r\n' "$KEY" >"$th/agents/wren.key"; refused "a key with CRLF"

# A project directory (or anything else on the caller's PATH) can't supply
# its own find, id or wc. ([ -L ] and the whitespace check on the URL back up
# find -prune, which never follows a symlink, and the exact line match; no
# test can tell them apart from those.)
fresh
mkdir -p "$t/proj"
for c in find id wc; do
  printf '#!/bin/sh\necho pwned >>"%s/pwned"\necho 0\n' "$t" >"$t/proj/$c"; chmod +x "$t/proj/$c"
done
(cd "$t/proj" && env -i HOME="$h" PATH="$t/proj:.:/usr/bin:/bin" CLAUDE_CODE_MCP_SERVER_URL="$URL" /bin/sh "$scripts/key-header.sh" >"$t/out" 2>"$t/err") || fail "hostile cwd: refused"
[ "$(cat "$t/out")" = "{\"Authorization\":\"Bearer $KEY\"}" ] || fail "hostile cwd: $(cat "$t/out")"
[ ! -e "$t/pwned" ] || fail "hostile cwd: a project command ran"

# Through both helpers, with no runtime at all: run-agent.sh is a stub that
# fails, so the key can only come from key-header.sh.
fresh
mkdir -p "$t/s"; cp "$scripts/headers.sh" "$scripts/market-headers.sh" "$scripts/key-header.sh" "$t/s/"
printf '#!/bin/sh\necho "{\\"Authorization\\":\\"Bearer from-cli\\"}"\n' >"$t/s/run-agent.sh"
printf '#!/bin/sh\nexit 127\n' >"$t/s/run-agent.sh"
chmod +x "$t/s/"*.sh
for pair in "headers.sh $URL" "market-headers.sh $MARKET"; do
  s=${pair%% *}; u=${pair#* }
  out=$(cd / && env -i HOME="$h" PATH=/usr/bin:/bin CLAUDE_CODE_MCP_SERVER_URL="$u" "$t/s/$s" 2>"$t/err") || fail "$s exited non-zero"
  [ "$out" = "{\"Authorization\":\"Bearer $KEY\"}" ] || fail "$s without a runtime: $out"
  [ ! -s "$t/err" ] || fail "$s wrote to stderr: $(cat "$t/err")"
done
# Refused by key-header.sh: the helper asks run-agent.sh, and its answer stands.
printf '#!/bin/sh\necho "{\\"Authorization\\":\\"Bearer from-cli\\"}"\n' >"$t/s/run-agent.sh"
out=$(cd / && env -i HOME="$h" PATH=/usr/bin:/bin CLAUDE_CODE_MCP_SERVER_URL="$URL/" "$t/s/headers.sh" 2>/dev/null)
[ "$out" = '{"Authorization":"Bearer from-cli"}' ] || fail "fallback to tilori-agent: $out"
printf '#!/bin/sh\nexit 1\n' >"$t/s/run-agent.sh"
out=$(cd / && env -i HOME="$h" PATH=/usr/bin:/bin CLAUDE_CODE_MCP_SERVER_URL=https://evil.example/mcp/v1 "$t/s/market-headers.sh" 2>/dev/null)
[ "$out" = '{"Authorization":"Bearer tilori-no-agent-key"}' ] || fail "both refused: $out"
# A third origin (UNI-818): a home set up for one deployment's Tilori and
# Market gives any other server only the placeholder, through either helper,
# for every agent here. Never the key.
for s in headers.sh market-headers.sh; do
  for u in https://evil.example/mcp/tilori/v1 https://evil.example/mcp/v1 https://tilori.example.evil.example/mcp/tilori/v1 http://tilori.example/mcp/tilori/v1; do
    for a in '' keel; do
      out=$(cd / && env -i HOME="$h" PATH=/usr/bin:/bin ${a:+TILORI_AGENT=$a} CLAUDE_CODE_MCP_SERVER_URL="$u" "$t/s/$s" 2>"$t/err") || fail "$s, $u: exited non-zero"
      [ "$out" = '{"Authorization":"Bearer tilori-no-agent-key"}' ] || fail "$s, $u, agent '${a:-default}': $out"
      ! grep -qF -e "$KEY" -e "$OTHER" "$t/err" || fail "$s, $u: a key on stderr"
    done
  done
done
echo "key-header: ok"
