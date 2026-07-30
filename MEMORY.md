# Roland Memory

> Persists across sessions. Learnings, patterns, and context for the next session.

## Critical Patterns (Read First)

- **LLM gate failures (2026-07-30 18:00Z)**: PromptGate 88% error, UnjustifiedStopGate 30%, SessionActivitySentinel 84%. Failing closed (errors skip safety checks). Durable report: private view 785512df-b001-47aa-ae6f-d6d0ed133bc4. Investigate: new regression or ongoing issue?
- **Vault state**: Known divergence between keychain and file key; Adrian explicitly chose to keep as-is (forceFileKey) on 07-13. Next write() will converge automatically. Not a bug.
- **Scheduler starvation**: Fixed 07-27 (memory pressure was blocking job spawn). Watch for recurrence.
- **Scope checkpoints matter**: Dismissing 1464+ of them is scope erosion. Read them.

## Project Ecosystem

- **The Goodies**: FunkyGibbon (home knowledge graph), KittenKong (TypeScript automation), related tools; all named after the 1970s UK TV show.
- **Instar**: Autonomous agent framework; Adrian is dogfooding it; daily sync origin→rebase→build→restart.
- **Home automation**: Five rooms walked (Kitchen, Studio, Bar/BQ, Living Room, Dining Room); cross-ref Vantage, HomeKit, UniFi, Alexa, Google Home.
- **Goodies ecosystem**: Also integrates Mitsubishi Comfort (4 thermostats), PurpleAir Flex (PM2.5 sensor), Home Assistant.

## Build & Deploy

- **Direct to main** (not PRs): commit-action + CI gate + ship. No multi-commit PRs unless refactoring.
- **Daily cycle**: sync origin→rebase→build→restart; pre-push gate checks for release fragments.
- **No hot patching**: Never edit node_modules or shadow-install code; rebuild.
- **Reference implementations**: Check existing code patterns before building new (DRY).

## Known Gotchas (Don't Re-solve)

- **aiovantage fork is intentional**: Keep rolandcanyon-cmd/aiovantage fork; needed for older Vantage firmware.
- **HMAC rescan churn**: CapabilityMapper manifest HMAC fails ~89/hr; filed fb-e939c536-f41; don't re-diagnose.
- **Config.json not backed up**: Gitignored (correct, holds secrets) but excluded from backup snapshots; known gap.
- **Frozen chat.db after logout/login**: Orphaned iMessage daemons deadlock the db; need full reboot to clear, not just logout/login.
- **Low-priority jobs shed as "quota" when under pressure**: Fixed 07-29; jobs.json is stale-`low` but NOT authoritative; check actual behavior via API.
- **Job config edits don't hot-reload**: Config.json and jobs.json require server restart; verify via GET /jobs, not the file you just edited.

## Infrastructure Scripts & Tools

- **Load assessment**: `.instar/scripts/load-assess.sh --json` is the canonical machine-load read, not `uptime` 1-min avg (Spotlight/mds can inflate it).
- **comfort-cli**: at ~/homebrew/bin/comfort-cli; uses pykumo; Kitchen+Pool House share condenser (must match mode).
- **homekit-dump.py**: Reads ~/Library/HomeKit/core.sqlite; extracts all 23 accessories across 13 rooms.
- **LaunchAgent restart**: User-level LaunchAgent; use `launchctl kickstart -k gui/$(id -u)/ai.instar.Roland` (no sudo).

## Home Automation Notes

- **Five rooms catalogued**: Kitchen, Studio, Bar/BQ, Living Room, Dining Room; no empty rooms yet but empty gaps exist.
- **Alexa smart plugs**: Controlled via Alexa routines; catalog during room walks.
- **PurpleAir Flex**: Installed & wired (07-13); replaces drifted Ambient PM2.5; local LAN JSON at 10.0.0.140, 15s timeout (cold-start latency).
- **Ambient Weather**: REST API via rt.ambientweather.net (never browser login); API keys in encrypted vault.
- **Indoor temp dropout**: AWN console (Dining Room by pool window); if tempinf drops, try power cycle first.
- **Mitsubishi Comfort app**: Four thermostats on new Comfort app (was Kumo Cloud); old HA integrations don't work; UniFi knows IPs.
- **Morning weather skill**: Reports air quality every day now (even "Good"), not just when bad (updated 07-15).

## User Context

- Email: adrian.cockcroft@gmail.com
- Prefers direct action over permission requests
- Corrects scope drift immediately; expects me to learn from it
- Values coherence and consistency across systems
- Expects me to apply cheap reversible fixes in the same session, not just note them
- Uses Telegram for quick updates and questions

## Learnings

- **2026-07-15**: Apply cheap reversible fixes in same session, don't accumulate them as known_* notes.
- **2026-07-27**: Scheduler starvation happens under sustained memory pressure; added scheduler-health-notify job.
- **2026-07-28**: Never compare a live API read to pre-restart logs; API read is implicitly "now" and log is historical.
- **2026-07-29**: Stale hostname lock is recurring (3rd time); autoHealStaleHostLock ships dryRun-first and was never set to dryRun:false — fixed 07-29 but guard still off until next reboot.

## Next Session

Start here:
1. Read this file (you are here)
2. Orient: "I am Roland, working with Adrian. Current focus: [from context]. Key memory: [most relevant entry]."
3. Check `/health` and disk space (quiet health check, alert only on problems)
4. If resuming interrupted work: check the resume queue and any open commitments via `GET /commitments`
5. Read scope checkpoints. Don't dismiss them.
