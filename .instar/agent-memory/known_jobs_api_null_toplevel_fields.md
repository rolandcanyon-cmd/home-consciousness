---
name: known-jobs-api-null-toplevel-fields
description: GET /jobs returns lastRun/nextScheduled as null at the top level for EVERY job — the real values are under .state.*; a naive jq read looks like total scheduler failure
metadata: 
  node_type: memory
  type: project
  originSessionId: 5a4c6b1b-2692-4679-b1d6-2788217b15ef
  modified: 2026-07-31T07:04:39.361Z
---

`GET /jobs` returns each job with **top-level `lastRun: null` and `nextScheduled: null` for every single job**, always. Measured 2026-07-30T11:01Z: of 33 enabled jobs, `0` had a non-null top-level `lastRun`; `32` had a non-null `.state.lastRun`.

The populated values live in the per-job **`.state`** sub-object:

```
.jobs[] | {slug, lastRun: .state.lastRun, nextScheduled: .state.nextScheduled, lastResult: .state.lastResult}
```

**Why it matters:** the obvious query — `jq '.jobs[] | {slug, lastRun, nextScheduled}'` — returns a wall of nulls across all 33 jobs. That reads exactly like catastrophic scheduler failure (or like every job being wedged), and it is a false alarm every time. It also silently defeats the wedge detector in [[known_silent_cron_slot_miss]], whose whole method is comparing `nextScheduled` against now: against the top-level field the comparison can never fire, because the field is null for healthy and wedged jobs alike.

**Update (2026-07-31): reaching through `.state` is necessary but not sufficient.** `.state.nextScheduled` is echoed verbatim from the on-disk state file when present, and computed live from the cron only when the field is *absent* — so the populated value is a record of the last run, never a view of the scheduler's queue. That retires the pointer as a wedge detector regardless of which field you read; see [[known_silent_cron_slot_miss]] for the replacement test (absence of any activity-log event at the slot).

**How to apply:** when reading job state from the API, always reach through `.state`. Never conclude a job has never run, or that the scheduler is dead, from a null top-level `lastRun`. The state files at `.instar/state/jobs/<slug>.json` carry the same values and are the other valid source. This is the failure mode "Registry First" invites when the registry's shape is assumed rather than inspected — check one known-healthy job's full record before trusting a field name.

Related: [[known_silent_cron_slot_miss]], [[known_scheduler_silent_starvation]], [[known_job_config_edits_need_restart]].
