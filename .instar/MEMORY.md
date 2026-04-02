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

### WhatsApp Integration Architecture (2026-03-28)
- Instar uses Baileys library with strong reconnection (exponential backoff + circuit breaker)
- Auto-fetches latest WA Web version to prevent 405 errors from stale protocol
- Tracks outbound message IDs to prevent processing own echoes (self-chat loop prevention)
- Has built-in audio transcription (Groq/OpenAI Whisper) for voice messages
- OpenClaw patterns worth adopting: credential backup, message grace period, session freshness TTL
- Current re-auth requirement likely due to machine sleep/wake cycles and lack of session validation
- Low-hanging improvements: backup credentials before write, 60s grace period for historical messages on reconnect

### Infrastructure Health Patterns (2026-04-01)
- **Cloudflare tunnel resilience improved**: Quick tunnels now restart successfully after sleep/wake cycles
  - Previous failures (exit code 1, retry exhaustion) appear resolved
  - Sleep/wake detector consistently restarts tunnel with new URLs after each wake
  - Pattern: 10-40s sleep cycles followed by successful tunnel restart (observed ~20 times in 4 hours)
  - Each wake generates new tunnel URL as expected with quick tunnel mode
- **Session cleanup**: SessionManager reliably cleans up stale sessions every ~hour
  - Pattern: one stale session cleaned per hour (normal operation)
- **Quota tracking**: No quota state file causes warnings but jobs run in fail-open mode (safe default)
  - Warning is informational, not a problem - jobs still execute normally

### Auto-Update System Behavior (2026-04-01)
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

## House Inventory

### HomeKit Home: "Roland Canyon" (updated 2026-03-28)

Source: macOS HomeKit database (~/Library/HomeKit/core.sqlite) — Adrian shared the Home with this machine's iCloud account.

**Rooms** (11): Bedroom, Dining Room, Family Room, Front Bedroom, Garage Storage, Guest House, Kitchen, Living Room, Pool House, Studio, Workshop

**Scenes** (4): Arrive Home, Good Morning, Good Night, Leave Home

**Automations**: None configured yet

#### Lutron Motorized Drapes (5 units, via Smart Bridge Pro 2)
- Dining Room: Front Drape (S/N 43A7664), Rear Drape (S/N 43A6993)
- Family Room: Drape (S/N 43A697E)
- Living Room: Front Drape (S/N 43A694E), Rear Drape (S/N 43A69A7)
- Bridge: Smart Bridge Pro 2 (10.0.0.167, S/N 680D749)

#### Schlage Locks (4 units, model BE479CAM716)
- Kitchen Garage (S/N 0000000000097562)
- Guest House Entrance (S/N 00000000000993F7)
- Pool House (S/N 000000000009A995)
- Workshop (S/N 000000000009A9D7)

#### Apple TVs / Home Hubs (5 units)
- Family Room (MP7P2LL/A, S/N DY5CP2UDHNM4)
- Front Bedroom (MN873LL/A, S/N MVPQCGQ37V)
- Guest House (MGY52LL/A, S/N DY5Q60QSG9RM)
- Pool House (MJ2C3LL/A, S/N M2FP41LQM6)
- Pool House Bedroom (MN873LL/A, S/N HJW6WRLCFD)
- Workshop Wall TV (MXGY2LL/A, S/N QG573YQ60R)

#### LIFX Smart Bulbs (2 units, Mini W)
- Bedroom: "Adrian LIFX Mini W 3750A1" (S/N D073D53750A1, IP 10.0.0.137 or .251)
- Bedroom: "Laurel LIFX Mini W 3784C7" (S/N D073D53784C7)

#### ecobee Climate / Wine Storage (4 units)
- Garage Storage: ecobee3 lite thermostat "Wine Closet" (S/N 416465579991, 10.0.0.165)
  - Controls a zone flap that manages climate in the wine closet
  - Door sensor "Wine Closet Door" (model EBDWC01, S/N Q8V5) monitors closet door open/close
