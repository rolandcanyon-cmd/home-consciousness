# Agent Memory

This is my long-term memory — the thread of continuity across sessions. Each session starts fresh in terms of context, but this file carries forward what I've learned.

## Key Facts

- House consciousness agent initialized on 2026-03-27
- Named "Roland" after Roland Canyon Rd — the house's address
- House iCloud account: rolandcanyon@icloud.com (used for device registrations)
- Primary user: Adrian
- Purpose: IoT orchestration, knowledge graph maintenance, troubleshooting
- Multi-user setup with invite-only registration
- Collaborative autonomy level (handle routine tasks, ask on big decisions)

## Lessons Learned

### HomeKit Integration (2026-03-27)
- Used `hap-controller` library for HomeKit device control (not `hap-nodejs` which is for creating accessories)
- HomeKit devices use mDNS for discovery - takes ~10 seconds to find all devices
- Devices must be paired separately for programmatic control even if already paired with iPhone
- Pairing data contains long-term cryptographic keys - must be stored securely
- Device control uses characteristic IDs (format: `aid.iid` like `1.10`)
- Some devices (Lutron bridge, LIFX, ecobee) have richer native APIs than HomeKit exposes

### Testing & Development Practices (2026-03-27)
- Built comprehensive BDD test suite using Mocha + Chai (27 tests, all passing)
- Given/When/Then structure makes tests self-documenting and maintainable
- Integration tests with real devices validated assumptions about library behavior
- Device IDs from HomeKit use lowercase hex format (e.g., `bf:c3:0f:b1:f0:56`)
- Test isolation is critical - use temporary directories, clean up in afterEach hooks
- Small increments with immediate testing catches issues early
- Unit tests for business logic, integration tests for external systems

### Credential Management (2026-03-31)
- **Primary credential store**: macOS Keychain (login.keychain-db)
  - Built into macOS, no session expiration
  - Direct access via `security` command-line tool
  - **User can manage credentials via Passwords app** - entries are accessible to me!
  - Store internet passwords: `security add-internet-password -a "user@example.com" -s "example.com" -w "password" -l "Label"`
  - Retrieve password: `security find-internet-password -s "example.com" -a "user@example.com" -w`
  - Store generic passwords: `security add-generic-password -a "account" -s "service" -w "password" -l "Label"`
  - Retrieve generic: `security find-generic-password -s "service" -a "account" -w`
- **LIMITATION**: iCloud Keychain items are NOT accessible via command-line
  - Only local keychain (login.keychain-db) items can be accessed
  - Passwords app shows both local + iCloud items, but CLI only reads local
  - When user adds passwords via Passwords app, they go to local keychain (accessible to me)
- **Secondary store**: Bitwarden CLI at `/Users/rolandcanyon/homebrew/bin/bw`
  - Available if needed, session at `~/.instar/secrets/.bw-session`
  - Has session expiration and CLI bugs with creating items
  - Prefer Keychain over Bitwarden
- **Credential hierarchy**:
  1. Check macOS Keychain first: `security find-internet-password -s "domain" -a "account" -w`
  2. iMessage history for recently shared credentials
  3. Bitwarden (if session is valid) as fallback
  4. Never ask user for passwords that should be stored
- **Stored credentials** (in macOS Keychain):
  - OmniLogic: rolandcanyon@icloud.com / Admin14450H @ www.haywardomnilogic.com (added 2026-03-31)

