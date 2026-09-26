---
name: known-jobs-user-md-are-dead
description: All 22 .md files in .instar/jobs/user/ are inert — they are the natural place to edit a job and the one place that does nothing; real prompts live in jobs/instar/SLUG.md (agentmd) or jobs.json execute.value
metadata: 
  node_type: memory
  type: project
  originSessionId: 936a6254-63b2-458f-8030-feb7cfe48936
  modified: 2026-08-03T07:05:12.971Z
---

Verified 2026-08-03 against live `GET /jobs`: **none of the 22 `.md` files under
`.instar/jobs/user/` ever execute** — including ones for actively running jobs
(guardian-pulse, health-check, state-integrity-check, insight-harvest, memory-hygiene,
coherence-audit, git-sync, reflection-trigger, the five overseer-* jobs).

A job prompt has exactly three possible real sources:
1. `.instar/jobs/schedule/SLUG.json` with `execute.type: agentmd` resolves the body from
   `.instar/jobs/ORIGIN/SLUG.md` — and `origin` is `instar` for every agentmd job here,
   so the `instar/` copy runs and the `user/` copy is a shadow.
2. The slug is in legacy `.instar/jobs.json` with `execute.type: prompt` — `execute.value`
   **is** the prompt and any `.md` is documentation only.
3. Neither — the job does not exist (`user/tcc-permission-check.md`).

The mixed tree is residue of the agentmd migration abandoned 2026-06-24
(`.instar/jobs/.migration-abandoned.json`).

**Nothing errors.** The edit lands on disk and reads back correctly, which is exactly why
this cost real time twice on 2026-08-02: a health-check degradation fix written to
`user/health-check.md` had never once executed, and the EVO-056 pointer had to be re-applied
to `jobs.json` and `jobs/instar/` after the first attempt silently did nothing.

**THE RULE:** after any job edit, restart the server and read the prompt back from
`GET /jobs` (`execute.value`, falling back to `body`). Confirm your text is present.
Note also that `jobs/instar/` is regenerated from the shipped template on every update, so a
durable edit there must be re-applied by the daily deploy rather than written once — same
durability trap as [[known_low_priority_jobs_quota_shed]].

See also [[known_job_config_edits_need_restart]] and LRN-015 / EVO-059.
