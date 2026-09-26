---
name: known-silent-cron-slot-miss
description: A job can miss a cron slot with zero log records — a starvation class invisible to scheduler-health-notify; detect via ABSENCE of any activity-log event at the slot, NOT via frozen nextScheduled (retired 07-31); restart recovers but does not inoculate
metadata: 
  node_type: memory
  type: project
  originSessionId: 047fc2ab-4060-4266-a2dc-a95b6e26f9b0
  modified: 2026-08-02T23:02:37.249Z
---

`imessage-fork-maintenance` (`30 7 * * *`, no gate) missed its 2026-07-29 14:30Z slot leaving **no record of any kind** — no `job_triggered`, no `job_skipped`, no `job_gate_skip`, and no `[scheduler]` line in `logs/server.log`. The tick itself fired (`scheduler-health-notify` + `health-check` logged at that exact instant; neighbouring daily jobs at 14:00/15:00/15:15Z all ran). Its state file still reads `nextScheduled: 2026-07-29T14:30:00.000Z`, `lastRun: 2026-07-28T14:30:47Z`.

**Why:** this is a third starvation class, distinct from the two already catalogued — (1) memory-pressure skip (loud, retries, self-recovers via `queued:missed`), (2) gate exit 1 (`job_gate_skip`), (3) **silent slot omission (nothing at all)**. `scheduler-health-notify` cannot see it: `.claude/scripts/scheduler-health-check.py` detects via `EXHAUST_RE` matching `exhausted N retries` lines in `logs/server.log`, and a job that is never dispatched never retries. The detector is otherwise wired correctly (log path valid, 125 live matches).

**How to apply:** never conclude a job ran, or was blocked, from the absence of a skip record. (⚠️ The pointer-based test that followed here was RETIRED on 2026-07-31 — read the MECHANISM PINNED section below before using it.) Check `state.nextScheduled` in `.instar/state/jobs/<slug>.json` against now — a **gate-less** job with a past `nextScheduled` was silently dropped. Only valid for gate-less jobs: `nextScheduled` also goes stale on every gate-skip, so `git-sync`, `insight-harvest`, `evolution-*`, `degradation-digest` all show past values while healthy (8 of 9 stale entries on 07-30 were benign).

**CONFIRMED + REMEDY (2026-07-30 00:07 PDT):** a `launchctl kickstart -k gui/$(id -u)/ai.instar.Roland` cleared it — within ~70s the job fired a catch-up run and `nextScheduled` advanced to the next real slot. So the frozen pointer was a genuine wedge, and restart re-registers and replays the missed slot (expect the full 25-min rebase to run immediately). Check the node pin before restarting — see [[known_node_pin_crash]]. Mechanism still unknown; if it recurs, capture `logs/server.log` around the slot BEFORE restarting.

**VERIFIED HEALTHY (2026-07-30 11:01Z):** `imessage-fork-maintenance` state now reads `lastRun: 2026-07-30T07:07:12Z`, `nextScheduled: 2026-07-30T14:30:00Z`. Recovery held.

