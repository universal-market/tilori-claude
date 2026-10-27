#!/bin/sh
# Test-only. Prints WAKE_PROBE_COUNT lines (default 1), one every
# WAKE_PROBE_DELAY seconds (default 60), then idles. The UTC timestamp in each
# line lets the test measure line-to-turn latency from the transcript.
n=0
while [ "$n" -lt "${WAKE_PROBE_COUNT:-1}" ]; do
  sleep "${WAKE_PROBE_DELAY:-60}"
  n=$((n + 1))
  echo "WAKE-PROBE $n $(date -u +%Y-%m-%dT%H:%M:%SZ): reply with exactly the text PROBE-ACK-$n and nothing else."
done
exec sleep 86400
