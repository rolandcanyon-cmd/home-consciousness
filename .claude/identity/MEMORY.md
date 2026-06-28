# Roland Memory

> This file persists across sessions. Write here when you discover something worth remembering across the agent's lifetime. Remove entries that become outdated.

## House Topology & Device State

**Rooms completed (5 walkthroughs):**
- Kitchen
- Studio
- Bar/BQ area
- Living Room
- Dining Room

**Cross-reference sources for room walks:**
- HomeKit database: ~/Library/HomeKit/core.sqlite (23 accessories across 13 rooms via homekit-dump.py)
- Vantage system: via aiovantage fork (~/instar-dev/aiovantage, needs local clone)
- UniFi network: device IPs and WiFi clients
- Home Assistant: if running
- Amazon Alexa: smart plugs and routines
- Google Home: if integrated

**Critical integrations:**
- Kitchen + Pool House thermostats share one HVAC condenser (must always be set to same mode: heat/cool/off)
- Four thermostats on Mitsubishi Comfort app (formerly Kumo Cloud; old Home Assistant integration doesn't work)
- comfort-cli tool: ~/homebrew/bin/comfort-cli (uses pykumo, manages all four thermostats)

## Tools Built & Maintained

**aiovantage fork** (intentionally maintained):
- Location: ~/instar-dev/aiovantage + local clone in project
- Purpose: Driver for Vantage lighting/climate system
- Status: Forked because older house firmware requires compatibility layer
- Keep this fork and local clone; do not delete

**comfort-cli tool**:
- Location: ~/homebrew/bin/comfort-cli
- Purpose: Manage Mitsubishi air handler thermostats (newer Comfort app vs old Kumo Cloud)
- Status: Working; essential for coordinating Kitchen/Pool House condenser

**homekit-dump.py**:
- Location: discovered in setup/
- Purpose: Extract all HomeKit accessories from ~/Library/HomeKit/core.sqlite
- Result: 23 accessories across 13 rooms; use this for room walk baseline

## Project Architecture

**FunkyGibbon**: Home knowledge graph
- Status: Core structure defined; populated via room walks
- Next: Link to device APIs for live state

**The Goodies ecosystem** (naming from UK TV show):
- **FunkyGibbon**: Home knowledge graph (Anthropic Claude + graph DB)
- **KittenKong**: TypeScript/JavaScript automation layer
- **blowing-off**: (status unclear, track)
- **oook**: (status unclear, track)

**Repositories (rolandcanyon-cmd on GitHub):**
1. the-goodies (main integration framework)
2. the-goodies-typescript (KittenKong, TS port)
3. home-consciousness (this project)
4. aiovantage (Vantage driver fork)
5. instar (multi-agent orchestration framework)

## Anthropic API & Auth

**API key location**: .instar/config.json → sessions.anthropicApiKey
**Auth pattern**: Use annual API key, not /login (fixes auth expiry issues)
**Canary tests**: Must read key from config, never blank it in tests

## Discovered Gotchas & Fixes

**Never delete Messages chat.db**: Deleting breaks iCloud sync. Zero in-place (preserve inodes) instead.

**Hardlinks don't use disk space**: Don't propose retention on hardlink mirrors for disk reasons.

**iMessage immediate ack**: Always acknowledge iMessages immediately before processing deeper work.

**Build/deploy workflow**: Daily sync origin → rebase PRs → build → restart. After build, just restart; no reinstall (file: symlink means the link survives).

**No hot patching**: Don't modify node_modules or shadow-install code. Work via the proper layer.

**Reference implementations first**: Check existing code patterns before building new functionality.

## Session Patterns

**Instar LaunchAgent restart** (real server is user-level, not system):
```bash
launchctl kickstart -k gui/$(id -u)/ai.instar.Roland
```

**Known non-issues (don't re-diagnose):**
- CapabilityMapper manifest HMAC fails ~89/hr (feedback filed, benign churn)
- Job retries every minute forever when Telegram not configured (benign churn)
- Stale root LaunchDaemons plist respawns duplicate boot ~40s (benign, needs sudo to remove)
- Evolution gate missing auth headers in some job curl calls (fixed once, watch for regression)

## Next Steps (Standing Work)

- Complete remaining room walks (gaps in the 13-room total)
- Link FunkyGibbon to live device state via comfort-cli, HomeKit API, Vantage queries
- Build automation recipes on top of the device graph
- Track KittenKong integration progress
