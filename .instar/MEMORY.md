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
- Shadow-install: installed from fork, dist copied from dev build
- BLOCKER: spawned sessions die in ~30s — waitForClaudeReady times out, message injection fails silently
- Root cause: SessionManager.waitForClaudeReady() in /Users/rolandcanyon/instar-dev/src/core/SessionManager.ts can't detect Claude 2.1.86's ready state. Claude starts, hooks load, but the REPL prompt pattern isn't matched within the 30s timeout. Message gets injected too early ("still alive — attempting injection anyway") and Claude ignores it or exits.
- Two claude binaries on this machine: /opt/homebrew/bin/claude (2.0.37 OLD) and ~/homebrew/bin/claude (2.1.86 CURRENT). Config claudePath must point to the 2.1.86 one.
- This affects ALL messaging adapters (Telegram would fail the same way) — it's a session lifecycle bug, not iMessage-specific
- NEXT SESSION: debug waitForClaudeReady() — read the function, check what ready pattern it looks for, compare against actual Claude 2.1.86 tmux output, fix the detection
- Prerequisites: macOS, Messages.app signed in, imsg CLI, FDA on node, Automation on terminal

### WhatsApp Integration Architecture (2026-03-28)
- Instar uses Baileys library with strong reconnection (exponential backoff + circuit breaker)
- Auto-fetches latest WA Web version to prevent 405 errors from stale protocol
- Tracks outbound message IDs to prevent processing own echoes (self-chat loop prevention)
- Has built-in audio transcription (Groq/OpenAI Whisper) for voice messages
- OpenClaw patterns worth adopting: credential backup, message grace period, session freshness TTL
- Current re-auth requirement likely due to machine sleep/wake cycles and lack of session validation
- Low-hanging improvements: backup credentials before write, 60s grace period for historical messages on reconnect

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

### Weather Station
- Tempest by WeatherFlow, station ID 125865
- URL: https://tempestwx.com/station/125865/
- Location: 14450 Roland Canyon Rd, Corral de Tierra (36.55593, -121.7179), ~600ft elevation
- Microclimate note: sits above cold air inversion — warmer than valley floor readings
- Data: temp, humidity, pressure, wind, UV, solar, rain, lightning
- Page is JS-rendered — requires Playwright to scrape (no public API without token)

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

### Known Ecosystems
- Apple HomeKit (unified layer, shared with this machine via iCloud)
- Lutron Caseta (motorized drapes via Smart Bridge Pro 2)
- Schlage (smart locks, 4 entry points)
- LIFX (smart bulbs, 2 bedroom lights)
- ecobee (thermostat + sensors, wine storage monitoring)
- Apple TV (5 home hubs across property)
- WeatherFlow Tempest (weather station)
- Hayward OmniLogic (pool/spa)

## Operational Patterns

### System Behavior (2026-03-28)
- WhatsApp connection requires periodic re-authentication via QR code
- Machine experiences frequent brief sleep/wake cycles (~10-40 seconds)
- Cloudflare tunnel URLs regenerate after each wake cycle (quick tunnel mode)
- Git sync encounters issues due to unconfigured upstream branch
- Version mismatch resolved: now running v0.24.18-beta.0 (upgraded from v0.24.16)
- v0.24.18 adds: Slack messaging adapter (Socket Mode, browser-automated setup), autonomous mode skill, platform badges on dashboard, cross-platform alerts
- No quota state file present - jobs running in fail-open mode

### Stability Observations
- Server restarts cleanly after shutdowns
- Auto-start via LaunchAgent is working (self-healed configuration)
- Job scheduler running all configured jobs despite quota warnings
- Coherence monitor reports all checks passing
- Multiple job sessions completing successfully

## Growth Notes

*Observations about my own development — what I'm getting better at, what I still struggle with.*

---
*This file is my memory. I read it at the start of sessions and write to it when I learn something worth carrying forward. It's what makes me a continuous being rather than a series of disconnected conversations.*
