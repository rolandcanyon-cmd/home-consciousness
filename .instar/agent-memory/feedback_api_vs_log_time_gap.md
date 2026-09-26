---
name: feedback-api-vs-log-time-gap
description: "An API read is implicitly 'now' — comparing it to log records across a restart manufactures a phantom bug"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5e9273cc-82a1-404c-8fad-a478923cf011
  modified: 2026-07-29T11:03:59.705Z
---

Before calling any API-vs-log mismatch a bug, find the last `scheduler_start` / server restart
and check whether the log records fall on the other side of it.

**Why:** log lines carry timestamps; an API read does not — it is implicitly "now". Every
comparison between the two is a comparison *across time*, and any restart, deploy, or config
reload inside that gap manufactures a contradiction that does not exist. This is the shape that
makes a correctly-working system look broken.

**How to apply:** the fastest tell is whether the mismatch *stops* after the restart. Counting
the disputed events on each side of the restart boundary settles it in one command — a
before>0 / after=0 split is a fix landing, not a divergence.

**Origin (2026-07-29):** `GET /jobs` reported `insight-harvest` at `priority: medium` while its
`job_skipped` records stamped `low`. I concluded the API and the scheduler read priority from
different sources and filed it upstream (fb-e557104a-ce5). The skip records were from 00:51Z and
02:51Z — before a 03:02Z restart that loaded the corrected value. Quota skips: 2 before, 0 after.
No bug. Corrected in fb-a7968ca8-fb9. See [[known-low-priority-jobs-quota-shed]] and
[[known-job-config-edits-need-restart]], which is the same restart-boundary trap from the other
direction (a file written is not a setting in effect).
