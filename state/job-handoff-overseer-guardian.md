# Guardian Overseer Handoff — 2026-06-27 19:00 PDT

## Summary: All guardian jobs healthy. Three persistent findings unchanged.

---

## Guardian Job Health (24h)

All 5 guardian jobs: **100% success rate, zero failures, zero skips**.

| Job | Runs | Avg Duration | Model | Cadence |
|-----|------|-------------|-------|---------|
| health-check | 288 | 23s | haiku | every 5m |
| degradation-digest | 6 | 44s | haiku | every 4h |
| session-continuity-check | 6 | 42s | haiku | every 4h |
| state-integrity-check | 4 | 74s | haiku | every 6h |
| guardian-pulse | 3 | 34s | haiku | every 8h |

Model allocation remains appropriate — all on haiku, durations well within budget.

---

## Finding 1: No Handoffs from Any Guardian Job (PERSISTENT GAP — 3rd observation)

Still zero handoff notes from any of the 5 guardian jobs. This has been noted in the prior two
overseer runs with no change. The monitoring system detects point-in-time issues but cannot
accumulate longitudinal drift information across cycles. Low urgency but a real blind spot.

---

## Finding 2: Scheduler Probe False Positive (PERSISTENT — 3rd observation)

API reports 38 jobs; jobs.json has 30. The 8 extra are built-in system jobs not in jobs.json.
This has been unchanged across all three overseer runs. The probe logic doesn't account for
instar's built-in jobs. Not a real issue — just a noisy false positive in the probe.

---

## Finding 3: monitoring.telemetry.enabled diverged-pending-restart (PERSISTENT — 3rd observation)

Same as prior two runs. A config change for telemetry is pending a server restart to take effect.
Has not been applied. Low impact but worth noting if this persists beyond 5+ runs.

---

## Update Status Change

- **Prior run**: 1.3.685 was pending/available  
- **This run**: 1.3.685 is current; **1.3.686 is now available**  
- Changes in 1.3.686: dynamic MCP live-test fixes (#1295-1297) — operator-approval tap page fix,
  config passthrough fix, and commit-before-restart fix for MCP load operations.
- Auto-updater has detected but not yet applied.

---

## Guards Summary

- on-confirmed (6): activeWorkSilenceSentinel, contextWedgeSentinel, permissionPromptAutoResolver,
  socketDisconnectSentinel, watchdog, scheduler — all core monitoring sentinels operational
- on-dry-run (1): one gate running in observe-only mode (expected)
- on-unverified (14): out-of-process guards where runtime verification isn't available
- off/dark (38): ships-dark features, expected
- diverged-pending-restart (1): monitoring.telemetry.enabled (see Finding 3)

No `off-runtime-divergent` or `errored` guards. Core sentinels all confirmed running.

---

## Attention Queue

Zero items queued. Clean.

---

## Next Overseer Focus

1. **Finding 3 persistence**: If telemetry diverged-pending-restart reaches 5+ runs, flag for
   user attention — the pending restart is not being applied.
2. **1.3.686 update**: Check if applied in next run.
3. **Guardian handoffs**: These jobs are not leaving handoff notes — likely by design but worth
   checking if the jobs have the capability. Could suggest adding handoff support if valuable.
