---
name: known-cron-evaluated-in-local-time
description: "Instar job cron expressions fire in LOCAL time (PDT = UTC-7) while every log and API timestamp is UTC — the frame mismatch behind repeated false \"job wedged\" diagnoses; convert before judging any slot"
metadata: 
  node_type: memory
  type: project
  originSessionId: 12c712af-f377-4636-9f4e-53de01fb2180
  modified: 2026-08-01T11:03:01.055Z
---

Every enabled job's `state.nextScheduled` equals its cron hour **plus 7** (PDT offset), confirmed
across the whole job table on 2026-08-01T11:00Z:

| cron | nextScheduled (UTC) | local |
|---|---|---|
| `0 7 * * *` | 14:00Z | 07:00 PDT |
| `5 6 * * *` | 13:05Z | 06:05 PDT |
| `0 */6 * * *` | 13:00Z | 06:00 PDT |
| `0 */4 * * *` | 15:00Z | 08:00 PDT |
| `0 6 */3 * *` | 13:00Z | 06:00 PDT |
| `0 8 1 * *` | 15:00Z | 08:00 PDT |

**Why it matters:** activity logs, `logs/server.log`, and every API timestamp are UTC. Reading a
cron hour as if it were UTC puts the expected slot **7 hours early**, so a perfectly healthy job
looks like it "missed its slot with zero records" — which is exactly the signature of the wedge
class in [[known_silent_cron_slot_miss]]. At least four separate wedge investigations were built
on slot instants computed in the wrong frame. This also confirms (no longer "suspected") the
local-vs-UTC hypothesis that note raised about `capability-audit` firing at 13:00Z on `0 6 */3 * *`.

**How to apply:** before claiming any job missed a slot, convert its cron hour to UTC by adding
the current local offset (+7 PDT / +8 PST — and note that flip at DST changes every slot's UTC
instant). Then check the activity log at *that* instant. Do not compare a cron hour directly to a
UTC clock. When in doubt, read `state.nextScheduled` from a job that just ran successfully — it is
the scheduler's own answer in UTC and settles the frame with no arithmetic.

Related: [[known_silent_cron_slot_miss]], [[known_jobs_api_null_toplevel_fields]],
[[known_low_priority_jobs_quota_shed]].
