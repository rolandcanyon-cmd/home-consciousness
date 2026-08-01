---
name: guardian-pulse
description: Meta-monitor that checks whether other jobs are running, healthy, and not silently failing
metadata:
  user_invocable: "false"
---

# Guardian Pulse — Job Health Meta-Monitor

## Purpose

Check whether the guardians themselves are healthy. Monitors job execution, skip ledger trends, queue health, degradation reporter pipeline, and zombie sessions.

## Procedure

Read the auth token:

\`\`\`
AUTH=$(python3 -c "import json; print(json.load(open('.instar/config.json')).get('authToken',''))" 2>/dev/null)
\`\`\`

### 1. Job Health

\`\`\`
curl -s -H "Authorization: Bearer $AUTH" http://localhost:${INSTAR_PORT:-4040}/jobs
\`\`\`

**READ THE RIGHT FIELDS.** The top-level \`lastRun\`, \`nextScheduled\`, \`lastError\` and
\`consecutiveFailures\` on each job object are ALWAYS null — verified 2026-07-30, 0 of 53 jobs
populate them. The real values live under \`.state.*\`. A check written against the top-level
fields silently sees null for every job and reports "healthy" forever. Read
\`.state.lastRun\`, \`.state.nextScheduled\`, \`.state.lastResult\`, \`.state.consecutiveFailures\`.

**SPLIT GATED FROM UNGATED FIRST.** Read \`.instar/jobs.json\` and note which jobs have a \`gate\`.
A gate skip advances NEITHER \`.state.lastRun\` NOR \`.state.nextScheduled\` — so on a GATED job both
fields are expected to be stale and neither one is evidence of a stall. Verified 2026-07-30: all
5 jobs whose \`nextScheduled\` was in the past (git-sync, coherence-audit, evolution-proposal-evaluate,
evolution-proposal-implement, initiative-digest-review) were gated and healthy. Applying the
staleness rules below to a gated job manufactures 5 false positives.

For each enabled UNGATED job, check:
- Has it run at all? (\`.state.lastRun\` should exist; only \`.state.firstSeenAt\` and no lastRun,
  more than 3 cadence intervals old, means it has NEVER run)
- Is it overdue? (If \`.state.lastRun\` is more than 3x the schedule interval ago, it's stuck)
- **Is its slot wedged?** (If \`.state.nextScheduled\` is in the PAST on an UNGATED job, the
  scheduler stopped advancing its slot — the silent cron-slot-miss class, e.g.
  imessage-fork-maintenance on 07-29. It produces NO log records and NO retry exhaustion, so
  scheduler-health-notify cannot see it. CRITICAL — a server restart clears it.)
- Is it failing repeatedly? (\`.state.consecutiveFailures\` > 0 is notable, > 2 is critical)
- Is \`.state.lastError\` informative? (If it says "Session killed" repeatedly, something is wrong)

For a GATED job, the only useful check is whether the gate is stuck ALWAYS-skip — cross-reference
the skip ledger in step 2 rather than the timestamps.

Beware two more false positives: a monthly/weekly/every-N-days schedule is not overdue at 26h, and
a job that ran late after a restart is recovered, not broken. Compare against the job's OWN cadence.

**Daily-cadence jobs are the highest-loss class.** The scheduler's retry ladder is minutes long,
so a daily job shed at its slot (quota, memory pressure) loses the entire 24h — the next attempt
is tomorrow. Flag any daily job whose last run is >26h old as WARNING even if nothing errored.

**Before attributing any shed to quota, read the quota SOURCE** — it is the discriminator, and the
skip event does not record it:

\`\`\`
curl -s -H "Authorization: Bearer \$AUTH" http://localhost:\${INSTAR_PORT:-4040}/quota
\`\`\`

- \`source: "anthropic-oauth"\` → authoritative; \`priority: low\` jobs run. The stale job has some
  other cause — keep looking, do not report it as a quota shed.
- \`source: "claude-jsonl"\`, or a missing \`source\`/\`fiveHourPercent\` field → degraded; **every**
  low-priority job is refused regardless of usage. That alone explains a cluster of stale
  low-priority dailies.

Never reason from \`usagePercent\` — it does not gate low-priority jobs (verified 08-01: 48% used,
authoritative source, zero sheds). The state flips within a day, so a shed seen yesterday is not
evidence about today (LRN-008).

### 2. Skip Ledger Trends

\`\`\`
curl -s -H "Authorization: Bearer $AUTH" http://localhost:${INSTAR_PORT:-4040}/skip-ledger/workloads
\`\`\`

If any job has been skipped more than 10 times by its gate, the gate may be misconfigured (always returning skip), or the feature it monitors is permanently broken.

### 3. Queue Health

Check queueLength from the jobs endpoint. If queue is perpetually > 0, jobs are backing up. This means maxParallelJobs is too low or jobs are running too long.

### 4. Degradation Reporter Health

Read \`.instar/state/degradation-events.json\` — if events exist but none have \`reported:true\` or \`alerted:true\`, the downstream connections (FeedbackManager, Telegram) never initialized. The reporter is collecting but not communicating.

### 5. Session Monitor

\`\`\`
curl -s -H "Authorization: Bearer $AUTH" http://localhost:${INSTAR_PORT:-4040}/sessions
\`\`\`

Are there zombie sessions (status: running but started > 30 minutes ago for a job that should take 5)?

## Output

For each finding, categorize:
- **CRITICAL**: Job has been failing for > 24 hours, or meta-infrastructure (scheduler, reporter) is broken
- **WARNING**: Job overdue, skip count high, queue growing
- **INFO**: Minor observations

Report CRITICAL and WARNING issues. Exit silently if everything looks healthy.

Write handoff:

\`\`\`
echo "Pulse at $(date). Jobs checked: N. Issues: [list or 'none']." > .instar/state/job-handoff-guardian-pulse.md
\`\`\`
