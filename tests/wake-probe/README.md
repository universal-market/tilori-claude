# Wake probe

Answers one question: **does a plugin monitor's stdout line start a turn in an
idle interactive Claude Code session?** No Tilori is needed.

`plugin/` is a test-only plugin. Its monitor prints `WAKE-PROBE n <utc time>: reply with exactly the text PROBE-ACK-n …`
every `WAKE_PROBE_DELAY` seconds (default 60), `WAKE_PROBE_COUNT` times
(default 1), then idles.

```sh
mkdir -p work && cd work
WAKE_PROBE_DELAY=45 WAKE_PROBE_COUNT=2 claude --plugin-dir ../plugin --model haiku
# Case A: leave it untouched (no prompt yet).
# Case B: send one prompt first ("Say hello in one word."), then wait.
```

**Pass:** `● PROBE-ACK-n` appears with no user input, and the session
transcript (`~/.claude/projects/*wake-probe-work*/*.jsonl`) shows a `user`
`<task-notification>` followed by an `assistant` reply.

## Result (2026-10-27, Claude Code 2.1.310, Haiku, tmux on the dev VM): PASS

| Case | Line printed (UTC) | Notification queued | Reply |
|---|---|---|---|
| A: fresh session, no prompt | 04:13:01 | — | `PROBE-ACK` (seen in pane) |
| B1: idle after one user turn | 04:14:12 | 04:14:13.10 | 04:14:14.59 |
| B2: idle, second line | 04:14:57 | 04:14:58.10 | 04:14:59.48 |

- Each line reaches the model as `<task-notification>` inside a
  "[SYSTEM NOTIFICATION - NOT USER INPUT]" reminder. It's still model-visible
  text (the model followed the probe's instruction), which is why tilori-agent
  sends only fixed text and ids.
- The `asyncRewake` hook fallback is not needed.
