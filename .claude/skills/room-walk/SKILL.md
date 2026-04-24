---
name: room-walk
description: Interactive room cataloging — Adrian stands in a room, conversationally catalogs everything (devices, keypads, doors, non-networked items) with photo support and Vantage load probing; produces a reviewable diff that commits to FunkyGibbon.
metadata:
  user_invocable: "true"
---

# /room-walk

Catalog what's physically in a room — devices, keypads, doors, sensors — through a guided conversation. Nothing writes to FunkyGibbon until you review and confirm.

Full design spec: `.instar/context/room-walk-skill-spec.md` (read it if you need details on the why behind any step).

## When to use

- Adrian says "let's walk [room]" / "I'm in [room], let's catalog it" / `/room-walk [room]`
- Adrian wants to document what's in a new or previously-uncatalogued area
- After a renovation or device installation

For editing an already-catalogued room (rename, remove, fix), use `/room-edit` instead.

## Required helpers

All under `.claude/scripts/`:
- `kittenkong_helper.py` — FunkyGibbon REST client (never touch the SQLite directly)
- `vantage_probe.py` — Vantage controller live commands
- `unifi_probe.py` — UniFi Dream Machine client/device enumeration (MAC, IP, AP)
- `room_session.py` — session state (in `.instar/state/room-sessions/`)
- `render_review.py` — generates review markdown + posts to Private Viewer
- `room_commit.py` — applies diffs on confirm
- `image_compress.py` — downsamples photos before upload
- `imessage-send-photo.sh` — sends an image back to Adrian via iMessage (use this; imsg --file fails with permission errors; this uses AppleScript instead)

All are Python. Use `/Library/Frameworks/Python.framework/Versions/3.11/bin/python3` or the bare `python3` on PATH.

## The conversation shape

You run a continuous conversation with Adrian over iMessage. Between Adrian's messages, you keep session state on disk — every Bash call creates/updates a session file. Never commit without a review-confirmed step.

### Phase 1 — Orient

1. **Resolve the room**. Use `kittenkong_helper.py` to find the room by name:
   ```bash
   python3 .claude/scripts/kittenkong_helper.py rooms
   ```
   - If Adrian's room name matches exactly (case-insensitive): great.
   - If ambiguous (multiple matches), ask which one.
   - If no match, offer: "No room called X. Should I create a new room, or did you mean [list similar]?"

2. **Check for open sessions** for that room:
   ```python
   from room_session import RoomSession
   open_sessions = RoomSession.find_open_for_room(room_name)
   ```
   If one exists, ask: "You have a walk in progress for [room] from [timestamp]. Resume, or start fresh (the old one will stay in `.instar/state/room-sessions/` for reference)?"

3. **Create the session**:
   ```python
   snapshot = {
       "devices": fg.list_devices_in_room(room_id),
       "doors": fg.list_doors_for_room(room_id),
   }
   session = RoomSession.create(room_entity_id=room_id, room_name=room_name,
                                 mode="walk", initial_snapshot=snapshot)
   ```

