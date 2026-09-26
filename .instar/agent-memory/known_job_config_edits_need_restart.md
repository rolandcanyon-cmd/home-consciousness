---
name: known-job-config-edits-need-restart
description: "Job enable/disable edits do nothing until a server restart — three \"disabled\" jobs were still firing 8+ hours later. Verify against the LIVE scheduler, never the file you just edited."
metadata: 
  node_type: memory
  type: project
  modified: 2026-08-02T14:36:35.865Z
  originSessionId: 5aeea14f-9e68-470f-9402-310ef58d4f26
---

**Verified 2026-07-28 11:00Z.** Job definitions load **at server start only —
there is no hot reload.** An edit to `.instar/jobs.json` or
`.instar/jobs/schedule/<slug>.json` changes nothing in the running scheduler
until the server restarts.

Evidence from this machine: server started **Jul 27 17:48 PDT**. Both disable
edits were written *after* that (`commitment-detection.json` at 21:01,
`jobs.json` touched 00:02) — so 8+ hours later both jobs were still firing on
their original schedules, and `dashboard-link-refresh` was still re-queuing on
error roughly **once a minute**, which is ~90% of the day's scheduler log volume.

**The verification rule:** after any job-config edit, compare the file against
the live scheduler — they are different sources:

```
curl -s -H "Authorization: Bearer $AUTH" http://localhost:4040/jobs
```

If `enabled` differs from the file, the edit has **not** taken effect. Reading
back the file you just wrote proves only that the write succeeded.

**The `dashboard-link-refresh` case closed as the mechanism predicts
(confirmed 2026-07-28 14:34Z):** it looked like a live-vs-disk discrepancy that
a restart wouldn't fix — jobs.json had carried `enabled: false` for months
while the live scheduler kept firing it ~once a minute. A restart *did* fix it
(`GET /jobs` → `enabled: false`, no run after 12:01Z despite a `*/15` cron).
Lesson: when an edit needs a restart and hasn't had one, don't conclude the
mechanism is broken — recheck after the next restart before revising the model.

**`.instar/jobs.json` is NOT git-tracked — snapshots are its only backup**
(re-verified 2026-08-02). A note here previously "corrected" this to say it *was*
tracked; that correction was wrong. Commit `3813e70` (2026-04-25) removed it and
added it to `.instar/.gitignore` alongside `config.json`. The trap: `git log --
.instar/jobs.json` still lists its pre-April commits, and `git diff HEAD` is
clean *because the file is untracked* — neither proves tracking. The check that
does: `git ls-files --error-unmatch <path>` or `git check-ignore -v <path>`.
See [[known-config-json-not-backed-up]].

**Generalizes beyond jobs — same rule for `config.json`.** The no-hot-reload
rule covers guard/feature config too, not just job definitions
(confirmed 2026-07-29: a `dryRun: false` written at 16:05 was still not in
effect at 16:30 because the server had been up since the previous evening).
Two runtime tells, both on `GET /guards`: `off-runtime-divergent` (config on,
runtime not doing the work — usually a dry-run-first guard missing
`dryRun: false`) and `diverged-pending-restart`.

**This check is now automated (EVO-049, 2026-07-29).** The `state-integrity-check`
job runs every 6h and its "Config-Reality Match" section now reads `GET /guards`
for both divergence classes and compares `config.json` mtime against the server
start time. So a staged-but-unloaded edit surfaces on a cadence instead of
relying on someone remembering to re-check.

**Why this matters:** three separate notes written the same night each said
"disabled/fixed" while the behavior continued unchanged. The common failure was
treating a successful file write as a completed fix. A config change is done
when the *running system* reflects it — not when the editor saves.
See [[feedback_apply_fix_dont_just_note_it]],
[[known-evolution-gate-missing-auth]].
