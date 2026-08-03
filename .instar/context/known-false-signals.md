# Known False Signals

Monitoring readings that **look like a problem and are not**. Every entry here has cost a
full re-investigation at least once. Read this before reporting anything as an issue.

**How to use this file:** if your finding matches an entry below, it is NOT a finding — stay
silent. If you discover a NEW false signal, add it here rather than patching one job's
instructions, so the next diagnostic job inherits it too.

Last verified: 2026-08-02 (all five entries re-checked against live state on this date).

---

## 1. `GET /health` → `status: "degraded"` is a dead constant

`status` has read `degraded` continuously since 2026-07-13 because of an accepted SecretStore
dual-key (keychain-vs-file) divergence Adrian deliberately chose to leave as-is.

- **Do NOT branch on `status`.** It has been `degraded` for weeks and will stay that way.
- **Do NOT branch on the `degradations` count either.** It is not even stable — it read 26 on
  2026-07-31 and 18 on 2026-08-02, while reducing to **exactly 1 distinct string** both times.
  A count that moves still proves nothing.
- **Correct read:** reduce `degradationSummary` to its **distinct** entries, then drop any
  mentioning SecretStore / dualKeyRead / master key divergence. If nothing distinct remains,
  health is fine. A genuine 27th problem would otherwise be one line hidden among 26 identical ones.
- A server that does not respond at all, or genuinely low disk, is still a real finding.

## 2. `.instar/logs/server-launchd.log` has NO timestamps and spans weeks

The file is ~352MB and its lines carry no dates. A `tail`-based frequency count therefore
reads as *live* activity when it may be weeks stale.

- This made `dashboard-link-refresh` (37k skip + 34k retry lines) look like an active retry
  storm. `GET /jobs` showed `enabled: false`, `lastRun 2026-07-28` — fixed long ago.
- **Never date a claim from this log.** Corroborate against a timestamped source
  (`.instar/logs/activity-*.jsonl`) or a live API read before reporting frequency or recency.

## 3. A gated job with a past `nextScheduled` and a stale `lastRun` is NORMAL

When a job's `gate` exits 1 the job **skips** — and for most gated jobs exit 1 means
*"queue is empty, nothing to do"*, i.e. **healthy**. A skip does not advance `nextScheduled`
to the next cron slot; the scheduler retries the same slot on a doubling ladder.

Observed ladder (measured from `job_gate_skip` inter-arrival times, 2026-08-01):
`+70s, +310s, +910s, +1810s, +3610s, +7210s` — i.e. ~1m, 5m, 15m, 30m, 1h, 2h — then it
re-anchors to the next cron slot. (It does **not** continue to +4h.)

- So "nextScheduled is in the past" on a **gated** job is not a wedge.
- Any frozen-`nextScheduled` wedge detector **must exclude gated jobs**, or it false-positives
  on every healthy empty-queue skip.
- Gate exit 1 on its own proves nothing either way — it is the normal healthy path.

**Before calling any past-due `nextScheduled` a wedge, run these two checks (2026-08-03):**

1. **Look for recent `job_gate_skip` records for that slug** in `.instar/logs/activity-*.jsonl`.
   ⚠ The slug lives at **`.metadata.slug`, NOT top-level `.slug`** — a naive `.slug` read returns
   `null` for every gate-skip record and makes a healthy gated job look dead. On 2026-08-03
   `evolution-proposal-evaluate` and `evolution-proposal-implement` were both past-due and both
   provably alive via gate-skip records at 14:52/15:00/15:01Z.
2. **Compare against other jobs firing at the same minute.** A genuine silent miss is **per-job,
   not scheduler-wide.** When `imessage-fork-maintenance` (cron `30 7 * * *` = 14:30Z) silently
   did not run on 2026-08-03, the scheduler spawned `health-check` and `scheduler-health-notify`
   within 0.4s of that same 14:30:00 tick. **If siblings fired, stop investigating the scheduler
   and investigate the single job entry.** Last `scheduler_start` was 08:04:51Z, hours earlier —
   so it was not a restart race either.

A genuine silent miss looks like: `state.lastRun` frozen on the prior day, `state.nextScheduled`
frozen at the already-passed slot, `consecutiveFailures: 0`, **zero** activity-log records, and no
`job-<slug>-*` session in `GET /sessions?include=all`. Restarting the server clears it.

Side effect worth knowing: gate skips ride the retry ladder, so one skip generates ~6 job attempts
over ~112 min. Cheap (shell, no LLM) but it pollutes the retry-exhaustion telemetry that
`scheduler-health-notify` keys on.

## 4. `GET /jobs` top-level `lastRun` / `nextScheduled` are ALWAYS null

Verified 2026-08-02: **0 of 52** jobs populate the top-level fields; **34 of 52** populate
`state.lastRun` / `state.nextScheduled`.

- Read `job.state.lastRun` and `job.state.nextScheduled`, never `job.lastRun`.
- The naive top-level read makes every job look as if it has never run — i.e. total scheduler
  failure — and simultaneously defeats any wedge detector built on those fields.

## 5. Cron fires in LOCAL time; logs and the API report UTC

Schedules in job definitions are evaluated in machine-local time (currently PDT, UTC-7), while
`activity-*.jsonl` timestamps and every API `lastRun`/`nextScheduled` are UTC.