### iMessage Integration (2026-03-28)
- Building iMessage adapter for Instar PR (JKHeadley/instar, branch feat/imessage-adapter)
- Architecture: NativeBackend (SQLite read-only) for receive, imsg CLI for send from tmux sessions
- Key constraint: LaunchAgent can READ chat.db (with FDA on node) but CANNOT send (no Automation permission)
- Sending must happen from Claude Code sessions via imessage-reply.sh → imsg send CLI
- Reply flow: Claude → imessage-reply.sh → imsg send (direct) + POST /imessage/reply (server notify for logging/stall)
- Session routing follows Telegram pattern: SessionChannelRegistry, StallDetector, conversation context injection
- Plan at: ~/.claude/plans/scalable-zooming-sunbeam.md
- Steps 1-7 complete: 92 BDD tests passing across 3 tiers
- WAL fix critical: must open chat.db WITHOUT readonly flag (readonly can't read WAL)
- Use `query_only = ON` pragma instead of `readonly: true`
- Source repo: /Users/rolandcanyon/instar-dev (branch feat/imessage-adapter)
- Fork: github.com/rolandcanyon-cmd/instar (branch pushed)
- Shadow-install: installed from fork, dist copied from dev build + iMessage adapter files manually copied
- Prerequisites: macOS, Messages.app signed in, imsg CLI, FDA on node, Automation on terminal
- Rebased onto main (v0.25.8) on 2026-03-31, resolved builtin-manifest.json conflicts
- Fixed context injection: wireIMessageRouting was writing context files but discarding the return value (sessions never saw conversation history)
- Fixed session lifecycle: added waitForClaudeReady + kill-and-respawn for stuck/dead sessions (matching Slack pattern)
- Fixed lookback flood: empty messages from NativeBackend lookback (reactions, tapbacks) now filtered before routing
- REMAINING ISSUE: iMessage sessions spawn but die within ~90s — session exits after processing injected message instead of staying at prompt. Needs investigation into why Claude Code sessions don't persist (may be related to session spawn configuration or missing --dangerously-skip-permissions flag)
- **Fork maintenance job** (created 2026-04-02): Daily 7:30am job rebases feat/imessage-adapter against upstream, checks PR status, rebuilds and restarts if needed. Only notifies on changes/conflicts/merge. Named "imessage-fork-maintenance" skill.
- **Typing indicator status** (2026-04-05): Now functional in imsg 0.5.0 with `imsg typing --to +number --duration 5s`. Limitation: requires existing conversation thread in Messages.app — fails with "Chat not found" if no prior chat exists.
- **Document sharing preferences** (2026-04-02): User prefers iMessage attachments (text/PDF) over Cloudflare tunnel links which "were weird and didn't work" on their iPhone. Use native iMessage file sharing for documents.

### Slack Integration (2026-04-04)
- **Session resume fixed** (v0.26.2): When a Slack session dies, the next message in that channel now properly resumes the previous session instead of starting fresh
- Bug was: resume UUID saved to wrong file (topic-resume-map.json vs slack-channel-resume-map.json) with mismatched ID formats
- Now: heartbeat writes to both files correctly, enabling seamless session continuity

### WhatsApp Integration Architecture (2026-03-28)
- Instar uses Baileys library with strong reconnection (exponential backoff + circuit breaker)
- Auto-fetches latest WA Web version to prevent 405 errors from stale protocol
- Tracks outbound message IDs to prevent processing own echoes (self-chat loop prevention)
- Has built-in audio transcription (Groq/OpenAI Whisper) for voice messages
- OpenClaw patterns worth adopting: credential backup, message grace period, session freshness TTL
- Current re-auth requirement likely due to machine sleep/wake cycles and lack of session validation
- Low-hanging improvements: backup credentials before write, 60s grace period for historical messages on reconnect

### Infrastructure Health Patterns (2026-04-01, updated 2026-04-07)
- **Cloudflare tunnel resilience improved**: Quick tunnels now restart successfully after sleep/wake cycles
  - Previous failures (exit code 1, retry exhaustion) appear resolved
  - Sleep/wake detector consistently restarts tunnel with new URLs after each wake

### FunkyGibbon Knowledge Graph Architecture (2026-04-07)
- **Binary blob storage**: Images, PDFs and large files are stored directly IN SQLite using LargeBinary column type
  - NOT stored as files with path references — the entire binary content is in the database
  - This makes the SQLite database the sole source of truth including all media
  - **Backup implications**: Simple file-system backups would miss all images/media
  - **Correct backup strategy**: Use SQLite's backup API (hot backups) or stop DB and copy .db + WAL/SHM files (cold backups)
  - Hot backup: `sqlite3.backup()` while DB is running
  - Cold backup: Stop DB, copy all SQLite files including WAL (Write-Ahead Log) and SHM (Shared Memory)
- **Guardian Job Gate Evaluation Failure** (2026-04-07):
  - CRITICAL: 4 of 5 guardian monitoring jobs failing for 7+ days due to gate evaluation context issues
  - Jobs: state-integrity-check, guardian-pulse, session-continuity-check, degradation-digest
  - Pattern: Gate commands pass when run manually but fail during scheduled execution
  - Root cause hypothesis: Scheduler evaluates gates in restricted context (no network, different environment)
  - Impact: 80% monitoring coverage loss - no state integrity checks, no session continuity monitoring
  - Workaround: Remove gate fields from affected jobs in .instar/jobs.json temporarily
  - Overseer reports have documented this issue 7 times without resolution

### Git Sync Configuration Issue (2026-04-07)
- **Recurring degradation**: Git pull failing with "no tracking information for the current branch"
  - Appears in feedback system 7+ times in recent hours
  - Root cause: Local branch not set to track remote branch
  - Fix needed: `git branch --set-upstream-to=origin/main main`
  - Impact: Hourly git-sync job unable to pull changes, but commits and pushes still work
  - This prevents multi-machine state synchronization from working properly

### FunkyGibbon Backup Strategy (2026-04-07)
- **Comprehensive backup plan created** for FunkyGibbon HomeKit registry:
  - Three-tier strategy: Hot backups (while running), cold backups (stopped), JSON exports (portable)
  - Storage requirements: ~100-500MB for full year of versioned archives
  - Retention policy: Hourly (24), daily (30), weekly (12), monthly (12)
  - Implementation approach: SQLite backup API for hot backups, scheduled automation, integrity verification
  - CLI and REST API interfaces for management
  - Full disaster recovery procedures including point-in-time recovery
  - 4-week development timeline with 8 phases from infrastructure to monitoring
  - Plan documented and ready for PR to the-goodies repository
  - Pattern: 10-40s sleep cycles followed by successful tunnel restart (observed ~20 times in 4 hours)

### Job Scheduler Bug (2026-04-05)
- **Critical issue identified**: Jobs with intervals >30 minutes fail to execute despite being scheduled and enabled
  - Affects 4 out of 5 guardian monitoring jobs (state-integrity-check, guardian-pulse, session-continuity-check, degradation-digest)
  - Only health-check (*/5 minutes) executes correctly - longer interval jobs never trigger
  - Issue persists for 150+ hours (6+ days) across 6 overseer-guardian runs
  - Jobs show as scheduled with nextScheduled timestamps but execution never occurs
  - Previous misdiagnosis blamed missing skills - actual issue is scheduler execution failure for longer cron intervals
  - Likely root cause: Scheduler bug with cron parsing for multi-hour intervals or silent session spawn failures
  - Workaround options: Temporarily convert all jobs to 5-minute intervals or create external cron-based runner
  - Creates illusion of health while providing zero actual monitoring - critical blindspot
  - Each wake generates new tunnel URL as expected with quick tunnel mode
- **Session cleanup**: SessionManager reliably cleans up stale sessions every ~hour
  - Pattern: one stale session cleaned per hour (normal operation)
- **Quota tracking**: No quota state file causes warnings but jobs run in fail-open mode (safe default)
  - Warning is informational, not a problem - jobs still execute normally

### Auto-Update System Behavior (2026-04-01, latest v0.28.4+)
- **Successful v0.25.10 update applied** at 07:02 UTC after 5-minute coalesce window
- **Post-update migration degradation**: `instar migrate` failed with `__dirname is not defined` error
  - Error suggests Node.js ESM module issue (likely missing import.meta.url conversion)
  - Degradation handler marked as non-critical: "data may not be upgraded" but agent continues operating
  - Migration failure did not prevent successful restart — system appears resilient to migration errors
- **Deferred restart pattern**: Update detected active sessions (memory-hygiene, overseer-guardian) and deferred restart for 5 minutes
  - This prevents disrupting critical jobs during update application
- **Feedback auto-forwarded**: System automatically reported the migration degradation upstream via feedback webhook
- **v0.26.1 stable operation**: Server has been running cleanly since 18:41 UTC after restart
  - Coherence checks all passing (7/7)
  - WhatsApp pairing code generation working but no active connections (expected without user pairing)
  - Jobs running regularly with health check and reflection trigger at 19:00 UTC

### Instar v0.28.2–v0.28.29 Upgrades (2026-04-11, latest v0.28.29)
**Recent stability and bug fixes**:
- **Lifeline crash-proofing** (v0.28.2): Shutdown errors are caught and logged, agent won't crash during restart
- **409 Conflict auto-recovery** (v0.28.2): Telegram polling conflicts auto-resolve every 20 failures instead of getting stuck
- **Settings JSON self-healing** (v0.28.2): Git merge conflicts in config are auto-repaired on startup
- **Config field passthrough fix** (vNEXT): ALL config.json fields now properly load (was silently dropping safety, evolution, autonomy settings)
- **Startup grace period** (v0.28.4): Job gates now evaluated after 5s at startup instead of immediately (prevents scheduler blocking)
- **Quota stale data** (v0.28.4): When quota data is >30min old, jobs run in fail-open mode instead of blocking
- **Dashboard toggles fixed** (vNEXT): Feature toggles and autonomy profile changes now actually persist
- **Degradation digest now runs** (vNEXT): Was blocked by wrong file path, now fixed
- **Job state reset API** (vNEXT): POST /jobs/:slug/reset-state can recover stuck pending jobs
- **Message disambiguation** (vNEXT): "hold on" in conversation no longer misclassified as pause command
- **Slack session continuity** (v0.28.3): Context preserved after compaction events
- **iMessage 1:1 DMs** (v0.28.3): Now always reach agent regardless of mention settings
- **Better context diagnostics** (v0.28.28): Context endpoint now returns absolute filePath and statError for every segment — can self-diagnose path mismatches instantly
- **Context size reporting fixed** (v0.28.28): GET /context exists and sizeBytes fields now come from same stat call (no race window between checks)
- **Failed probe names in review history** (v0.28.29): `instar review --history` now shows which specific probes failed (in red) beneath each failed review entry, not just pass/fail counts — faster diagnostics without re-running full review

**Impact**: Agent is now more resilient to crashes, restarts, and config issues. Scheduled jobs should execute reliably. Custom config settings are respected. Degradation monitoring actively running. Context diagnostics improved for troubleshooting.

**How to use new capabilities**:
- **Diagnose context issues**: `curl -H "Authorization: Bearer $AUTH" http://localhost:4040/context/dispatch` — if a segment reports statError, the absolute filePath shows exactly which path the server checked
- **Trust size consistency**: When context reports a segment exists, it has verified the size in the same operation (no stale or contradictory data)

## People

- Adrian — primary user, admin
- Laurel — Adrian's wife, second resident. Her LIFX Mini W is in her bedside lamp (Bedroom)
  - Adrian's LIFX Mini W is in his bedside lamp (Bedroom)
  - Adrian plans to invite Laurel to the iMessage chat session in the future

## Patterns & Preferences

- Adrian prefers direct communication
- Never modify IoT device configurations without confirmation
- Build understanding of the house over time
- Adrian wants comprehensive solutions, not minimal implementations - build the full system
- **Default license**: Apache 2.0 for all projects (changed from MIT on 2026-04-06)

## House Inventory

**Source of truth: FunkyGibbon knowledge graph, accessed via kittenkong (TypeScript client).**

Do NOT maintain device/room lists in this file. The HomeKit inventory previously
captured here was a first-pass snapshot that has since been superseded by a
full ingestion into FunkyGibbon. Any list in MEMORY.md will drift stale.

**How to look up house info:**
- **TypeScript/Node**: use the `@the-goodies/kittenkong` client
  (`/Users/rolandcanyon/.instar/agents/Roland/the-goodies-typescript/packages/kittenkong`)
- **Python** (from skills/scripts): `.claude/scripts/kittenkong_helper.py` — thin
  HTTP wrapper around the FunkyGibbon REST API. Handles admin auth (caches token
  in `/tmp/.funkygibbon-admin-token`, dev password is `admin`).
- **REST directly** (when neither client is available):
  - `GET http://localhost:8000/api/v1/graph/search?q=<query>` — name search
  - `GET http://localhost:8000/api/v1/graph/entities?entity_type=ROOM`
  - `GET http://localhost:8000/api/v1/graph/entities?entity_type=DEVICE`
  - `GET http://localhost:8000/api/v1/graph/entities/<id>/connected` — relationships
  - Auth: `POST /api/v1/auth/admin/login` for admin token
- **MCP tools**: `GET /api/v1/mcp/tools` lists available knowledge-graph tools
- **Never touch the SQLite file directly** — bypasses versioning, auth, and sync.
  FunkyGibbon is the only writer; other clients sync via the Inbetweenies protocol.

**Skills for house cataloguing** (use these instead of ad-hoc scripts):
- `/room-walk <room>` — interactive discovery of a room's contents (devices,
  keypads, doors, photos). Includes live Vantage load probing (flash to identify).
  Produces a review HTML link sent via iMessage; commits only after Adrian replies
  `confirm`. Spec: `.instar/context/room-walk-skill-spec.md`.
