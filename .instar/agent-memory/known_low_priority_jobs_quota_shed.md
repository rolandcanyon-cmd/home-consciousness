---
name: known-low-priority-jobs-quota-shed
description: "\"quota\" job skips are degraded-mode low-priority shedding; the priority fix is REVERTED by every schedule-file regeneration (recurred 07-30)"
metadata:
  node_type: memory
  type: project
  originSessionId: 9beec25b-de2d-48b4-bd57-a5fe94048db8
  modified: 2026-08-01T03:04:53.919Z
---

Four enabled jobs — `insight-harvest`, `overseer-development`, `rope-health-digest`,
`relationship-maintenance` — get skipped with reason `quota` while `GET /quota` says ~22%
usage, status ok, recommendation normal.

**It is not quota pressure.** `QuotaTracker.shouldSpawnSession` classifies a `claude-jsonl`
quota source as non-authoritative ("degraded"), and `boundedDegradedDecision` then refuses
*every* job with `priority: "low"` unconditionally, whatever the usage number is. All four
shed jobs are priority low; everything that ran was medium/critical or a script job (script
jobs bypass quota gating).

**Why it's hard to see:** `QuotaManager.setScheduler` collapses the rich verdict to a boolean
(`sched.canRunJob = (priority) => this.canSpawnSession(priority).allowed`, QuotaManager.ts:294),
throwing away the reason string, so the log only ever says bare `quota`. `GET /quota` exposes
neither `fiveHourPercent` nor the degraded/source-authority flag. Filed upstream.

**The fix:** raise `priority` low → `medium` in `.instar/jobs/schedule/<slug>.json`, then
**restart** (job definitions load at server start only — [[known-job-config-edits-need-restart]]).
Backups: `/tmp/<slug>.json.bak-0728`, `/tmp/<slug>.json.bak-0730`.

## THE FIX DOES NOT PERSIST — regression confirmed 2026-07-30

Applied 07-28 23:05Z, activated by the 07-29 03:02Z restart, verified landed 07-29 11:00Z
(`GET /jobs` reported all four at `medium`, zero `retry:quota` after the restart). It then
**silently reverted ~28 hours later.**

Evidence: **all 33 files** in `.instar/jobs/schedule/` share mtime `2026-07-30T14:31:28Z` —
a single wholesale regeneration — one second before the `14:31:29Z` scheduler restart. The
regenerated files carry the shipped-template `priority: "low"`; `enabled` survived, `priority`
did not. Quota shedding resumed at 14:32:45Z and logged 8 skips by 15:01Z (insight-harvest 6,
overseer-development 2) while `GET /quota` read 22.3% / normal at 14:51:40Z — a shed 2 minutes
after a healthy reading.

**This was NOT a bad-npm-update event:** `GET /updates/last` showed
`currentVersion == latestVersion == 1.3.1073, updateAvailable: false`. Any full regeneration
(a build/deploy of the shadow-install, a server start) can do it. Assume it happens routinely.

**The generalizable lesson — durability is not landing.** CLAUDE.md documents that the
installer "explicitly PRESERVES" `enabled` in the schedule override file. It says nothing about
any other key, and `priority` is in fact NOT preserved. **An override outside the preserved-key
set is reverted by the next regeneration, silently.** Verifying a fix landed once (`GET /jobs`
said `medium`) is evidence about that moment only — it is not evidence the setting will survive.
Re-verify overrides after every build/deploy/restart, not just after the one that applied them.
Generalized into [[feedback-verify-durability-not-just-landing]].

**Re-applied 2026-07-30 ~15:05Z** from the reflection cycle (only this quiet job session was
live), with a same-session restart. **Verify:** `GET /jobs` reports all four `medium`, AND the
four stop logging `retry:quota` in `activity-*.jsonl`. **Then re-check after the next deploy** —
if it reverts again the durable fix is upstream (make `priority` a preserved key, or ship an
authoritative quota source), not another local edit.

**Behavioral verification PASSED, durability NOT yet tested (2026-07-31 03:05Z, +12h).**
All four read `medium` in both `GET /jobs` and on disk; **zero** `job_skipped` records of any
reason since the 15:05Z restart (the pre-fix rate was 8 skips in 30 min). The behavior half of
the verification above is closed.

**Do not read that as durability.** No regeneration has occurred in the window — the other 29
schedule files still carry the `2026-07-30T14:31:28Z` regeneration mtime while these four carry
my `15:02Z` edit. The previous application survived **28 hours** before a regeneration reverted
it; 12 clean hours is inside that envelope and proves nothing. The regeneration is the test, not
elapsed time. Re-check the four files' mtimes — a jump to a new shared mtime across all 33 means
a regeneration ran and `priority` needs re-checking immediately.