**CAVEAT — a `(missed)` replay is NOT evidence a job was wedged.** The 07:07Z restart replayed exactly two jobs as `(missed)`: `imessage-fork-maintenance` (genuinely overdue) and `capability-audit` (**not** overdue — it had run on schedule at 07-28 13:00Z, its next real slot was 07-31 13:00Z, and its pointer advanced to exactly that afterwards). So the restart's missed-slot evaluator produces false positives; a `(missed)` label in the activity log means "the evaluator decided to replay it", not "this job had been dropped". Counting `(missed)` replays overstates the wedge's blast radius. Suspected cause is a local-vs-UTC frame mismatch in missed-slot evaluation (`capability-audit`'s schedule reads `0 6 */3 * *` while it consistently fires at 13:00Z = 06:00 PDT) — unconfirmed, do not treat as diagnosed.

**The "gate-less jobs only" exclusion above is too permissive.** A job whose gate is effectively always-true is still diagnosable by its pointer. `coherence-audit`'s gate is just `curl -sf http://localhost:4040/health`, which passes whenever the server is up — so a stale pointer there is meaningful, not gate noise. Judge the gate's actual pass rate, not merely whether a gate exists.

**WATCH ITEM — `coherence-audit` (as of 2026-07-30):** has not run since 2026-07-10T14:32Z; pointer frozen at `2026-07-13T15:00:00Z`. Its schedule was changed to monthly (`0 8 1 * *`, `firstSeenAt: 2026-07-27T15:26Z`) while the historical runs were all ~15:00Z on assorted days, so the stale pointer belongs to the retired schedule. The 07:07Z restart did **not** replay it. Benign reading: the monthly cron computes next = 2026-08-01T08:00Z and nothing was actually missed. Wedge reading: same frozen-pointer signature as above. **Check on 2026-08-01 whether it fires**; if it does not, restart clears it as before. Do not raise this before Aug 1 — there is no way to distinguish the two readings yet.

**MECHANISM PINNED (2026-07-31): the pointer is written at run time and never revised, and the API echoes it unreconciled.** `GET /jobs` returns `.state.nextScheduled` verbatim from `.instar/state/jobs/<slug>.json` **when the field is present**, and computes it live from the cron **only when the field is absent**. Proof: `evolution-overdue-check.json` on disk contains only `{slug, consecutiveFailures, firstSeenAt}` — no `nextScheduled` — yet the API reported `2026-07-31T11:00:00Z`, the correct future slot. So a past pointer proves only "has not run since then". It cannot distinguish a wedge from a retired schedule, from gate-skipping, or from a long cadence that is not due. **This retires the pointer as a primary detector**, including the "judge the gate's pass rate" refinement above — that narrows the false-positive set but does not make the signal sound. The reliable test is the absence of *any* event (`job_triggered` / `job_gate_skip` / `job_skipped`) for the slug in `.instar/logs/activity-<date>.jsonl` at the expected slot. Use the pointer only to generate candidates, then confirm against the activity log.

**FOURTH INSTANCE — and restart is recovery, not inoculation (2026-07-31).** `initiative-digest-review` (`0 11 * * 1,4` = Mon/Thu, genuinely gate-less — no `gate` key in `.instar/jobs/schedule/initiative-digest-review.json`) missed its Thursday 2026-07-30T18:00Z slot with zero records of any kind. `lastRun` still 2026-07-27T18:00Z, pointer frozen at 2026-07-30T18:00Z. Crucially, the scheduler had restarted cleanly at 2026-07-30T15:05Z with all 33 jobs registered — about three hours *before* the missed slot. So the wedge re-forms on a freshly started scheduler; the CONFIRMED + REMEDY section above should be read as "kickstart replays the missed run and clears that instance", never as a fix. Mechanism still unknown.

**Deliberately not restarted on discovery (2026-07-31T07:0xZ).** Three reasons, all still valid if this is re-read: the job's next fire is Mon 2026-08-03T18:00Z so there is no urgency; `.instar/logs/server.log` is 0 bytes (Mar 28) so a restart would capture no evidence the note asks for; and 2026-08-01 is the `coherence-audit` WATCH ITEM test date (see above), which a missed-slot replay would confound. Let 08-01 run untouched, then judge both jobs together. The 07-31 evidence tilts the `coherence-audit` question toward the wedge reading — two gate-less jobs now show the same signature — but does not settle it.

**WATCH WINDOW IS NOW OPEN — pre-slot baseline captured 2026-08-01T03:00Z.** Nothing has been
touched, per the 07-31 decision to let 08-01 run untouched. Baseline, for a clean before/after:

| job | records in `activity-2026-08-01.jsonl` @03:00Z | `lastRun` | pointer |
|---|---|---|---|
| `coherence-audit` | **0** | 2026-07-10T14:32:03.650Z | 2026-07-13T15:00Z |
| `initiative-digest-review` | **0** | 2026-07-27T18:00:00.478Z | 2026-07-30T18:00Z |

**The test:** `coherence-audit`'s monthly slot (`0 8 1 * *`) is **2026-08-01T08:00Z**.
After that instant run `grep -c coherence-audit .instar/logs/activity-2026-08-01.jsonl`.
Any record at all — including a `(missed)` replay — proves the scheduler dispatched it today
(the line-21 caveat says a `(missed)` label does not prove it *had been* wedged; it does not
weaken the converse, and dispatch-or-not is the actual question here). **Zero records after
08:00Z confirms the wedge reading**, and per CONFIRMED + REMEDY a kickstart clears that instance
— check the node pin first ([[known_node_pin_crash]]).

**⚠️ Do not judge before 08:00Z.** This reflection job runs every 4h, so the **07:00Z run is
still pre-slot** — reading "0 records" there means only "not due yet" and must NOT be written up
as the wedge confirmed. The **11:00Z run is the first that can decide.** `initiative-digest-review`
is *not* on test today: it is Mon/Thu and its next real fire is **Mon 2026-08-03T18:00Z**, so its
0 records today are expected and are not evidence either way.

**WATCH ITEM VOIDED — the test instant was in the wrong time frame (2026-08-01T11:00Z).** The test
above is unrunnable as written: cron fires in **local** time, so `coherence-audit`'s `0 8 1 * *`
slot is **2026-08-01T15:00Z**, not 08:00Z. See [[known_cron_evaluated_in_local_time]] — every job's
`nextScheduled` is its cron hour +7. So the 11:00Z reading is still *pre-slot*, and "0 scheduler
records" today proves nothing. The scheduler was demonstrably alive and ticking at 08:00:00.640Z
(gate-retry lines for other jobs), and it correctly did **not** dispatch `coherence-audit` then,
because the job was not due. Reading its whole history in local time, its schedule was set on
07-27 and its first fire under it is 08-01T15:00Z — nothing was ever missed. **The benign reading
wins; do not restart on this evidence.** This also retires the 07-31 line "the evidence tilts
toward the wedge reading — two gate-less jobs show the same signature": both signatures were
manufactured by the frame error.

`coherence-audit` did run once today at **09:01:54Z, `triggered (manual)`** — a manual/API trigger,
not a scheduler dispatch, so it is not evidence either way about dispatch. It succeeded, and its
pointer advanced to `2026-08-01T15:00:00Z` — which is precisely the datum that pinned the local-time
frame.

**Path correction:** the 07-31 decision not to restart was partly justified by "`.instar/logs/server.log`
is 0 bytes (Mar 28) so a restart would capture no evidence". That is the **wrong path**. The live
server log is **`logs/server.log`** (5.5 MB, current) — the `.instar/logs/` copy is a stale Mar-28
artifact. Scheduler evidence has been available the whole time; use `logs/server.log`.

**WATCH ITEM CLOSED — `coherence-audit` dispatched on schedule (2026-08-02).** `GET /jobs` now reads
`lastRun: 2026-08-01T15:01:31.293Z`, `nextScheduled: 2026-09-01T15:00:00Z`. It fired at its real
monthly local slot (15:00Z = 08:00 PDT), one minute after the instant the voided test misplaced at
08:00Z. The benign reading is confirmed; no wedge, nothing to restart. `initiative-digest-review`
remains the only open gate-less instance — its next real fire is Mon 2026-08-03T18:00Z.

**POSITIVE signal for gated jobs: the doubling retry ladder (2026-08-02).** A gate exit-1 skip does
not advance the pointer, but it *does* start a retry ladder on the same slot — observed cadence
+1m, +5m, +15m, +30m, +1h, +2h, +4h (e.g. `insight-harvest` 15:06 → 15:21 → 15:51 → 16:52 → 18:52Z;
`evolution-proposal-implement` the same shape). So for a **gated** job you get a confirming signal,
not just an absence: recent `job_gate_skip` rows in a doubling pattern prove the scheduler is still
evaluating it. `insight-harvest` currently shows `lastRun` 08-01T07:03Z against an 8-hourly cron and
a 32h-stale pointer — healthy, gate returning exit 1 (empty queue), ladder running. Do not diagnose
this as a wedge.

Related: [[known_scheduler_silent_starvation]], [[known_low_priority_jobs_quota_shed]], [[known_job_config_edits_need_restart]], [[known_jobs_api_null_toplevel_fields]], [[known_cron_evaluated_in_local_time]].


## 2026-09-07 correction — a frozen nextScheduled is NOT proof of a wedge

I read `storm-watch` (last=2026-08-29T00:07, next=2026-08-29T01:07, enabled=true)
as "wedged for 9 days" and restarted the server to clear it. Wrong on both counts:
the restart did not change it, and nothing was broken.

`storm-watch` had **self-stopped correctly**. `.instar/state/storm-watch-state.json`
held `stopped: true`, `warningLiftedAt: 2026-08-28T22:07:17Z`, and a note confirming
the Red Flag Warning was re-checked and gone. Its **gate** (`storm-watch-gate.sh`)
returns exit 1, so the scheduler skips it every hour and `nextScheduled` never
advances. That is the designed resting state, not a stall.

**The discriminator — check these BEFORE calling a frozen slot a wedge:**
1. Does the job declare a `gate:` in `.instar/jobs.json`? Run it — a non-zero exit
   means "intentionally skipping", and a frozen `nextScheduled` follows from that.
2. Is there a job-specific state file under `.instar/state/<slug>-state.json` with a
   `stopped` / `stoppedAt` / `reason` field? A self-stopping job records why.
3. Only if BOTH say it should be running is a frozen `nextScheduled` a real wedge.

A gated or self-stopping job looks identical to a wedged one from `GET /jobs` alone.
Cost of getting it wrong: an unnecessary server restart and a false alarm to the
operator about a safety monitor.