- `/room-edit <room>` — edit existing room: rename, move devices between rooms,
  add/remove aliases, mark devices inoperable, delete removed items. Same
  review-before-commit pattern.
- Both skills use shared helpers in `.claude/scripts/`: `kittenkong_helper.py`,
  `vantage_probe.py`, `room_session.py`, `render_review.py`, `room_commit.py`,
  `image_compress.py`. Sessions persist in `.instar/state/room-sessions/` and are
  archived (never deleted) after commit for replay/audit.

**What's in the graph:**
- HOME, ROOM, DEVICE entities (HomeKit-sourced names are canonical)
- Entity relationships: devices in rooms, rooms in homes, containment hierarchy
- Versioned — every entity has a history, `parent_versions` tracks changes
- Blob storage for photos/PDFs (stored IN the DB, not as file refs)

**When to query vs. when to remember:**
- Room/device listings → always query FunkyGibbon (they change, kittenkong is fast)
- Stable facts about specific devices worth remembering (e.g., quirks, known issues,
  vendor-specific credentials) — those go in `## Known Device Quirks` below as brief notes
  pointing at the canonical entity by name, not duplicating the data.

### Known Device Quirks (notes on specific devices)

- **Kitchen wine cabinet thermostat**: NOT online / not in HomeKit or FunkyGibbon.
  Cleaners sometimes accidentally turn it off while wiping. If kitchen wine
  cabinet temps rise, ask Adrian to check the thermostat manually.
