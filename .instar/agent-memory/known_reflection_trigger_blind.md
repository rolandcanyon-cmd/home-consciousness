---
name: known-reflection-trigger-blind
description: "reflection-trigger job's activity jq doesn't compile — its RECENT ACTIVITY block has always been empty; filed upstream fb-bc396333-94b"
metadata: 
  node_type: memory
  type: project
  originSessionId: e48d24ed-ef8a-4f45-9578-f264537b9e89
  modified: 2026-08-03T11:02:42.796Z
---

The built-in `reflection-trigger` job (`.instar/jobs/instar/reflection-trigger.md:25`) builds its
"RECENT ACTIVITY (Last 4 Hours)" block with a jq filter that **does not compile**:

- interpolation missing backslashes — `"(.timestamp) [(.type)]"` should be `"\(.timestamp) [\(.type)]"`
- field names don't exist — activity JSONL is `{type, summary, sessionId, timestamp, metadata:{slug}}`;
  `.message`/`.title`/`.session_name`/`.slug` all resolve to null. Real fields: `.summary`, `.metadata.slug`
- noise filter excludes `job-start`/`job-queued` (hyphens); real types are `job_triggered`/`job_gate_skip`

A trailing `2>/dev/null` swallows the compile error, so the job prints the header and nothing —
**indistinguishable from a genuinely quiet 4 hours.** Every run has reflected on zero data.

**Do not fix locally** — built-in job markdown is regenerated from the shipped template on every
update, so the edit is silently reverted. Filed upstream: **fb-bc396333-94b** (2026-08-03).

**To actually reflect, extract activity yourself:**
```
tail -600 .instar/logs/activity-$(date -u +%F).jsonl | jq -r 'select(.timestamp >= "<ISO>") | "\(.timestamp[11:19]) [\(.type)] \(.summary)"' | grep -v job_triggered
```

Second defect in the same template: the `POST /reflection/record` example it prints omits the
`Authorization: Bearer` header, so following it verbatim returns `Missing or invalid Authorization
header` and the reflection is never recorded. Add the header.

**Why:** an empty result in a monitoring/reflection job reads as good news. `2>/dev/null` on the step
that produces the evidence converts a hard failure into a plausible silence.

**How to apply:** never suppress stderr on an evidence-producing step; and when a health/reflection
check reports "nothing happened", verify the extraction ran before believing it.
See [[feedback_verify_durability_not_just_landing]], [[feedback_apply_fix_dont_just_note_it]].
