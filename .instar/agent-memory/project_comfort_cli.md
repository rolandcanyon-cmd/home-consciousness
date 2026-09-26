---
name: comfort-cli — Mitsubishi thermostat CLI
description: comfort-cli tool built 2026-04-19 for controlling Mitsubishi Comfort thermostats via pykumo
type: project
originSessionId: 3d008a33-f8b5-4e57-97b0-405171b5d02d
---
Built 2026-04-19. Uses pykumo library to control 4 Mitsubishi mini-split thermostats.

**Location**: `~/homebrew/bin/comfort-cli`
**Library**: `pykumo` (pip-installed, v0.4.0)
**Credentials cache**: `~/.comfort-cli.json`

**Four units**: Guest House, Kitchen, Main Bedroom, Pool House

**Critical — condenser pairing**: Kitchen + Pool House share a condenser and must ALWAYS be the same mode (heat/cool/off). If set to different modes they cycle against each other and fight — inefficient and potentially damaging. Any mode change to Kitchen or Pool House must also apply to the other (use comfort-cli's paired-mode command if present).

**Commands**:
- `comfort-cli status` — show all units
- `comfort-cli mode <unit> <off|cool|heat|auto>` — set mode
- `comfort-cli set <unit> <temp_f>` — set setpoint
- Partial matching: `comfort-cli status pool` → Pool House

**FunkyGibbon**: Full instructions in entity `a0cdbf3e-df83-4f9d-a5a1-99b3b69dc31a` ("Mitsubishi HVAC — comfort-cli instructions"). Use `search_entities("Mitsubishi")` to find it.

**Pool House note**: HTTPS with self-signed cert (SSL disabled in comfort-cli). Shows `?` when off LAN.

**Why:** Use this tool for thermostat queries/control. FunkyGibbon has the full API reference.
