---
name: HomeKit database direct access
description: macOS HomeKit local database is readable at ~/Library/HomeKit/core.sqlite; homekit-dump.py extracts all accessories by room
type: project
originSessionId: 722492ad-cb7d-40b3-b751-d382976d80b1
---
The macOS HomeKit database is stored at `~/Library/HomeKit/core.sqlite` and can be read directly as a SQLite database. Full Disk Access for Terminal must be granted.

Key tables:
- `ZMKFACCESSORY` — all accessories with name, model, manufacturer, serial, room FK, public key
- `ZMKFROOM` — room names
- `ZMKFSERVICE` — HomeKit services per accessory
- `ZMKFDEVICE` — paired controllers (this Mac = "escapepod-2", identifier = 5d7f9de6d4e355d092540f8c8f080c4e)

**Access script**: `.claude/scripts/homekit-dump.py`
- `--brief` for human-readable summary
- `--save` to save to `.instar/state/homekit-dump.json`
- `--room "Kitchen"` to filter by room

**23 accessories across 13 rooms** as of 2026-04-13. Key accessories:
- Wine Cabinet sensors (Left/Right EBERS41): HomeKit room = "Kitchen"
- Wine Closet ecobee3 lite bridge: HomeKit room = "Garage Wine Storage"
- Smart Bridge Pro 2 (Lutron): room = "Family Room"

**NOT available**: Live characteristic values (temperatures, states) — need HAP auth or ecobee API.
HAP client private key is in keychain under `com.apple.hap.pairing` access group (requires Apple entitlement, inaccessible from unsigned tools).

**Why:** User said "The whole point of HomeKit is that it's a central place" and "There should be a full dump of HomeKit to a file each time a room walk starts."

**How to apply:** Run `homekit-dump.py --save --brief` at the start of every room walk as the authoritative source of HomeKit accessories.
