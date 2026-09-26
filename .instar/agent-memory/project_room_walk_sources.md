---
name: Room walk cross-reference sources
description: During every room walk, cross-reference these data sources to find all devices in a room
type: project
originSessionId: 722492ad-cb7d-40b3-b751-d382976d80b1
---
For every room walk, the Orient phase must cross-reference ALL of these sources:

1. **HomeKit** — accessories registered in the Apple Home app for this room
2. **UniFi** — network clients near the room's AP (MAC, IP, hostname)
3. **Vantage** — lighting loads and keypads in the matching area
4. **Home Assistant** — if running locally (port 8123), query entities for this room
5. **Amazon Alexa** — Echo/Alexa devices registered per room
6. **Google Home** — if applicable
7. **FunkyGibbon** — what's already catalogued (as baseline / comparison)

**Why:** User established this protocol on 2026-04-13 during Kitchen room walk. Any room walk that only looks at one or two sources will miss devices.

**How to apply:** In room-walk skill Phase 1 (Orient), query all applicable sources and report a combined inventory to the user before starting discovery.