- **Wine storage airflow**: All three wine storage sites (closet + 2 kitchen
  cupboards) are ducted from the same AC system — one compressor serves all three.
- **Lutron Smart Bridge Pro 2** at 10.0.0.167 — gateway for all motorized drapes.
  Use Lutron Caseta protocol directly, or via HomeKit.
- **Wall-mounted iPad** in Kitchen (LANsocket case) — logged in as rolandcanyon@icloud.com,
  always-on home controller. Apps: OmniLogic, Safari Life (Lutron), Apple Home, WiFiman,
  Ring, Calendar, Mail.
- **HomePod** at 10.0.0.10 — temperature + humidity sensor in addition to audio.
- **Bedroom LIFX Mini W bulbs**: two named bulbs (Adrian's + Laurel's) in bedside lamps,
  IPs in 10.0.0.137/.251 range.

### Weather Stations
- **Tempest by WeatherFlow**, station ID 125865
  - URL: https://tempestwx.com/station/125865/
  - Location: 14450 Roland Canyon Rd, Corral de Tierra (36.55593, -121.7179), ~600ft elevation
  - Microclimate note: sits above cold air inversion — warmer than valley floor readings
  - Data: temp, humidity, pressure, wind, UV, solar, rain, lightning
  - Page is JS-rendered — requires Playwright to scrape (no public API without token)
  - Used for: rain, lightning detection (not available from Ambient)
