---
name: known-daily-deploy-restart-storm
description: The 14:32Z daily deploy triggers an escalating launchd crash-relaunch storm (1 to 5 to 10 restarts) that self-heals
metadata: 
  node_type: memory
  type: project
  originSessionId: ca024778-c5c6-4596-b996-66e3318c4147
  modified: 2026-08-02T19:06:03.493Z
---

At the daily deploy slot (~14:32Z / 07:32 PDT) the server crash-loops and
launchd relaunches it repeatedly. `scheduler_start` counts per day in
`.instar/logs/activity-*.jsonl`:

- 2026-07-31: 1
- 2026-08-01: 5
- 2026-08-02: 10 (all inside 14:32:15–14:36:50Z, ~4.5 min)

`KeepAlive=true` + `ThrottleInterval=10` in `ai.instar.Roland.plist` means
launchd relaunches after each exit with widening spacing (19s, 10s, 11s, 33s,
43s, 54s, 16s, 49s, 39s) until one process sticks.

**Real transient damage inside the window** — overlapping processes hit
`EADDRINUSE` on `.instar/listener.sock` (wake socket degraded), and one process
took `Threadline: relay DISPLACED by another connection using this identity`,
which disarms reconnect *for the life of that process*.

**It self-heals.** On 08-02 the surviving process reconnected the relay at
14:36:55, iMessage rewired, and 84 jobs triggered normally afterwards. But the
trend is upward, and it means a ~4.5-minute daily window where the agent is
unreliable.

**Why it matters:** prior memory expected *two* restarts here (deploy restart +
second kickstart, see [[known_low_priority_jobs_quota_shed]]). Reality is 10 —
so the deploy sequence is doing something beyond what the repair intended.

**How to apply:** track the trend with `jq 'select(.type=="scheduler_start")'`
over `.instar/logs/activity-*.jsonl` per day. If it keeps climbing, find the
crash cause first (`.instar/logs/server-launchd.err`, but see
[[feedback_launchd_log_no_timestamps]]) rather than adding another kickstart.
Related: [[known_node_pin_crash]] (NODE_MODULE_VERSION 141 vs 147 on
better-sqlite3 under `~/instar-dev/node_modules` is present in the .err).
Observed 2026-08-02 (LRN-010).
