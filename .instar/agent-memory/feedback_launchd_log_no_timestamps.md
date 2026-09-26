---
name: feedback-launchd-log-no-timestamps
description: server-launchd.log/.err have no timestamps and span weeks — never date-reason from a tail of them
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ca024778-c5c6-4596-b996-66e3318c4147
  modified: 2026-08-02T19:06:13.174Z
---

`.instar/logs/server-launchd.log` (352MB) and `server-launchd.err` (100MB) are
unrotated launchd stdout/stderr with **no timestamps**. A `tail -200000`
frequency count *feels* like "recent activity" but reaches back past 2026-07-28.

**Why:** doing exactly that on 2026-08-02 made `dashboard-link-refresh` look
like a live retry storm — 37k "skipped (error)" + 34k "Retrying job" lines, by
far the most frequent line in the sample. `GET /jobs` showed it
`enabled: false`, `lastRun: 2026-07-28` — fixed a week earlier. Same trap
nearly fired on lease churn (22k lease-acquire lines in the sample; the live
epoch did not move at all over a measured 45s).

This is the map-vs-territory failure in log-forensics clothing: a big
undated file makes stale history indistinguishable from current state.

**How to apply:** date every log-derived claim against a timestamped source
(`logs/server.log`, `.instar/logs/activity-*.jsonl`) or a live API read before
reporting it. If a log line names a job, check `GET /jobs` for that slug before
calling it a live failure. Related: [[known_jobs_api_null_toplevel_fields]],
[[feedback_api_vs_log_time_gap]]. Learned 2026-08-02 (LRN-011).
