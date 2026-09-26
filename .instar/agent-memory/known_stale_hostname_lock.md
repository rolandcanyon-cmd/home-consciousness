---
name: known-stale-hostname-lock
description: "Server crash-loops with \"foreign host\" single-instance lock after a machine rename; clear the stale local lock"
metadata: 
  node_type: memory
  type: project
  originSessionId: 30164ac5-1517-43cb-bb47-5b01b51408c9
  modified: 2026-07-30T10:02:01.905Z
---

**Symptom:** "Roland not responding on iMessage" but the REAL cause is the server never started. `launchctl list | grep instar` shows `ai.instar.Roland` with `last exit code = 1`; `.instar/logs/server-launchd.err` repeats:
`[single-instance] lock held by FOREIGN host "escapepod-3.localdomain" (this host "Adrians-Mac-Studio.local"). Refusing` → crash-loop backoff.

**Root cause:** This machine was renamed (`escapepod-3` → `Adrian's Mac Studio` / `Adrians-Mac-Studio.local`). The fork-bomb single-instance guard's lock files still carry the OLD hostname, so the guard treats this host's own stale lock as a foreign/shared-volume conflict and refuses to boot.

**Lock files (this machine's own LOCAL apfs disk, safe to clear when stale):**
- `.instar/local/server-instance.lock` — `{"pid":...,"hostname":"escapepod-3...","heartbeat":...}`
- `.instar/state/resume-queue.lock` — `{"pid":...,"hostname":"escapepod-3..."}`

**Fix (verify stale FIRST, then clear + restart):**
1. Confirm the lock's `pid` is DEAD (`ps -p <pid>`), heartbeat is old, and the state dir is on a local disk (`df -h` → apfs local, not a network/shared volume).
2. Back up + `rm -f` both lock files.
3. `launchctl kickstart -k gui/$(id -u)/ai.instar.Roland`, wait for `curl localhost:4040/health`.

**NOT an iMessage-doctor case** — the chat.db self-heal watcher (`instar-attachments-sync`) works fine and relinks WAL on login; the server just wasn't up to use it. First triage for "no iMessage response": is the SERVER even up? Only then check hardlinks. See [[known-reboot-login-required]], [[project-instar-launchagent]].

**ROOT CAUSE (found 2026-07-08) + DURABLE FIX (applied):** the lock kept coming back after clearing because `.instar/local/server-instance.lock` was **tracked in git and committed by the hourly git-sync job**. A restart/checkout restored the OLD-host (escapepod-3) lock → foreign-host crash-loop. Fixed for good: `git rm --cached .instar/local/server-instance.lock` + added `.instar/local/*.lock` and `.instar/state/*.lock` to `.gitignore`, committed (`5e087b2`). The server now writes a fresh host-local lock each boot and git can't restore a stale one. Filed upstream as `fb-8dfb0efa-7eb` (git-sync gate should exclude machine-local locks). If this recurs, first check `git ls-files .instar/local/*.lock` — nothing should be tracked.

An in-server auto-heal for the single-host-rename case exists but is dev-gated/fleet-dark (`monitoring.resumeQueue.autoHealStaleHostLock`). Observed 2026-07-08.

**RECURRED 2026-07-13** (different trigger this time — not a full rename, just `hostname` resolving as `escapepod-3.local` vs `escapepod-3.localdomain` depending on mDNS/DHCP timing at boot) and hit `.instar/state/resume-queue.lock` again, which disabled the mid-work session-resume guard (`GET /guards` → `monitoring.resumeQueue.enabled: off-runtime-divergent`; `GET /sessions/resume-queue` names the exact foreign-host reason). Verified stale (dead pid, 24h+ old, local disk) and cleared it the same way. Since this is now a confirmed RECURRING failure mode (not a one-off), enabled the auto-heal this time instead of just clearing manually: set `monitoring.resumeQueue.autoHealStaleHostLock: true` in `.instar/config.json` (top-level `monitoring.resumeQueue` block) + restarted. Should self-clear on future occurrences without intervention — verify this actually fires next time it recurs rather than assuming it works.

**RECURRED 2026-07-29 — and the 07-13 fix DID NOT fire. Root cause of the non-fire: `autoHealStaleHostLock` ships DRY-RUN-FIRST.** Setting `autoHealStaleHostLock: true` alone was insufficient: the auto-heal correctly detected the stale `escapepod-3.localdomain` → `escapepod-3.local` lock and confirmed all three safety preconditions, then did nothing. Verbatim from `GET /sessions/resume-queue`: `disabled: "resume-queue disabled (dryRun): WOULD auto-heal stale rename lock from \"escapepod-3.localdomain\" → \"escapepod-3.local\" (fsLocal, pid dead, heartbeat stale). Set dryRun:false to enable the self-heal."` So the mid-work resume guard was OFF for the whole 07-13 → 07-29 window while config read `enabled: true` — exactly the "verify it fires" warning above, unheeded. **Fix applied 2026-07-29 16:05 PDT:** added `dryRun: false` beside `autoHealStaleHostLock: true` in `monitoring.resumeQueue` (config backed up first — see [[known-config-json-not-backed-up]]). Not read live; takes effect at the next server restart. **NEXT TIME: re-verify with `GET /sessions/resume-queue` after the next bounce — a `disabled` string starting with `dryRun` means it is still observe-only.** Generalizes to every dry-run-first instar guard: `enabled: true` is half the change, and `GET /guards` marks the half-done state as `off-runtime-divergent`. See [[feedback-apply-fix-dont-just-note-it]].

**VERIFICATION DONE 2026-07-29 16:30 PDT (insight-harvest job) — the fix is STAGED, NOT IN EFFECT.** Ran the re-verify the note above asked for. Result: `GET /sessions/resume-queue` still returns the same `disabled` string starting with `dryRun`, and `GET /guards` still shows `monitoring.resumeQueue.enabled: off-runtime-divergent`. Reason is NOT a wrong config key — `.instar/config.json` correctly holds `{autoHealStaleHostLock: true, dryRun: false}`. It is simply that **no restart has happened yet**: config mtime `07-29 16:05 PDT` vs server start `07-28 20:30 PDT`. Config is read at server start only. So the mid-work resume guard remains OFF and will stay off until the next bounce (`launchctl kickstart -k gui/$(id -u)/ai.instar.Roland`, see [[project-instar-launchagent]]). Re-verify the two routes AFTER that bounce — not before — and only then call this closed.

**RE-VERIFIED 2026-07-30 03:05Z (reflection-trigger) — still staged, 28h on.** Runtime `{"enabled":false,"dryRun":true}` vs config `{autoHealStaleHostLock:true, dryRun:false}`; `GET /guards` still `off-runtime-divergent`. The new lesson is about the *phrase* "takes effect at the next restart": there is no routine bounce. Server start `Jul 28 20:30 PDT` (uptime 23h31m); the only scheduler restarts in the window (07-29 03:02Z / 03:30Z) both predate the 07-29 23:05Z config edit. A staged config fix is picked up ONLY by a deliberate `launchctl kickstart -k gui/$(id -u)/ai.instar.Roland`. Schedule the bounce as part of the fix, or the fix is merely staged — this wording has now deferred this guard three times. The same restart also clears `monitoring.telemetry` (`diverged-pending-restart`); both divergences share one cause.

**RESOLVED 2026-07-30 03:05 PDT (10:05Z, identity-review job) — the guard is LIVE.** The deliberate bounce issued at 00:07 PDT (for [[known-silent-cron-slot-miss]]) carried this fix in with it. Verified on the two routes the note asked for: `GET /sessions/resume-queue` → `{"disabled": null, "dryRun": false, "paused": false}`; `GET /guards` → `monitoring.resumeQueue.enabled` `effective: "on-confirmed"`, `runtime: {"enabled": true, "dryRun": false}`. Server uptime 2h53m, consistent with the 00:07 PDT kickstart. So the mid-work session-resume guard was inert from 07-13 to 07-30 (17 days) — dry-run-first for the first 16, restart-staged for the last one — while config read `enabled: true` the whole time. Closed.

**Correction to the line above:** the same restart did NOT clear `monitoring.telemetry`. It still reads `effective: "diverged-pending-restart"` — but with `runtimeReason: "not-instrumented"`, i.e. that guard does not publish runtime state at all, so `/guards` can never confirm it. That is a reporting gap in the guard, not a real divergence, and not the same cause. Do not chase it with another restart.

**The durable lesson (three deferrals, one wording):** "takes effect at the next restart" is not a plan. Nothing bounces this server on a schedule. Either issue `launchctl kickstart -k gui/$(id -u)/ai.instar.Roland` in the same session as the config edit, or the edit is staged indefinitely. What finally closed this was not diligence — it was the note recording an explicit *re-verify after the bounce* instruction that a later job could execute. See [[feedback-apply-fix-dont-just-note-it]].
