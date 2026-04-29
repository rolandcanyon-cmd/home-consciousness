# Room Walk & Room Edit Skills — Spec

**Status:** Draft for review
**Goal:** Let the user catalog and edit house knowledge conversationally via iMessage, with structured review before anything writes to FunkyGibbon.

Two complementary skills that share the same underlying machinery:

- `/room-walk <room>` — interactive discovery session for a room (additive, mostly creating)
- `/room-edit <room>` — targeted edit session for a known room (reviewing, renaming, deleting, correcting)

---

## 1. Shared Design Principles

### Canonical names come from HomeKit
Room names follow HomeKit's vocabulary where possible. For Vantage-only zones (outdoor, attics), new imported ROOM entities are created with `source_type: "imported"`. Both skills respect this.

### FunkyGibbon is the only writer
All changes go via the REST API (`POST/PATCH/DELETE /api/v1/graph/entities`). No direct SQLite touches. The TypeScript kittenkong client is preferred when available; Python skills use direct REST calls.

### Session state in files, not memory
Each walk/edit has a session UUID. State lives in `.instar/state/room-session-<uuid>.json`. This survives iMessage session respawns — if the Claude session dies mid-walk, the next one picks up the pending walk on resume.

### No writes without explicit review
Both skills have a clear "show summary, confirm, then commit" boundary. Summary is sent as a Private Viewer HTML page via `POST /view` (phone-readable), and the commit step requires the user to reply "confirm" or similar.

### Aliases everywhere
Every ROOM and DEVICE has `content.aliases` — natural-language ways the user refers to it. Added during walks, edited during edits, used by future lookup.

### Photos as blobs, not file refs
Images sent via iMessage are uploaded as blob entities linked via `has_blob` relationship. The FunkyGibbon schema already supports this (LargeBinary column). Never store paths to files outside the DB.

---

## 2. `/room-walk <room>` — Discovery Session

### Entry points
- User command: `/room-walk Living Room`
- Phrase triggers: "let's walk [room]", "I'm in [room], let's catalog", "tour [room]"
- Detected from context: if an iMessage mentions a room name + "cataloging" intent

### Phase 1: Orient
1. Resolve room name — exact or fuzzy match against FunkyGibbon rooms
   - If ambiguous, ask: "I have 'Living Room' and 'Pool House Living Room' — which?"
   - If not found, ask: "No room called X. Create new or pick existing: [list]?"
2. Create session state file with `{uuid, room_entity_id, started_at, status: "orienting"}`
3. Query FunkyGibbon for existing devices in this room
4. Query Vantage via port 2001 (or cached dump) for loads whose `area_vid` maps to this room's Vantage aliases
5. Report findings to user:
   > "We're in **Living Room**. FunkyGibbon knows about 3 devices here: Lutron Front Drape, Lutron Rear Drape, ceiling light (LIFX).
   > Vantage has 4 loads in this area: BIG PICTURE RIGHT OF FIREPLACE, MCDONALD STANDING SCULPTURE, FLOOR PLUG, GLASS LEFT OF FIREPLACE.
   > Are all of these still here? Anything else I should know about?"

### Phase 2: Discovery (loop)
User drives this. The agent assists with:

**For wrongly-located devices**: If the user points to a device that FunkyGibbon has in a different room, The agent handles it as a move:
> "FunkyGibbon says 'Kitchen Island Light' is in the Kitchen, but you're in the Dining Room pointing at it. Did it move, or is it mis-assigned?"

The draft records a `move` action, same format as the `/room-edit` flow (§3 under Edit loop). On commit, this updates the `located_in` relationship — not a duplicate entity, just a different link.

Walk sessions can therefore fix misplacements discovered along the way, not only add new devices.


**For Vantage loads**, The agent can probe live:
> "I'll flash load 1781 (BIG PICTURE RIGHT OF FIREPLACE) — tell me what light that is."
Then: `vantage load 1781 100` → wait 3s → `vantage load 1781 0` → wait → `vantage load 1781 <original>`

