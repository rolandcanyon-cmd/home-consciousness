---
name: known-scheduler-silent-starvation
description: Chronic memory pressure silently blocked ~24 daily jobs for over a week with zero user notification; fixed with a new detector job
metadata: 
  node_type: memory
  type: project
  originSessionId: 123b2e0e-1049-4d6f-bc07-84d5fe38b4b1
  modified: 2026-07-27T14:54:12.332Z
---

Found 2026-07-27: this Mac runs chronically at ~75-80% memory used (macOS
"available = free+inactive+purgeable" formula), which sits in instar's
`elevated` memory-pressure tier (75-90% used). At `elevated`, the scheduler
refuses to spawn ANY new job session — not just low-priority ones. When a
job exhausts its 6 retry slots (up to ~4h of backoff) it just logs
"waiting for next cron window" and gives up — no state update, no
notification, `consecutiveFailures` never increments. Result: ~24 of ~33
enabled jobs (morning-weather-report, memory-hygiene, evolution/overseer
jobs, imessage-fork-maintenance, repo-health-sweep, etc.) went 3-10+ days
without a single successful run, completely silently.

Root cause of the silence: instar's central `notify()` gateway
(`src/commands/server.ts`) only delivers via Telegram (NotificationBatcher)
or Slack — there is no iMessage branch. Worse, iMessage sends are
architecturally impossible from the server/LaunchAgent process at all
(`IMessageAdapter.send()` throws by design — "AppleScript Automation
permission does not propagate through LaunchAgent"); only a spawned
interactive Claude Code session (via `imessage-reply.sh`) can actually send.
So on an iMessage-only agent like Roland, memory-pressure/quota
warnings that `notify()` tries to raise are silent no-ops, full stop.

**Fix shipped**: `.claude/scripts/scheduler-health-check.py` + a new
`scheduler-health-notify` job (every 30 min, `execute.type: "prompt"` so it
spawns a real session that CAN send iMessage) that scans `logs/server.log`
for "exhausted N retries" lines per job slug, checks whether that job's
`state.lastRun` is still older than the exhaustion (i.e. genuinely still
stuck), checks `/quota` for elevated Claude usage, and texts a plain-English
summary — deduped to once per calendar day per issue via
`.instar/state/scheduler-health-notified.json`. Committed to the instar-dev
fork's `.claude/scripts/` (git-tracked); `.instar/jobs.json` itself is
gitignored (machine-local state) so the job entry lives only in this
agent's own jobs.json, not in git.

**Why:** [[feedback_build_deploy]] establishes this agent's daily-job
maintenance pattern; this closes a real silent-failure gap the user hit
directly ("not seeing the daily weather report for the last few days").
User confirmed 2026-07-27: "Yes, and always report when the limit is hit."

**How to apply:** If future reports of "job X hasn't run" come up, check
`logs/server.log` for `[scheduler] Job "X" exhausted` lines and
`/jobs` state.lastRun BEFORE assuming a code bug in the job itself — it's
very likely the same memory-pressure starvation, not the job. Also worth
knowing: `MemoryPressureMonitor` thresholds (warning=60/elevated=75/
critical=90% used) are hardcoded in `server.ts` with no config.json
override wired in yet — raising `elevated` (e.g. to 85%) would let more
jobs actually run on this chronically-busy shared Mac, but that's a
deliberate safety-threshold change that needs the user's explicit sign-off,
not something to silently tune.