- **The real UTC slot is the cron hour + the local offset** (currently +7).
- Worked example verified 2026-08-02: `evolution-proposal-implement` has cron
  `0 1,7,13,19 * * *`; it last ran `02:00Z` (= 19:00 local) and is next due `08:00Z` (= 01:00 local).
- Comparing a cron hour directly against a UTC log time is the frame error behind repeated
  false "job wedged" / "job fired at the wrong time" diagnoses.

## 6. Editing a job's `.md` usually changes NOTHING — every file in `.instar/jobs/user/` is dead

Audited 2026-08-03: **all 20 `.md` files under `.instar/jobs/user/` never execute.** That is the
directory you would naturally edit to customise a job, and it is entirely inert.

Each of those files now opens with an inline `⛔ DEAD FILE` banner naming its real prompt source,
so the warning is visible in the editor at the moment of the edit (EVO-059). `tcc-permission-check.md`
was deleted — no such job exists anywhere.

A job's real prompt comes from one of three places. **These are ordered by precedence, not
alternatives — check 1 first and stop if it matches.**

1. **`.instar/jobs/schedule/<slug>.json` has `execute.type: "agentmd"`** → the body is
   `.instar/jobs/<origin>/<slug>.md`, where `origin` is a field *in that manifest*. It is
   `instar` for every agentmd job here, so the **`instar/` copy executes and the `user/` copy is
   a shadow.** ⚠ Those `instar/` files are regenerated from the shipped template on every
   update, so an edit there is reverted by the next daily deploy — put the repair in the deploy
   (see the `REPAIRED_MD` block in the `imessage-fork-maintenance` skill), not just in the file.
2. **The slug is in legacy `.instar/jobs.json`** (`execute.type: "prompt"`) → that `execute.value`
   string is the prompt **only if rule 1 did not already match**. The `.md` is documentation only.

   ⚠ **Rule 1 beats rule 2, and 13 slugs match both.** Measured 2026-08-03 by diffing
   `.instar/jobs.json` against live `GET /jobs`: **13 of 32** `jobs.json` entries declare
   `execute.type: "prompt"` while the loaded job runs `execute.type: "agentmd"` — their
   `execute.value` is dead code. They are `health-check`, `reflection-trigger`,
   `relationship-maintenance`, `insight-harvest`, `evolution-overdue-check`, `identity-review`,
   `evolution-proposal-evaluate`, `evolution-proposal-implement`, and all five `overseer-*`.
   All 13 have a `schedule/<slug>.json` declaring `agentmd`. Editing the `jobs.json` prompt for
   any of them changes nothing and raises no error.
3. **Neither** → the job does not exist at all (e.g. `user/tcc-permission-check.md`).

This cost real time twice: a health-check fix applied to `user/health-check.md` on 2026-08-02 had
**never once run**, and this file's own pointer had to be re-applied to `jobs.json` and
`jobs/instar/` after the first attempt silently did nothing.

**Verify, never assume:** after any job edit, read the loaded prompt back from
`GET /jobs` (`execute.value`, falling back to `body`) *after a restart* and confirm your text is
actually in it. Job definitions load at server start — there is no hot reload.

---

## 7. Every outbound channel here reads healthy while its WRITE is broken

The paths by which I surface something to Adrian are degraded, and each degrades *without
erroring at the point of use*. Reading the surface tells you nothing:

- **Attention queue — WRITE-DEAD.** `POST /attention` returns `503 {"error":"Telegram not
  configured"}`; the handler gates on Telegram before storage, and this agent runs
  whatsapp (logged out) + imessage. So **`GET /attention` returning 0 items means nothing can
  be *written*, not that nothing needed attention.** Every built-in guard that escalates this
  way — guard-posture tripwire, sentinel escalations, resume-queue give-ups, burn detection,
  duplicate reconciler, scope-accretion holds, machine-coherence, load-bearing gaps — is a
  silent no-op here. Filed `fb-bbe74c6b-96c`.
- **Feedback ring — 99% flood.** The store holds 1000 entries, which looks full and healthy;
  ~993 are the same `[DEGRADATION] SecretStore.dualKeyRead` report, leaving ~8 distinct titles.
  At ~814/day the ring recycles about daily, so anything real filed there is destroyed within
  ~24h. Filed `fb-af466c05-2b1`.
- **Tunnel — INTERMITTENT, not dead.** A `url` field is often populated even when the link is
  unreachable, and it genuinely does work in stretches. Do not tell Adrian remote links are
  impossible; **re-read `GET /tunnel` at the moment you need one.** Filed `fb-955877a3-429`.

**The rule:** when something needs Adrian, send iMessage — the only channel verified to work.
Never `POST /attention` and assume it landed. And if an escalation *write* fails, that failure
**outranks** whatever was being escalated; report the broken channel first, not as a footnote.

`guardian-pulse` runs `.claude/scripts/outbound-channel-check.py` every 8h to catch relapses
(write-probe and distinct-value checks only, deduped to once per channel per day). Do not
re-file the three `fb-*` reports above — they are the durable upstream record.

---

## Two general rules that produced most of the above

- **An API read is implicitly "now".** Do not compare a live API read against pre-restart log
  lines; check the most recent `scheduler_start` first, or the mismatch is an artifact.
- **A constant is not a signal.** Before reporting a field, ask whether it has *ever* held a
  different value. If it cannot vary, it cannot be evidence.