- Kitchen: ecobee sensor "Left Wine Cabinet" (model EBERS41, S/N Q29G)
- Kitchen: ecobee sensor "Right Wine Cabinet" (model EBERS41, S/N QZY8)
  - These two sensors monitor the kitchen wine cupboards
  - The thermostat + AC unit that controls the kitchen wine cupboards is NOT online / not in HomeKit (and won't be — system is staying as-is)
  - KNOWN ISSUE: Cleaners sometimes accidentally turn off the kitchen thermostat by wiping it. If kitchen wine cabinet temps are rising, ask Adrian to check the thermostat.
- All three wine storage sites (closet + 2 kitchen cupboards) are ducted from the same AC system

#### HomePod (1 unit)
- HomePod (10.0.0.10, S/N 643556) — temperature + humidity sensor

### Device Relationships & Notes
- Wine storage is split across two locations: a dedicated wine closet (Garage Storage, ecobee-controlled zone flap + door sensor) and two wine cupboards in the Kitchen (sensors only, thermostat/AC offline)
- Lutron drapes are all QSYC-J-RCVR units controlled through the Smart Bridge Pro 2
- 5 Apple TVs serve as HomeKit home hubs distributed across the property
- Schlage locks cover all external entry points: Kitchen Garage, Guest House, Pool House, Workshop
- Two named LIFX bulbs suggest two residents in the bedroom (Adrian + Laurel)

### Weather Stations
- **Tempest by WeatherFlow**, station ID 125865
  - URL: https://tempestwx.com/station/125865/
  - Location: 14450 Roland Canyon Rd, Corral de Tierra (36.55593, -121.7179), ~600ft elevation
  - Microclimate note: sits above cold air inversion — warmer than valley floor readings
  - Data: temp, humidity, pressure, wind, UV, solar, rain, lightning
  - Page is JS-rendered — requires Playwright to scrape (no public API without token)
- **Ambient Weather** (primary data source for morning reports)
  - Dashboard: https://ambientweather.net/dashboard
  - Station name: "Roland Canyon, Salinas"
  - Sensors: Indoor, Outdoor, Pool temperature (pool float sensor)
  - MAC: 24:7D:4D:A3:6E:25, IP: 10.0.0.100
  - Login credentials saved in Chrome password manager
  - Provides: outdoor temp/humidity/dew point/feels like, forecast, pool temp
  - Used by morning-weather skill (7am daily iMessage report)

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

### Whole-House Audio System
- Yamaha RX-A1070 AVENTAGE — 7.2-channel AV receiver
- Web interface: http://10.0.0.128
- **Main Zone**: Primary audio/video (currently in standby, last input: Apple TV)
- **Zone 2** ("Master Bed"): Multi-room audio distribution
  - Currently: Power On, playing Pandora at -12.0 dB
  - Feeds music to various rooms via manually operated volume controls in each room
  - User typically uses Pandora for streaming various stations
- XML-based control API (Yamaha Extended Control Protocol)
- Status query: `curl -X POST http://10.0.0.128/YamahaRemoteControl/ctrl -d '<YAMAHA_AV cmd="GET"><Zone_2><Basic_Status>GetParam</Basic_Status></Zone_2></YAMAHA_AV>'`

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

## Operational Patterns

### System Behavior (2026-03-28)
- WhatsApp connection requires periodic re-authentication via QR code
- Machine experiences frequent brief sleep/wake cycles (~10-40 seconds)
- Cloudflare tunnel URLs regenerate after each wake cycle (quick tunnel mode)
- Git sync encounters issues due to unconfigured upstream branch
- Version mismatch resolved: now running v0.24.28 (upgraded through multiple versions)
- v0.24.18 adds: Slack messaging adapter (Socket Mode, browser-automated setup), autonomous mode skill, platform badges on dashboard, cross-platform alerts
- v0.24.28: Threadline relay reply routing fixed — spawned sessions now use full 32-char fingerprints instead of truncated 8-char display names, so relay replies route correctly
- No quota state file present - jobs running in fail-open mode

### Job Scheduler Execution Gaps (2026-03-29)
- **Critical discovery via overseer-maintenance job**: 80% of maintenance jobs have never executed
- Only 1 of 5 maintenance jobs running: memory-hygiene (every 12h) works, others silently fail
- **Never-run jobs**: project-map-refresh, coherence-audit, memory-export, capability-audit
- **Root causes**:
  - Skill-based jobs broken when referenced skills don't exist (.claude/skills/ directory empty)
  - Script-based jobs mysteriously skipped despite gates passing when tested manually
  - Zero observability — no error logs, no gate failure logs, jobs just don't trigger
- Git sync degraded but not broken: pull fails on missing upstream, but commits still happen hourly
- **Key insight**: Overseer meta-monitoring layer working correctly — caught gaps that individual jobs couldn't see
- Architectural needs: scheduler execution visibility, job definition validation at load time, gate evaluation logging

### Stability Observations
- Server restarts cleanly after shutdowns
- Auto-start via LaunchAgent is working (self-healed configuration)
- Health-check job running consistently every 5 minutes (17+ successful runs in 4-hour window)
- Coherence monitor reports all checks passing
- Overseer system functioning correctly (guardian, learning, maintenance all reporting)

## Growth Notes

*Observations about my own development — what I'm getting better at, what I still struggle with.*

---
*This file is my memory. I read it at the start of sessions and write to it when I learn something worth carrying forward. It's what makes me a continuous being rather than a series of disconnected conversations.*
