---
name: known-job-queue-serialized
description: "A job trigger returning \"queued\" with no session for minutes is normal serialization, not a dropped job"
metadata: 
  node_type: memory
  type: project
  originSessionId: 279fd871-8e87-4984-af72-3103971c7f0b
  modified: 2026-08-04T07:34:30.665Z
---

`POST /jobs/<slug>/trigger` returns `{"result":"queued"}` and the job may not spawn for many
**minutes**. The queue drains one job at a time through `.instar/state/active-job.json`.
Measured 2026-08-03: a manual trigger at 15:03 sat behind `job-insight-harvest` until 15:09:37.

**Machine load and session count are NOT the constraint** — load was fine (76% idle, 2 running
sessions) while the queue was serialized. Don't cite load as the cause.

**Wait correctly:** grep the slug in `.instar/logs/activity-*.jsonl`. Do NOT poll `GET /sessions`
for ~60s and call the absence a failure — that misread briefly looked like the silent slot-miss
bug ([[known-silent-cron-slot-miss]]) and was not.

**Observability hole:** a `job_triggered` record is written at DRAIN time, not enqueue time, and
there is no enqueue event at all. A job enqueued-then-dropped is indistinguishable in the logs
from one never enqueued. Say "cannot attribute", not "dropped".

Full detail lives in `.instar/context/known-false-signals.md` §8 (git-tracked, durable).
Related: [[known-jobs-user-md-are-dead]], [[known-job-config-edits-need-restart]].