**Two enabled+low jobs are NOT part of this regression (07-31).** `GET /jobs` also reports
`feedback-retry` and `instar-state-snapshot` as enabled + low. Both have **no
`.instar/jobs/schedule/<slug>.json` at all** — the `low` comes from the shipped built-in
definition, not from a reverted override — and both run on schedule with zero `gateReason=="quota"`
records (feedback-retry every 6h, instar-state-snapshot weekly). They are at-risk-but-healthy;
treating either as a defect is a false positive. Check whether a schedule file exists before
attributing a low priority to a regeneration.

**Durability still untested at 2026-07-31 08:00Z (+17h).** mtime groups: 29 files at the
07-30 bulk-regen stamp, the 4 overridden at a later distinct one; all four still `medium` live;
zero quota sheds on 07-31. No regeneration has run, so this remains inside the 28h envelope.

## THE REVERTER IS IDENTIFIED — repair moved into the deploy (2026-07-31)

**Third revert, 14:31Z today.** All 33 schedule files back to one shared mtime; the four
overrides back to `low`; `insight-harvest` + `overseer-development` shed as `quota` at 15:00Z
while `GET /quota` read **26% / ok / normal** at 14:51Z.

**It is the daily `imessage-fork-maintenance` deploy — not a random event, not an npm update**
(`auto-updater.json` `lastApply` is 2026-04-02). Activity log: `imessage-fork-maintenance`
triggered `14:30:24Z` → `scheduler_stop 14:31:41Z` → `scheduler_start 14:31:43Z`. The 07-30
revert carries the **same 14:31Z signature**. The deploy's `npm install` of the shadow-install
regenerates every schedule file (keeping `enabled`, discarding `priority`) and then restarts.
That is exactly the ~28h survival window: **one daily cycle**. So a manual re-application is
futile by construction — guaranteed wiped at 07:31 PDT daily.

**Fix applied (structural):** a repair step in
`.claude/skills/imessage-fork-maintenance/SKILL.md` step 7 (Deploy), placed after the
`autoApply` fix and **before** the `launchctl kickstart` — so priorities are restored after
regeneration and before the load. It sits with the two identical pre-existing repairs in that
same block (node symlink, node-candidates.json), which exist because `npm install` resets those
too. It also prints a warning for any OTHER enabled+low schedule override, so a fifth affected
job self-announces instead of being silently shed.

**No restart was taken today** (only two quiet job sessions were live, one of them the
reflecting session itself). The four files are back at `medium` on disk; they activate at
tomorrow's 14:31Z deploy-restart, after which the new repair step keeps them there.
**VERIFY after 2026-08-01 14:32Z:** all four read `medium` in `GET /jobs` AND zero
`quota` `job_skipped` records. If they read `low` again, the repair step did not run — read the
deploy's transcript. (A no-upstream-commits day short-circuits step 4 → step 8, skipping the
repair — but that also skips the `npm install` that regenerates, so nothing reverts either.
Regeneration and repair are correctly coupled inside step 7.)

**Caution:** `.instar/jobs.json` carries `priority: low` for these jobs and is stale / NOT
authoritative — the loader reads `.instar/jobs/schedule/<slug>.json`. An API-vs-log mismatch
must be checked against the last `scheduler_start` before it's called a bug
([[feedback-api-vs-log-time-gap]]).

**Do NOT read 07-31's continued shedding as "the repair step failed."** The repair was
committed at `822d2d7`, 2026-07-31T09:00:38-07:00 (16:00:38Z) — **90 minutes after** the
14:30:24Z deploy that reverted the priorities. Today's deploy ran a version of the skill that
did not contain the repair, so it could not have applied it. Confirmed end-state on 07-31:
29 schedule files at mtime `14:31:42Z` (regeneration) + scheduler restart `14:31:43Z`, then
the four repaired by hand at `15:02:52Z` — **31 minutes after the restart**, so the running
scheduler kept the `low` it loaded. Live `GET /jobs` read `low` for all four while disk read
`medium` for the rest of the day, costing 26 `retry:quota` sheds across the four jobs.
The 08-01 14:32Z check is the **first** real test of the repair step; a `low` reading before
that date proves nothing about it.

## THE REFUSAL IS A STATE, NOT A LATCH — corrected 2026-07-31T23:05Z

Two claims at the top of this note are falsified by direct observation tonight.

**1. "Silently shed until the next deploy" is wrong.** Live priority for all four was `low`
all afternoon (14:31Z regeneration reverted them; the 15:02Z disk repair landed 31 min after
the restart so the running scheduler kept `low`). They shed 15:00Z→19:51Z, each exhausting its
full 6-step retry ladder (+1m, +6m, +21m, +51m, +1h51m, +3h51m). Then `insight-harvest`
**spawned normally at 23:02:06Z with priority still `low`** — session
`job-insight-harvest-ms9jrwtm`, confirmed `running` via `GET /sessions`. The degraded refusal
tracks the CURRENT quota-source state; when it lifts, the next scheduled occurrence runs. A
reverted priority costs the occurrences that land inside a degraded window, not the whole day.

