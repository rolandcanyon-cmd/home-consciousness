---
name: known-evolution-gate-missing-auth
description: CORRECTED 2026-07-28 — the "missing auth" diagnosis was WRONG. Evolution gates exit 1 because the result set is empty (healthy skip by design). Do not re-fix.
metadata: 
  node_type: memory
  type: project
  originSessionId: d2650805-19c6-40c5-a486-e3779ba525bf
  modified: 2026-07-28T11:03:12.283Z
---

**CORRECTED 2026-07-28 11:00Z (reflection run). The earlier "RESOLVED — missing
auth" claim was wrong on every load-bearing point.** Verified this run:

- The live built-in gate in `.instar/jobs/schedule/evolution-overdue-check.json`
  **already passes auth**, via `-H "Authorization: Bearer $INSTAR_AUTH_TOKEN"`
  (env injected by the scheduler). File mtime Jul 27 08:26 — before the current
  server start (Jul 27 17:48), so it is what the running scheduler loaded. Auth
  was never missing in the live job.
- Running the endpoint by hand WITH auth returns `{"overdue":[]}` → the gate's
  `exit(0 if len(...) > 0 else 1)` exits **1 because the queue is empty**. That
  is a **healthy skip working as designed**, not a failure.
- `git diff HEAD -- .instar/jobs.json` is **clean**, last commit Apr 25. The
  claimed 07-28 "fix applied to jobs.json" is not present as any new change.
- The claim that the server **"hot-reloaded jobs.json — no restart required"**
  is false. It contradicts the documented mechanism (job definitions load at
  SERVER START, no hot reload) *and* the sibling note written the same night,
  which states the opposite correctly.

**The trap, stated correctly this time:** a failing gate and a legitimately
skipping gate log *identically* (`job_gate_skip … exit 1 after 3 attempts`).
The previous note named that trap and then fell into it from the other side —
reading a healthy empty-queue skip as a five-week outage. The asymmetry it
asserted does not exist: exit 1 alone proves nothing in *either* direction.

**How to apply:** before "fixing" a gate, run the gate's own command by hand
with `2>/dev/null` removed and read stdout+stderr. An empty JSON list with
exit 1 is success. Only a traceback or a 401 body is a real failure. Same check
applies to `git-sync` (gate exit 1 = nothing to sync = healthy).

See [[feedback_apply_fix_dont_just_note_it]] and
[[known-job-config-edits-need-restart]].