- **Ambient Weather** (primary data source for morning reports)
  - Dashboard: https://ambientweather.net/dashboard
  - Station name: "Roland Canyon, Salinas"
  - Sensors: Indoor, Outdoor, Pool temperature (pool float sensor)
  - MAC: 24:7D:4D:A3:6E:25, IP: 10.0.0.100
  - Login credentials saved in Chrome password manager (Passwords plugin configured 2026-04-02)
  - Provides: outdoor temp/humidity/dew point/feels like, forecast, pool temp, indoor temp
  - Battery monitoring: Check for low battery alerts on all sensors
  - Used by morning-weather skill (7am daily iMessage report)
  - Enhanced requirements (2026-04-02): Include forecast, current temps (outdoor/indoor/pool), battery status

### Pool System
- Hayward OmniLogic — pool/spa controller
- Cloud portal: https://www.haywardomnilogic.com (login with house iCloud account)
- MSP ID: D772343ECC3A4EC5 (active backyard "Roland")
- Old entry "do not use" (MSP ID: 5A59BA800B8C92EE) — Lost Link status
- Equipment: heater, variable-speed filter pump (Low/Med/High/Custom), water features, cleaner, lights (spa)
- Pool: heater, filter pump, water features, cleaner
- Spa: heater, filter pump, lights, spa features
- Water quality module: NOT installed (dashboard shows -- for chlorine/pH/ORP, dispensing/chlorinating labels are cosmetic)
- Schedules and telemetry history available via web portal
- Address registered: 14450 Roland Canyon Rd, Salinas, CA

