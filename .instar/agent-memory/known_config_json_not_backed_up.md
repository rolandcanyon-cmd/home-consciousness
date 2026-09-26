---
name: known-config-json-not-backed-up
description: ".instar/config.json (secrets, tokens, job/feature settings) is excluded from BOTH git-sync and the backup-snapshot system — no durable backup coverage at all"
metadata:
  node_type: memory
  type: project
  originSessionId: 1b3d3ffa-2f99-41d4-8910-a96d2b706edf
---

**Found 2026-07-13** while investigating why a config change (`monitoring.resumeQueue.autoHealStaleHostLock`) didn't show up in git after `POST /git/commit` returned `{"committed":true}`.

`.instar/config.json` is listed in `.instar/.gitignore` (line 14) — **correctly**, since it holds live secrets in plaintext (`authToken`, `sessions.anthropicApiKey`, `dashboardPin`). Git-sync will never touch it, by design.

**But**: `POST /backups` snapshot file lists (checked 2026-07-13) only ever include `AGENT.md`, `USER.md`, `MEMORY.md`, `jobs.json`, `users.json`, `shared-state.jsonl.stats.json` — **config.json is not in that list either**. So config.json — including any manual `PATCH /config` or direct-edit changes (feature flags, job-relevant settings, the resumeQueue fix from today) — currently has **zero durable backup coverage**. A disk failure or bad edit with no undo would lose it entirely; recovery would mean regenerating `authToken`/`dashboardPin` and re-entering `anthropicApiKey` (and any accumulated tuning like the resumeQueue fix) from scratch.

`.instar/jobs.json` is ALSO gitignored (`.instar/.gitignore` line 53, "Operational state") — but unlike config.json, it IS included in the backup-snapshot file list above. So custom job definitions (e.g. the `repo-health-sweep` job added 2026-07-13) survive via periodic snapshots, just not via git.

**Not yet resolved / worth a decision**: does config.json's secret content make it deliberately excluded from snapshots too (avoiding secrets sitting in a less-protected backup archive vs the actual encrypted vault), or is this an oversight? Flagged as an open question, not fixed — haven't touched the backup `includeFiles` list or snapshot code. See also [[known-stale-hostname-lock]] for the related resumeQueue lock fix that prompted this discovery.

**How to apply:** before assuming "our state is backed up" covers everything, remember config.json is the one load-bearing file that isn't — in EITHER git or snapshots. If Adrian wants it covered, that's a real ask, not something to assume is already handled.
