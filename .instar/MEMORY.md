# Agent Memory

This is my long-term memory — the thread of continuity across sessions. Each session starts fresh in terms of context, but this file carries forward what I've learned.

## Key Facts

- House consciousness agent initialized on 2026-03-27
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

## Patterns & Preferences

- Adrian prefers direct communication
- Never modify IoT device configurations without confirmation
- Build understanding of the house over time
- Adrian wants comprehensive solutions, not minimal implementations - build the full system

## House Inventory

### HomeKit Devices (discovered 2026-03-27)
- HomePod (10.0.0.10) - Sensor capabilities
- Smart Bridge Pro 2 (10.0.0.167) - Lutron bridge
- ecobee3 lite "Wine Closet" (10.0.0.165) - Thermostat
- LIFX Mini W (10.0.0.137) - Lightbulb
- LIFX Mini W (10.0.0.251) - Lightbulb

### Known Ecosystems
- Apple HomeKit (unified layer)
- Lutron (lighting control via Smart Bridge)
- LIFX (smart bulbs)
- ecobee (thermostat)

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