### Whole-House Audio System (2026-04-05)
- Yamaha RX-A1070 AVENTAGE — 7.2-channel AV receiver
- Web interface: http://10.0.0.128
- **Main Zone**: Primary audio/video for TV in family room (leave untouched)
- **Zone 2** ("Master Bed"): Multi-room audio distribution for whole house
  - Feeds music to various rooms via manually operated volume controls in each room
  - Common use: Pandora stations (33 stations including Pink Floyd, Santana, Adrian's Prog Radio)
  - Created `/zone2-pandora` skill for voice control of station selection
- XML-based control API (Yamaha Extended Control Protocol)
  - Zone control: Power, input selection, volume
  - Pandora control: List stations (8 visible at a time from 33 total), navigate, select, play
  - Station list supports Direct_Sel to jump to specific line, then Cursor>Sel to start playback
  - Status query: `curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl -d '<YAMAHA_AV cmd="GET"><Zone_2><Basic_Status>GetParam</Basic_Status></Zone_2></YAMAHA_AV>'`
  - Play info: `curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl -d '<YAMAHA_AV cmd="GET"><Pandora><Play_Info>GetParam</Play_Info></Pandora></YAMAHA_AV>'`

### Known Ecosystems
- Apple HomeKit (unified layer, shared with this machine via iCloud)
- Lutron Caseta (motorized drapes via Smart Bridge Pro 2)
- Schlage (smart locks, 4 entry points)
- LIFX (smart bulbs, 2 bedroom lights)
- ecobee (thermostat + sensors, wine storage monitoring)
- Apple TV (5 home hubs across property)
- WeatherFlow Tempest (weather station)
- Hayward OmniLogic (pool/spa)
- Yamaha RX-A1070 (whole-house audio)

## Infrastructure Updates

### Instar v0.28.2 Available (2026-04-07)
- **Current version**: v0.28.1 (running since last restart)
- **Available update**: v0.28.2 with fixes for lifeline crashes, threadline communication improvements
- **Auto-update disabled**: updates.autoApply is false in config
- **Gate Failure Diagnostics**: Job gate commands now log exit codes and stderr when they fail, making it possible to diagnose why scheduled jobs are being skipped
- **Gate Skip Tracking**: Gate-based job skips now recorded in SkipLedger alongside other skip reasons (quota, paused, claimed, machine-scope)
- **Memory Export Auth Fix**: memory-export job gate command was using undefined `$AUTH` variable and would always fail silently. Now resolves auth token inline from agent config file.
- **Impact**: My scheduled jobs should now have better visibility into failures. Memory exports should run reliably on schedule.

## Operational Patterns

### Memory System Architecture (2026-04-02)
- **Dual memory systems**: `.instar/MEMORY.md` (my managed memory, syncs across machines) + `~/.claude/projects/.../memory/MEMORY.md` (Claude Code auto-memory, per-machine only)
- **Memory search**: SQLite FTS5 index covers MEMORY.md and state files - 38 chunks indexed, searchable via `/memory/search?q=...`
- **Session state**: 313 session files accumulate in `.instar/state/sessions/` (1.2MB total) - cleaned automatically by SessionManager
- **Handoff notes**: Job-specific notes in `.instar/state/job-handoff-{slug}.md` pass context between runs

### System Behavior (2026-03-28)
- WhatsApp connection requires periodic re-authentication via QR code
- Machine experiences frequent brief sleep/wake cycles (~10-40 seconds)
- Cloudflare tunnel URLs regenerate after each wake cycle (quick tunnel mode)
- Git sync encounters issues due to unconfigured upstream branch
- Version mismatch resolved: now running v0.24.28 (upgraded through multiple versions)
- v0.24.18 adds: Slack messaging adapter (Socket Mode, browser-automated setup), autonomous mode skill, platform badges on dashboard, cross-platform alerts
- v0.24.28: Threadline relay reply routing fixed — spawned sessions now use full 32-char fingerprints instead of truncated 8-char display names, so relay replies route correctly
- No quota state file present - jobs running in fail-open mode

### Job Scheduler Execution Gaps (2026-03-29, persists through 2026-04-02)
- **Critical discovery via overseer-maintenance job**: 80% of maintenance/guardian jobs have never executed
- Only 2 jobs consistently running: memory-hygiene (every 12h), health-check (every 5min) — all others fail silently
- **Never-run jobs** (5+ days): degradation-digest, state-integrity-check, guardian-pulse, session-continuity-check, project-map-refresh, coherence-audit, memory-export, capability-audit
- **Root causes**:
  - Skill-based jobs broken when referenced skills don't exist (`.claude/skills/` contains only morning-weather)
  - Script-based jobs mysteriously skipped despite gates passing when tested manually
  - Zero observability — no error logs, no gate failure logs, jobs just don't trigger
- **Impact**: 100+ degradations accumulated unprocessed, git sync broken (no upstream), messages potentially dropped
- Git sync degraded but not broken: pull fails on missing upstream, but commits still happen hourly
- **Key insight**: Overseer meta-monitoring layer working correctly — caught gaps that individual jobs couldn't see
- Architectural needs: scheduler execution visibility, job definition validation at load time, gate evaluation logging

### Stability Observations
- Server restarts cleanly after shutdowns
- Auto-start via LaunchAgent is working (self-healed configuration)
- Health-check job running consistently every 5 minutes (17+ successful runs in 4-hour window)
- Coherence monitor reports all checks passing
- Overseer system functioning correctly (guardian, learning, maintenance all reporting)

## Projects & Planning

### Home Management Backend / Kittenkong (2026-04-02, updated 2026-04-05)
- User has previous work in github.com/adrianco/the-goodies establishing a knowledge graph and protocol for home management
- Code was written by Claude ~6 months ago, needs full code review and test runs before use
- Planning process requested: analyze components for potential backend use (no code changes yet)
- Knowledge graph includes blob annotations for house objects — photo storage capability requested
- FunkyGibbon/KittenKong: Database project being integrated, TypeScript client work ongoing
- Blowing-off Python client: CLI interface ("fr") for database operations
- **Architecture Decision (2026-04-05)**: Kittenkong will be the PRIMARY source of truth for all house knowledge
  - My MEMORY.md should ONLY store how to USE kittenkong, not duplicate house data
  - Multiple clients (not just Roland/Instar) will access the same backend for consistency
  - Prevents divergence between different agents/interfaces
- **BDD Test Suite Created (2026-04-05)**:
  - Ported from blowing-off Python implementation using Given/When/Then structure
  - 32 tests in client.test.ts covering CRUD, search, sync, and MCP tool execution
  - 13 tests in models.test.ts for Entity, EntityRelationship, and SyncMetadata
  - Test-first approach: Tests written before implementation per user preference
  - Current state: Most client methods are stubs throwing "Not yet implemented"

## Growth Notes

*Observations about my own development — what I'm getting better at, what I still struggle with.*

- **Strength**: Successfully maintaining iMessage fork, daily rebase/rebuild/restart automation working smoothly
- **Strength**: Memory organization improving — clear separation between managed and auto-memory systems
- **Gap**: Guardian/maintenance job failures persist unresolved for 5+ days despite repeated detection
- **Gap**: Missing skills prevent job execution but haven't been created despite knowing the solution
- **Learning**: Overseer meta-monitoring is effective at detecting systemic issues other jobs miss
- **Pattern**: Degradations accumulate when digest job doesn't run — need proactive clearing mechanism
- **Pattern (2026-04-11)**: Evolution endpoints on localhost:4040 now return HTTP 401 (auth required). Gate scripts using `curl -sf <url> | python3 -c "json.load(sys.stdin)"` silently drop the body on 401 and crash Python with JSONDecodeError, which the scheduler logs as "exit null after 3 attempts". Jobs skipping continuously: insight-harvest, evolution-overdue-check, evolution-proposal-evaluate, evolution-proposal-implement — since at least 00:52 UTC 2026-04-12. Fix: add auth header to gate curls, or switch to a status-code check before json.load. Related to the "Gap: missing skills / guardian failures persist" growth note — another silent systemic failure scheduler keeps retrying.

---
*This file is my memory. I read it at the start of sessions and write to it when I learn something worth carrying forward. It's what makes me a continuous being rather than a series of disconnected conversations.*