4. **Load all smart home inventories** — query every integrated system for this room's footprint:

   **HomeKit** (ALWAYS FIRST — authoritative list of all accessories):
   Run at the start of EVERY walk to get a fresh dump and save it:
   ```bash
   python3 .claude/scripts/homekit-dump.py --save --brief
   ```
   Then filter for this room:
   ```python
   import json
   hk_data = json.load(open('.instar/state/homekit-dump.json'))
   room_accessories = [
       acc for room in hk_data['rooms']
       for acc in room['accessories']
       if room_filter.lower() in (room['name'] or '').lower()
   ]
   ```
   The dump reads `~/Library/HomeKit/core.sqlite` directly (requires Full Disk Access for Terminal). Note that HomeKit room names may differ from FunkyGibbon room names — check adjacent rooms too.

   **Vantage** (lighting loads and keypads):
   ```python
   from vantage_probe import VantageProbe
   v = VantageProbe()
   v.load_inventory()
   vantage_loads = v.find_loads_in_area(room_name)  # fuzzy area match
   vantage_stations = v.find_stations_in_area(room_name)
   ```

   **UniFi** (network devices near the room's AP):
   ```python
   from unifi_probe import UniFi
   from kittenkong_helper import FunkyGibbon
   u = UniFi()
   u.load_inventory()
   fg = FunkyGibbon()
   all_fg_devices = fg.list_entities('device')
   # Build a set of MACs already catalogued in any room
   catalogued_macs = set()
   for d in all_fg_devices:
       net = d.get('content', {}).get('network', {})
       if net.get('mac') and d.get('located_in_room_id'):
           catalogued_macs.add(net['mac'].lower())
   candidates = u.clients_near(room_name)
   # Exclude already-catalogued devices
   new_candidates = [
       e for e in candidates
       if e['client']['mac_address'].lower() not in catalogued_macs
   ]
   already_placed = [e for e in candidates if e not in new_candidates]
   # Mention excluded count but don't surface them
   # e.g. "3 devices on this AP are already catalogued in other rooms — skipping those"
   candidates = new_candidates
   ```

   **Home Assistant** (if running on the network — check port 8123):
   ```bash
   curl -s http://localhost:8123/api/states -H "Authorization: Bearer $HA_TOKEN" 2>/dev/null | python3 -c "import json,sys; [print(e['entity_id'], e['state']) for e in json.load(sys.stdin) if '<room>' in e.get('attributes',{}).get('friendly_name','').lower()]"
   ```

   **Amazon Alexa / Google Home / other hubs**: Check if the user has mentioned these for this home. If configured, query them. Otherwise note "not configured".

5. **Report findings** to Adrian via iMessage (use `imessage-reply.sh`):
   > "We're in **[room]**. FunkyGibbon has N devices here: [names]. Vantage has M loads: [list]. HomeKit shows: [accessories]. UniFi sees: [devices near AP]. Anything missing or wrong?"

### Phase 2 — Discovery loop

Drive entirely by Adrian's input. For each thing Adrian mentions, add a diff via `session.add_diff(...)`. Common patterns:

**New Vantage device** (already in Vantage inventory, not yet in FunkyGibbon):
Adrian: "there's a fountain at the entry, Vantage calls it POUNTAIN"
```python
session.add_diff({
    "action": "create_device",
    "draft": {
        "name": "Entry Fountain",
        "content": {
            "system": {"kind": "vantage", "vid": 2454, "area_vid": 2448,
                       "original_name": "ENTRY POUNTAIN"},
            "aliases": ["the fountain", "entry water feature"],
            "status": "operational",
            "notes": "Vantage name has a typo — cleaned to Entry Fountain",
        },
        "located_in_room_id": room_id,
    },
})
```

**Probe a Vantage load to identify it** (full flash, 3s by default):
```python
v.flash_load(1781, duration=3.0)
```
Narrate: "Flashing load 1781 for 3 seconds — tell me which light that is."

**New non-Vantage device** (Alexa, Tuya, HomeKit-only, etc.):
Adrian: "there's an Echo Dot on the side table"
```python
session.add_diff({
    "action": "create_device",
    "draft": {
        "name": "Side Table Echo Dot",
        "content": {
            "system": {"kind": "alexa", "model": "Echo Dot 5th gen"},
            "aliases": ["the Echo", "Alexa"],
            "control_status": "catalogued_only",  # no integration yet
            "status": "operational",
        },
        "located_in_room_id": room_id,
    },
})
```

**Photo attachment** — Adrian sends a photo via iMessage:
The photo will be available as a file (Read tool can show it to you).
```python
photo_id = session.attach_photo(
    source_path=photo_file_path,
    parent_hint="entry keypad",
    description="6-button keypad by front door"
)
```
Then reference it in a draft via `"photos": [photo_id]`.

**Sending a photo back to Adrian** — Use `imessage-send-photo.sh`, NOT imsg --file (which fails with a permissions error):
```bash
.claude/scripts/imessage-send-photo.sh "+14084424360" "/path/to/photo.jpeg" "Optional caption"
```
This script compresses the image first and uses AppleScript to send it, bypassing the Full Disk Access restriction that blocks imsg.

**Keypad** — Adrian photographs the keypad; vision extracts button labels:
```python
# After reading the image and identifying labels
session.add_diff({
    "action": "create_keypad",
    "draft": {
        "name": "Living Room Entry Keypad",
        "content": {
            "aliases": ["the switch by the door"],
            "system": {"kind": "vantage", "vid": 2103,
                       "station_type": "Keypad", "button_count": 6},
        },
        "located_in_room_id": room_id,
        "photos": [photo_id],
        "buttons": [
            {
                "name": "Overhead",
                "content": {
                    "label_raw": "OVERHEAD",
                    "system": {"kind": "vantage", "vid": 2105,
                               "keypad_vid": 2103, "position": 1},
                },
                "controls": ["<existing-load-entity-id>"],  # if known
            },
            # ... more buttons
        ],
    },
})
```
For each button, interactively probe/ask: "Button 2 is labeled 'CANS'. I'll flash load 2231 — tell me if that's the cans." Use `v.flash_load()`.

**Door**:
Adrian: "there's a door to the garage with a Schlage lock"
```python
session.add_diff({
    "action": "create_door",
    "draft": {
        "name": "Living Room to Garage Door",
        "content": {
            "aliases": ["garage door"],
            "is_lock_smart": True,
            "lock_device_id": "<schlage-entity-id-from-homekit>",
            "is_exterior": False,
        },
        "connects_to": [room_id, "<garage-room-id>"],
    },
})
```

**Mis-located existing device** — if FunkyGibbon has a device in a different room but Adrian says it's here:
```python
session.add_diff({
    "action": "move_to_room",
    "entity_id": "<existing-device-id>",
    "new_room_id": room_id,
})
```

**Inoperable / replaced device**:
```python
session.add_diff({
    "action": "set_status",
    "entity_id": "<existing-device-id>",
    "status": "inoperable",
    "reason": "dead, needs replacement",
})
```

**Cross-reference from UniFi**: query the UniFi Dream Machine for clients near the room's AP/switch.

```python
from unifi_probe import UniFi
u = UniFi()
u.load_inventory()

# Find clients near the AP that matches this room (UniFi AP names often include
# room names: "AP Family Room TV", "AP Laurels Desk", etc.)
candidates = u.clients_near(room_name)
for entry in candidates:
    c = entry["client"]
    print(f"  {c['name']} ({c['ip_address']}, {c['mac_address']}) via {entry['ap_name']}")
```

Report candidates to Adrian:
> "I see these devices on the Family Room AP: Apple TV (10.0.0.74), Ambient Weather (10.0.0.166), Wolf Wall Oven (10.0.0.25), SubZero Freezer, Rheem Hot Water. Which of these should I catalog in this room?"

For each that Adrian confirms, include the network metadata in the device's content:
```python
session.add_diff({
    "action": "create_device",
    "draft": {
        "name": "Apple TV 4K (Family Room)",
        "content": {
            "system": {"kind": "homekit", "accessory_id": "..."},
            "network": {
                "mac": "50:de:06:b0:03:15",
                "ipv4_hint": "10.0.0.74",
                "unifi_client_id": "...",
                "ap": "AP Family Room TV",
            },
            "aliases": ["Apple TV", "family room TV"],
        },
        "located_in_room_id": room_id,
    },
})
```

MAC is stable, IP is a hint (DHCP). Store both.

### Phase 2.5 — Iterate

Between diffs, keep transcribing:
```python
session.log("user", "<what Adrian said>")
session.log("agent", "<what you said back>")
```

Don't send a review after every single diff — batch. When Adrian indicates they're done (says "that's it", "done", "wrap it up", "let's review") or you've covered the obvious, move to Phase 3.

### Phase 3 — Review

1. **Post the review**:
   ```python
   from render_review import post_session_review
   view = post_session_review(session)
   ```
2. **Send the tunnel URL** to Adrian via iMessage:
   ```bash
   .claude/scripts/imessage-reply.sh "+14084424360" "Review here: <view['tunnelUrl']>
   Reply 'confirm' to commit, or tell me what to change."
   ```

3. **Wait** for Adrian's response. Don't commit anything yet.

### Phase 4 — Edit or Confirm

If Adrian says "confirm" (or "yes", "do it", "commit"):
```bash
python3 .claude/scripts/room_commit.py <session.id>
```
Then iMessage the result: number of entities created, any errors, and if applicable, a note that photos were uploaded as blobs.

If Adrian requests changes ("rename X to Y", "remove that door"):
- Parse the change, modify the session diffs via `session.remove_diff(idx)` / `session.replace_diff(idx, new_diff)` / `session.add_diff(...)`
- Regenerate and post the review again
- Wait for confirm

If Adrian says "discard" or "cancel":
```python
session.set_status("discarded")
```
The session is archived (never deleted) but won't be applied.

### Phase 5 — Handoff

After commit:
- Write a brief summary to `.instar/state/job-handoff-room-walk.md`
- Append a one-line entry to `.instar/MEMORY.md` under "Room Walks" section:
  > - 2026-04-13: Living Room — catalogued 5 new devices, 1 keypad (6 buttons), 2 doors. Session `abc123…`
- iMessage Adrian with the commit summary and session UUID

## Important constraints

- **Never write to SQLite directly.** Always go through `kittenkong_helper.py`.
- **Never commit without the review + confirm cycle.** Even if Adrian is impatient.
- **Full-flash probing is fine during the day**; if Adrian asks for gentle flash ("it's dark / the baby's asleep"), use `v.flash_load(vid, duration=1.5, peak_level=30)` in that session.
- **Photos are always downsampled** before upload (`image_compress.compress_image`). Don't skip this — the default compresses to ~100KB JPEG.
- **Sessions never expire.** If you find an open session for a room, ask before clobbering — archived sessions are audit trail, never auto-purged.
- **Keep the transcript** (`session.log()`) so the review and the saved note both have context.
- **Be willing to wait.** Adrian may leave the room and come back. Session state persists across iMessage session respawns. On resume, read the session file to pick up where you left off.

## What success looks like

End of a successful walk:
- FunkyGibbon has new DEVICE/DOOR/KEYPAD/ROOM entities with clean names, aliases, system metadata, and photos
- Relationships (`located_in`, `connects_to`, `controls`, `part_of`) are in place
- A `note` entity captures the session transcript, linked `documented_by` to the room
- MEMORY.md has a one-line log entry
- Session JSON is archived in `.instar/state/room-sessions/archive/`
- Adrian got a confirmation iMessage with numbers: "Committed: N entities created, K photos uploaded, 0 errors"