**2. "GET /quota exposes neither fiveHourPercent nor the source-authority flag" is wrong.**
At 2026-07-31T23:00Z it returned
`{"status":"ok","usagePercent":43,"fiveHourPercent":25,"source":"anthropic-oauth",
"lastUpdated":"2026-07-31T22:55:18.395Z","recommendation":"normal"}` — both fields present.
`git log --since=7.days -S fiveHourPercent` in `~/instar-dev` finds nothing, so this is not a
new upstream fix arriving via the daily rebase. Most likely the fields are populated only when
an authoritative source is live, which makes **the absence of `source`/`fiveHourPercent` the
degraded-mode tell** — the cheap diagnostic this note said did not exist. Re-confirm the next
time the source reads `claude-jsonl`.

**Diagnostic order, corrected:** read `source` in `GET /quota` FIRST. `anthropic-oauth` =
authoritative, low-priority work runs, a `retry:quota` skip needs a different explanation.
`claude-jsonl` (or the field missing) = degraded, every `priority: low` job is refused whatever
`usagePercent` says. Never reason from the usage number; never generalise from one sample —
the source flips during the day, so re-read it at the moment you are explaining a skip
([[feedback-api-vs-log-time-gap]]).

**No restart taken (again), deliberately.** On-disk is already `medium` for all four; only a
load is missing. A bounce was considered and declined because the source had already flipped to
authoritative (so the fix would have bought nothing tonight) and `job-insight-harvest` was live
and would have been killed mid-run. The 08-01 14:32Z deploy restart remains the first real test
of the repair step in `.claude/skills/imessage-fork-maintenance/SKILL.md` step 7 — and note that
a clean night tonight is explained by the source flip, NOT by the repair.

**Source-flip reading CORROBORATED (2026-08-01T03:00Z, +4h).** `GET /quota` still authoritative —
`{"status":"ok","usagePercent":47,"fiveHourPercent":14,"source":"anthropic-oauth"}` — and **zero
`job_skipped` records of any reason since 2026-07-31T19:51Z** (~7h clean), while live priority for
all four is *still* `low` and disk is *still* `medium`. That combination is the clean proof of the
corrected diagnostic: **priority is irrelevant while the source is authoritative.** The unrepaired
`low` cost nothing overnight. So do not read a quiet night as the repair working — and equally, do
not read a quiet night as the priority divergence being harmless; it is dormant, not fixed.
The 08-01 14:32Z deploy remains the first real test of the step-7 repair.

## THE REPAIR WAS IN THE WRONG PLACE — regeneration is at BOOT, not at npm install (2026-08-01T07:00Z)

The step-7 repair added 07-31 was placed **before** the `launchctl kickstart`, reasoning that
`npm install` regenerates and the restart then loads the repaired files. That reasoning is
wrong and the repair as placed could never have worked.

**Evidence (07-31):** `.instar/shadow-install/` npm artifacts carry **April/June** mtimes,
while all 33 `jobs/instar/*.md` and 29 `jobs/schedule/*.json` share mtime `14:31:42Z` — sitting
**between** `scheduler_stop 14:31:41.150Z` and `scheduler_start 14:31:43.694Z`. Only ONE
stop/start pair exists on 07-31, so that pair is the skill's own kickstart, not an installer
restart. Regeneration runs **during the new server's boot**, one second before the job loader
reads the files — so a pre-kickstart repair is wiped by the very boot it precedes.

**But boot regeneration is conditional on the install/version change, not every boot** — which
is what makes the fix possible. Proof from 07-30: repair at 15:02Z, a *second* boot at
15:05:22Z (same build), then all four ran on schedule the rest of the day (insight-harvest
15:06Z, relationship-maintenance + rope-health-digest 16:00Z, overseer-development 19:03Z),
zero further sheds. The identical repair on 07-31 with **no** second restart left live priority
`low` and cost 26 `retry:quota` sheds. Repair-then-restart works; repair-then-nothing does not;
repair-before-the-regenerating-boot does not.

**Fix applied 2026-08-01:** the repair block moved to *after* the restart-verified kickstart in
step 7, plus a conditional **second** kickstart (only when a priority was actually re-applied),
plus a `GET /jobs` assertion that the four read `medium` — the on-disk value is not the loaded
value ([[known-job-config-edits-need-restart]]). **Expect TWO restarts in the 08-01 14:32Z
deploy transcript.** If only one appears, the new block did not run.

**Correction to the 07-31 entry above:** its claim that "the deploy's `npm install` ... regenerates
every schedule file and then restarts" is falsified — the npm install does not regenerate; the
boot does. The 08-01 14:32Z verification target stands unchanged, but a `low` reading then means
the *placement*, not the repair logic, needs re-checking.

**Generalizable:** when a setting is wiped by regeneration, identify *which step* regenerates
before choosing where the repair goes. "Just before the restart" is the intuitive placement and
is wrong whenever regeneration is part of boot. The test is mtime ordering against the
`scheduler_stop`/`scheduler_start` pair in `activity-*.jsonl` — not the narrative order of the
deploy script. See [[feedback-repair-belongs-in-the-reverting-event]].