**For photos**, user sends image via iMessage:
- The agent reads the image file (Claude Code's Read tool handles images)
- Describes what it sees: "I see a tall floor lamp with a bronze base next to a leather armchair"
- Asks: "What do you call it? Which system controls it?"
- Stores image in session state for later blob upload

**For natural-language descriptions**:
- User: "the overhead lights"
- The agent: checks session findings for matches, asks clarifying questions
- User: "actually call it 'ceiling lights' — that's what I say"
- The agent: records as alias

### Phase 3: Build up the draft
For each device identified, The agent builds a draft record in session state:

```json
{
  "discovery_action": "create" | "update" | "confirm_existing",
  "entity_id": "...",  // for updates
  "name": "Entry Fountain",
  "aliases": ["the fountain", "entry water feature"],
  "entity_type": "device",
  "source_type": "imported" | "homekit",
  "content": {
    "vantage": {"vid": 2454, "area_vid": 2448, "kind": "load", "original_name": "ENTRY POUNTAIN"},
    "notes": "Vantage name has a typo — cleaned to Entry Fountain"
  },
  "located_in_room_id": "...",
  "photos": ["<base64 or local tmp path>"]
}
```

### Phase 4: Review
When user signals done ("that's it", "done", "let's wrap up"):
1. Summarize verbally: "Here's what I found: [brief list]"
2. Generate full review document
3. Post via `POST /view` → get tunnel URL
4. iMessage the link: "Review here: https://.../view/<token> — reply 'confirm' to commit or tell me what to change."

Review document includes:
- All new devices with names, aliases, system, location
- All updates (existing device + what changed + why)
- All new aliases on the room itself
- Photos shown inline
- Vantage VIDs referenced
- Any ambiguities or notes flagged for attention

### Phase 5: Commit
User replies "confirm" (or similar: "yes", "do it", "commit"):
1. Create/update entities via REST
2. Upload photos as blob entities, create `has_blob` relationships
3. Create `located_in` relationships
4. Create `note` entity with full walk transcript, linked `documented_by` to room
5. Write handoff summary to `.instar/state/job-handoff-room-walk.md`
6. Update MEMORY.md with completion entry
7. Clean up session state file
8. Report: "Committed. Added N devices, updated M, attached K photos."

If user replies with changes ("rename X to Y", "remove Z"):
- Apply to draft, re-generate review, post again, wait for confirm

---

## 3. `/room-edit <room>` — Targeted Edit Session

Same underlying machinery, different default behaviors:

### Differences from walk
- **Starts with the full current state**, not discovery — The agent shows everything in the room upfront
- **Edit-first conversation** — "what would you like to change?"
- **Bulk operations supported** — "rename all the Vantage 'POUNTAIN' entries to 'Fountain'" applies a regex to all matching devices
- **Deletion supported** — "remove the Old Thermostat" marks entity for deletion
- **Moving devices** — "move the LIFX to the Bedroom" updates `located_in` relationship
- **Room-level edits** — rename the room, add aliases, change source type, split/merge rooms

### Entry points
- User command: `/room-edit Bedroom`
- Phrase triggers: "let me fix [room]", "edit [room]", "update [room]"

### Phase 1: Snapshot
1. Resolve room
2. Load all entities linked via `located_in` to that room
3. Load room's own content
4. Present:
   > "Bedroom has:
   >   • Owner LIFX Mini W (LIFX, IP 10.0.0.137) — aliases: 'owner's lamp', 'bedside'
   >   • Partner LIFX Mini W (LIFX) — aliases: 'partner's lamp'
   >   • Overhead lights (Vantage VID 47) — aliases: 'ceiling'
   >   Room aliases: 'master bedroom', 'bedroom'
   > What would you like to change?"

### Phase 2: Edit loop
User specifies changes. The agent parses:
- **Rename**: "call the Owner LIFX 'Left Bedside'"
- **Add alias**: "also call it 'my side'"
- **Remove alias**: "drop 'bedside' from it"
- **Move**: "the overhead lights should be in Living Room instead"
- **Delete**: "remove Laurel's LIFX, it's gone"
- **Update notes**: "add a note that the LIFX was replaced in March"
- **Room-level**: "rename the room to 'Primary Bedroom'"

The agent maintains a diff in session state:
```json
{
  "diffs": [
    {"action": "rename", "entity_id": "...", "old": "Owner LIFX Mini W", "new": "Left Bedside"},
    {"action": "add_alias", "entity_id": "...", "alias": "my side"},
    {"action": "move", "entity_id": "...", "from_room": "...", "to_room": "..."},
    {"action": "delete", "entity_id": "...", "reason": "removed from house"}
  ]
}
```

### Phase 3: Review & Commit
Same as walk — post review HTML, wait for confirm, then apply.

For **deletes**, the review is extra explicit: "The following entities will be deleted. Versioning preserves history, but queries will no longer return them. Confirm?"

### Phase 4: Cleanup
- Session state archived to `.instar/state/archive/room-edit-<uuid>.json` (not deleted — audit trail)
- Handoff written

---

## 3.4.4 Device systems — open-ended set of integrations

Houses have a messy collection of control systems. Beyond HomeKit and Vantage, houses may have devices speaking:
- **Amazon Alexa** — Echo Dots, Show, etc. Controllable via Alexa Voice Service or ESP3 API
- **Tuya / Smart Life** — generic China-sourced smart plugs, bulbs, cameras. Cloud API or local Tuya API
- **Google Home / Matter** — shared Matter devices, Nest cameras/thermostats
- **Home Assistant** — some houses use it; this one doesn't, but the skill should be ready if it appears
- **Vendor-specific islands** — Sonos (audio), Ring (doorbells/cameras), Hue (Philips), Kasa (TP-Link), Wyze, Ecobee direct API (where richer than HomeKit exposes), LIFX LAN, etc.
- **Non-networked devices** — keyed locks, manual thermostats, old timer switches — still worth cataloging so the graph reflects reality

The spec should assume **open-ended integration**, not a closed HomeKit+Vantage world. Vantage is one "system plugin"; the skill must treat it as just another option.

### Schema — `system` field on each DEVICE

Each DEVICE entity's `content` includes a `system` descriptor:

```json
{
  "system": {
    "kind": "vantage",        // system identifier
    "vid": 1781,               // system-specific ID (flexible structure)
    "area_vid": 85,
    "capabilities": ["on_off","dim"],
    "notes": "..."
  }
}
```

Common `kind` values:
- `homekit` — accessory from HomeKit (most devices in this house)
- `vantage` — Vantage InFusion load / keypad / task
- `lutron` — direct Lutron Caseta (often via HomeKit, but may be richer direct)
- `ecobee` — direct ecobee API
- `alexa` — Amazon Echo devices
- `tuya` — Tuya/Smart Life devices
- `matter` — Matter-native devices
- `hue`, `lifx`, `sonos`, `ring`, `kasa`, `wyze`, `homeassistant`, etc. — one value per vendor/protocol
- `manual` — non-networked devices (pull-chain fan, keyed deadbolt, etc.)
- `unknown` — seen but not yet identified

**Multiple systems for the same physical device**: common — a thermostat might have both HomeKit and native ecobee control. Represent as `content.systems` (array) instead of a single `system`:

```json
{
  "content": {
    "systems": [
      {"kind": "homekit", "accessory_id": "..."},
      {"kind": "ecobee", "thermostat_id": "...", "richer_api": true}
    ]
  }
}
```

For single-system devices, `system` (singular) is fine — a convenience. Skill code accepts either.

### Discovery for unknown systems

During walks, the user may say "that's a Tuya smart plug" or "that's an Alexa." The agent:
1. Records `system.kind = "tuya"` (or `"alexa"` etc.)
2. Captures whatever identifying info the user provides (MAC, IP, name in the Alexa app, model number, photo of the device/sticker)
3. Flags the device `control_status: "catalogued_only"` — it's in the graph but the agent doesn't have an integration to control it yet
4. The user can later build an integration (or a skill for a specific class of device), at which point the device's entry is updated with proper control metadata

The walk does NOT block on "we don't have Tuya integration yet." It captures what's there and moves on. Future work adds control.

### Network-layer identification (UniFi)

This house has UniFi switches + APs as the network infrastructure. UniFi can enumerate connected clients with:
- MAC address
- Current IP
- Hostname (often vendor-revealing: `Alexa-Echo-Dot-1234`, `Tuya-LED-A1B2`)
- Switch port / AP the device is attached to
- Last-seen timestamp
- Manufacturer OUI

During a room walk, The agent can cross-reference:
1. Ask the user "what network-connected devices are in this room?"
2. Query UniFi controller for all clients
3. Filter by last-seen (recent), vendor (from OUI), or hostname pattern
4. Show candidate list: "I see an 'Echo-Dot-ABCD' on switch port 12 which is likely in this room — is that the Alexa you mentioned?"
5. Capture MAC + hostname + IP into the DEVICE entity's `content.network`:

```json
{
  "content": {
    "system": {"kind": "alexa", "echo_type": "Dot 5th gen"},
    "network": {
      "mac": "a4:08:01:xx:xx:xx",
      "hostname": "Echo-Dot-ABCD",
      "ipv4_hint": "10.0.0.137",
      "unifi_client_id": "...",
      "oui_vendor": "Amazon Technologies"
    }
  }
}
```

IP is a **hint** (DHCP reassigns), MAC is stable. Store both.

A separate `unifi_probe.py` helper wraps the UniFi API for this (same pattern as `vantage_probe.py`). Not built in this first pass — will add after the core walk/edit skills work end-to-end.

### Skill modularity

The `/room-walk` and `/room-edit` skills are **house-agnostic**. They don't know about Vantage specifically — they know about "systems" generically. The Vantage-specific probing (flash a load to identify it) lives in a separate `vantage_probe.py` helper that's invoked only when the user's house has Vantage.

If someone without Vantage uses this skill (e.g., another Instar user), the skill still works — it just doesn't offer Vantage-specific probing prompts. Over time, parallel helpers (`alexa_probe.py`, `tuya_probe.py`) can be added for whatever systems are common.

### House-specific notes

Vantage is a special case **for this house**. Other houses may have Lutron Homeworks, Crestron, Control4, or just plain HomeKit. The spec documents the Vantage integration as one implementation; the room-walk/edit skills themselves are general.

This also means: the Vantage-specific helper and the room-walk/edit skills can be independently shared. Someone with Vantage but different catalog preferences could reuse just `vantage_probe.py`. Someone with a different system but the same cataloging goals could reuse the walk/edit skills and write their own probe helper.

## 3.4.5 Device status: operational vs inoperable

Not every catalogued device still works. Some are legacy hardware that's been disconnected, replaced, or just broken but not yet removed.

### Schema

Every DEVICE entity gets a `content.status` field:
- `"operational"` (default) — device works, commands go through
- `"inoperable"` — device is known not to work; don't try to control it. Kept in the graph for completeness and history.
- `"unknown"` — status hasn't been verified
- `"decommissioned"` — physically removed or permanently replaced (kept for record, but shouldn't appear in "what's in this room" listings unless explicitly asked)

### Additional metadata on inoperable devices

```json
{
  "status": "inoperable",
  "inoperable_since": "2026-04-12",
  "inoperable_reason": "LIFX bulb died, not replaced",
  "replacement_device_id": "<uuid-or-null>"  // if replaced by another device
}
```

### Walk and edit flows

During `/room-walk`, when the user flags something as not working:
> "The old Owner LIFX doesn't work anymore — mark inoperable"

The agent updates the device with `status: "inoperable"` and prompts for a reason and whether there's a replacement.

During `/room-edit`, inoperable devices are shown but visually separated (review HTML lists them under "Not working" heading).


## 3.5 Doors (and other connectors between rooms)

FunkyGibbon has a first-class `door` entity type. Doors aren't in a single room — they sit between two rooms. Windows (`window` entity type) work the same way.

### Schema
Each door is a DOOR entity with:
- `name` — canonical name, e.g., "Kitchen to Garage Door", "Guest House Entrance"
- `content`:
  - `aliases` — natural-language names ("back door", "side door")
  - `is_lock_smart`: boolean — has a Schlage / electronic lock
  - `lock_device_id` — entity_id of the DEVICE entity representing the lock (if smart)
  - `manual_lock_type` — "deadbolt", "handle", "none", "sliding" (if not smart)
  - `is_exterior`: boolean — leads outside
  - `notes` — quirks, e.g., "sticks in winter"

### Relationships
- `(door) -[connects_to]-> (room_A)` — both rooms
- `(door) -[connects_to]-> (room_B)`
- For smart locks: `(lock_device) -[controls]-> (door)` — the DEVICE is still the Schlage accessory; the DOOR is the physical door. This keeps HomeKit-sourced lock metadata (serial number, battery, etc.) on the DEVICE and room-spanning semantics on the DOOR.
- For exterior doors that only connect one room to outside: `(door) -[connects_to]-> (room)` + `is_exterior: true`. No outside "room" needed unless you want to model the outdoor zone as a room (which we already do for the Vantage-only outdoor areas).

### Walk flow additions
During `/room-walk`, after identifying devices, The agent explicitly asks about doors:
> "What doors connect this room to others? I know about Kitchen Garage Door (Schlage lock). Any others? Which ones have Schlage locks vs manual?"

For each door:
- If already known (e.g., Schlage locks already in HomeKit), update its `connects_to` relationships
- If new, create DOOR entity with the metadata above
- For smart locks: the Schlage DEVICE should already exist (from HomeKit ingestion); link it via `controls` to the DOOR
- For manual doors: just create the DOOR entity with `is_lock_smart: false`

### Edit flow additions
`/room-edit` can:
- Add/remove doors to/from a room
- Change a door from manual to smart (when a lock is installed) — creates the DEVICE, links via `controls`
- Rename doors, edit aliases
- Update lock types, notes

### Why model doors explicitly
- Natural language: "lock the back door" → finds DOOR entity → follows `controls` relationship to the Schlage device → sends lock command. Without door entities, you'd have to hardcode which Schlage is "the back door."
- Safety/audit queries: "which doors are unlocked?" → iterate doors with smart locks, check lock device state
- Guest guidance: "how do I get from the Pool House to the Workshop?" → graph traversal over `connects_to`
- Pattern matching: "are all exterior doors locked?" → filter on `is_exterior`

### Walk prompts include doors
Add to Phase 2 discovery prompts in `/room-walk`:
> "Doors in this room: [list known]. Any I'm missing? For each, is the lock smart or manual?"

And in Phase 3 draft:
```json
{
  "discovery_action": "create",
  "entity_type": "door",
  "name": "Kitchen to Garage Door",
  "content": {
    "aliases": ["garage door", "kitchen back door"],
    "is_lock_smart": true,
    "lock_device_id": "<schlage-entity-id>",
    "is_exterior": false
  },
  "connects_to": ["<kitchen-room-id>", "<garage-room-id>"]
}
```

## 3.6 Keypads and their buttons

Vantage has 62 keypads with 511 buttons across the house. The physical labels on those keypads — with their own typos and house-specific shorthand — are what the user actually looks at to control things. So the labels are the source of truth for "what does this button do," not the Vantage internal button names.

### Schema

**Keypad** — one DEVICE entity per physical keypad:
- `entity_type: "device"`
- `source_type: "imported"`
- `name` — canonical name, e.g., "Living Room 6-Button Keypad", "Kitchen Island Keypad"
- `content`:
  - `aliases` — natural-language names
  - `vantage`:
    - `vid` — Vantage station VID
    - `station_type` — "Keypad", "DualRelayStation", "Dimmer", etc.
    - `button_count` — how many buttons
  - `photos` — references to blob entities with pictures of the labeled keypad
- Linked via `located_in` to its room

**Button** — one DEVICE entity per button on the keypad:
- `entity_type: "device"`
- `source_type: "imported"`
- `name` — the **label on the physical keypad** (e.g., "Kitchen Cans", "Overhead", "All Off", typos and all). This is what the user sees and says.
- `content`:
  - `aliases` — natural-language alternatives
  - `label_raw` — the exact text as it appears on the keypad (typos preserved, separate from cleaned canonical name if different)
  - `label_photo_blob_id` — blob entity for a closeup if helpful
  - `vantage`:
    - `vid` — Vantage button VID
    - `keypad_vid` — parent station VID
    - `position` — 1-based index or row/col on the keypad
    - `vantage_internal_name` — what Vantage calls it internally (often a typo of the label or something generic like "Button 3")
- Linked via:
  - `part_of` → keypad DEVICE entity
  - `located_in` → room (inherited from keypad, but explicit is fine)
  - `controls` → the load DEVICE(s) or `triggered_by` relationship to a task/automation entity it invokes

### What each button can do

Buttons map to one of several action types:
- **Load control** — toggle/dim a specific load or load group → `controls` relationship to DEVICE(s)
- **Task trigger** — invoke a Vantage task → `triggered_by` relationship from automation entity
- **Scene-like** — sets multiple loads to specific levels → multiple `controls` relationships
- **Unused/no-op** — some buttons aren't wired to anything → mark `content.action: "none"` and move on

### Walk flow additions

During `/room-walk` Phase 2 discovery, after cataloging devices and doors, The agent prompts:

> "Any keypads in this room? Send me a photo of each, labels visible. I'll extract what each button does."

For each keypad photo:
1. The agent reads the image (Claude Code's Read tool handles images)
2. Extracts button labels via vision — reads "UP LIGHTS / OVERHEAD / CANS / READING / DIM / ALL OFF" etc.
3. Queries Vantage for the station's VID and button VIDs by fuzzy match on area + button count
4. For each button, asks the user interactively:
   > "Button 2 is labeled 'OVERHEAD'. What does it control? I can flash each load to help identify."
5. User describes, or The agent probes: "I'll flash load X, tell me if that's what OVERHEAD controls"
6. Build draft entries for keypad + buttons + relationships

### Draft entry for a keypad walk

```json
{
  "keypad": {
    "discovery_action": "create",
    "entity_type": "device",
    "name": "Living Room Entry Keypad",
    "content": {
      "aliases": ["the switch by the door", "entry keypad"],
      "vantage": {"vid": 2103, "station_type": "Keypad", "button_count": 6},
      "photos": ["<base64 image>"]
    },
    "located_in_room_id": "<living-room-id>"
  },
  "buttons": [
    {
      "entity_type": "device",
      "name": "Overhead",
      "content": {
        "label_raw": "OVERHEAD",
        "vantage": {"vid": 2105, "keypad_vid": 2103, "position": 1, "vantage_internal_name": "Button 1"}
      },
      "part_of": "<keypad-id>",
      "controls": ["<living-room-overhead-load-id>"]
    },
    {
      "name": "All Off",
      "content": {
        "label_raw": "ALL OFF",
        "vantage": {"vid": 2106, "keypad_vid": 2103, "position": 2}
      },
      "part_of": "<keypad-id>",
      "triggered_by": "<living-room-all-off-task-id>"
    }
  ]
}
```

### Typo handling

Keypad labels are the authority. If the physical keypad says "POUNTAIN" and Vantage's internal name is "ENTRY POUNTAIN," we keep the cleaned canonical name ("Fountain" or "Entry Fountain") but preserve both raw versions:
- Load entity: `name: "Entry Fountain"`, `content.vantage.original_name: "ENTRY POUNTAIN"`
- Button entity: `name: "Fountain"` (cleaned), `content.label_raw: "POUNTAIN"` (as physically labeled)

When the user says "the pountain" by habit or local convention, it matches via `label_raw` or an alias.

### Edit flow for keypads

`/room-edit` supports:
- Updating button labels if a physical relabel happens (peel-off label replaced)
- Re-photographing a keypad
- Changing what a button controls (rewired in Vantage)
- Marking unused buttons
- Adding aliases to buttons or keypads

## 4. Shared Machinery

Both skills use:

### `room_session.py` — session state management
- `create_session(room, type)` → session_id
- `load_session(session_id)` → draft
- `update_session(session_id, patch)`
- `commit_session(session_id)` → applies all diffs via REST
- `archive_session(session_id)`

### `fg_client.py` (blowing-off wrapper)
- `find_entity_by_name(name, entity_type)` — fuzzy entity lookup
- `list_entities(entity_type)`
- `create_entity(entity_type, name, content)` / `update_entity(entity_id, patch)`
- `create_relationship(from_id, to_id, rel_type)`
- `upload_blob(entity_id, image_bytes)` — creates blob entity, links via has_blob

### `vantage_probe.py` — live Vantage interaction
- `flash_load(vid, duration_s)` — temporarily set on, restore previous
- `get_load_level(vid)` — query current level
- `find_loads_in_area(area_name_pattern)` — fuzzy area match

### Review HTML generator
- Takes session draft → renders HTML
- Includes photos inline, vantage VIDs, before/after diffs for edits
- Uploads via `POST /view` → returns tunnel URL
- Includes a prominent "this is a preview — no changes written yet" banner

---

## 5. Failure Modes & Handling

- **Session abandoned mid-walk** → next session-start hook detects pending sessions and asks "You had a room-walk in progress for Bedroom from 2h ago. Resume, discard, or commit what you had?"
- **Review link not clicked** → no writes happen. Session stays open indefinitely until committed or explicitly discarded.
- **Commit fails partway** → transaction-style with rollback. Each entity create/update is atomic. If relationship creation fails, delete the orphan.
- **Ambiguous names in commit** → reject the commit, show the ambiguity, ask for resolution.
- **Vantage controller unreachable** → walk continues without probing, notes "device catalog only, not tested."
- **User says "commit" but there are unsaved edits in the conversation since the last review** → regenerate review first, send new link.

---

## 6. What Lives Where

- **Skills**: `.claude/skills/room-walk/SKILL.md`, `.claude/skills/room-edit/SKILL.md`
- **Shared scripts**: `.claude/scripts/room_session.py`, `.claude/scripts/fg_client.py`, `.claude/scripts/vantage_probe.py`, `.claude/scripts/render_review.py`
- **Session state**: `.instar/state/room-session-*.json` (active), `.instar/state/archive/` (completed)
- **Session transcripts**: stored as `note` entities in FunkyGibbon, linked `documented_by` to the room
- **MEMORY.md**: brief completion entries only, not detail dumps (the graph has the details)

---

## 7. Design Decisions

1. ~~**Review medium**?~~ **DECIDED (2026-04-12): Private Viewer HTML via tunnel link. Verified working end-to-end via iMessage. Links are markdown-rendered, signed (tamper-resistant), and readable on phone. Caveat: quick tunnel URLs change on server restart — if we want review links to survive restarts, upgrade to a named Cloudflare tunnel later.**
2. ~~**Photo retention**?~~ **DECIDED (2026-04-12): Store all photos, but downsample/compress first. Target ~100KB per image max.**
   - Before upload, re-encode to JPEG at ~80% quality with max dimension ~1600px (keypad labels still readable, room photos still useful).
   - Python: `from PIL import Image; img.thumbnail((1600,1600)); img.save(buf, 'JPEG', quality=80, optimize=True)`.
   - `/room-edit` supports removing individual photo blobs when they're redundant or mis-tagged.
   - Blob entity `content` records original filename, capture timestamp, and a one-line description (extracted from the user's iMessage context).
3. ~~**Vantage probe intensity**?~~ **DECIDED (2026-04-12): Full flash. Walks will mostly happen during the day, so 0→100→0 (then restore previous level) is fine. No special nighttime mode needed for now. If a nighttime walk happens, the user can ask the agent to "use a gentle flash" and the helper will reduce intensity for that session.**
4. ~~**Session expiration**?~~ **DECIDED (2026-04-12): Never auto-expire. Sessions stay open until explicitly committed or discarded. On commit, the session state file moves to `.instar/state/archive/` and is preserved indefinitely for audit and replay. Design implication: session files should be self-contained (all context needed to replay — starting state snapshot, all decisions made, all photos referenced by blob entity IDs). A future `/room-replay <session-id>` skill can re-apply a past walk's decisions if FunkyGibbon state is lost or rolled back, or reconstruct "what did the user decide about the pool keypad on April 15?"**
5. ~~**Undo skill**?~~ **DECIDED (2026-04-12): No separate undo skill. `/room-edit` handles corrections — rename, remove, move, restore status, etc. FunkyGibbon's versioning preserves history, so if the user wants to see what changed, he can query the entity's versions directly. If a full rollback of a walk is ever needed (e.g., someone accidentally committed wrong data), that's handled via archived session state + manual edit, not a dedicated skill.**
6. ~~**Bulk ops**?~~ **DECIDED (2026-04-12): No bulk operations for now. All changes go through per-room walks or per-room edits. If a systematic cleanup is needed later (e.g., fix typos across many rooms), it can be a separate scripted migration with its own review — not part of the walk/edit skills.**

---

## 8. Next Steps

1. Review this spec, answer §7 questions
2. Build `room_session.py` + `fg_client.py` (shared infra)
3. Build `/room-walk` skill using the shared infra
4. Test with one room end-to-end
5. Build `/room-edit` on the same infra
6. Test with a known room, run discovery → edit → verify
7. Document in a short usage note in MEMORY.md
