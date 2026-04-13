# Vantage ↔ HomeKit Mapping Plan

**Status:** Draft
**Goal:** Let Roland control Vantage devices using HomeKit-canonical names (rooms and devices) without introducing a parallel naming system. Vantage remains the hardware layer; HomeKit names are the user-facing vocabulary.

---

## 1. Problem Statement

Vantage inventory (from controller at 10.0.0.50):
- 15–20 areas (inconsistent hierarchy, some nested areas only referenced by loads)
- 83 loads with inconsistent names (typos like `ENTRY POUNTAIN`, stray spaces, generic names like `Station Load 1`)
- 360 tasks (scenes/automations)
- 511 keypad buttons
- Various sensors, thermostats, dry contacts

HomeKit inventory (as ingested into FunkyGibbon):
- 1 HOME entity
- 48 ROOM entities (full set — supersedes the 11-room first-pass in MEMORY.md)
- 23 DEVICE entities

**The two systems overlap but don't align cleanly:**
- Some Vantage loads correspond 1:1 to HomeKit devices (e.g., a specific dimmable light)
- Some Vantage loads have no HomeKit counterpart (outdoor fountains, path lights, exterior flood lights — Vantage-only territory)
- Some HomeKit devices have no Vantage counterpart (Schlage locks, ecobee thermostats, LIFX bulbs — HomeKit-native)
- Area/room boundaries drift: Vantage "BED" vs HomeKit "Bedroom" — probably the same, but needs verification

## 2. FunkyGibbon Schema — What We Have to Work With

### Entities
Every entity has:
- `id` (UUID), `version`, `entity_type`, `name`, `user_id`
- **`content` (JSON, free-form)** — this is where mapping data lives
- `source_type` — one of: `homekit`, `matter`, `manual`, `imported`, `generated`
- Full versioning via `parent_versions`

### Entity types
`home`, `room`, `device`, `zone`, `door`, `window`, `procedure`, `manual`, `note`, `schedule`, `automation`, `app`

### Relationships
`located_in`, `controls`, `connects_to`, `part_of`, `manages`, `documented_by`, `procedure_for`, `triggered_by`, `depends_on`, `contained_in`, `monitors`, `automates`, `controlled_by_app`, `has_blob`

**Crucially:**
- `content` is a typed-as-object JSON field — can hold arbitrary structured metadata
- Relationships are first-class — we can link entities with semantic meaning
- `note` is an entity type — we can attach free-form notes as their own entities
- `source_type: imported` exists specifically for non-HomeKit data

## 3. Approach: Annotate Existing Entities, Don't Duplicate

We do **not** create a parallel tree of "VantageDevice" and "VantageRoom" entities. That would fragment the graph. Instead:

### 3.1 Annotate HomeKit entities with Vantage bindings

For every HomeKit ROOM or DEVICE that has a Vantage equivalent, add to its `content` JSON:

```json
{
  "homekit_id": "...",  // existing homekit metadata preserved
  "homekit_room_id": "...",
  "vantage": {
    "vids": [42, 43],       // one or more Vantage VIDs this entity maps to
    "area_vid": 85,         // the Vantage area this device lives in (if device)
    "kind": "load",          // load | task | thermostat | dry_contact | keypad | area
    "capabilities": ["on_off", "dim"],  // what actions are valid
    "notes": "Entry pountain [sic] — typo in Vantage"  // optional, for quirks
  }
}
```

**Why `vids` (plural):** Some HomeKit "accessories" correspond to multiple Vantage loads controlled together (e.g., "Kitchen cans" = 4 loads). Keep the list even when there's only one.

### 3.2 Create `imported` entities for Vantage-only devices

For Vantage loads/tasks that have no HomeKit counterpart (outdoor fountains, path lights, scene tasks), create entities with:

- `source_type: "imported"` (distinguishes from `homekit`)
- `entity_type: "device"` (or `automation` for tasks/scenes)
- `name`: the **corrected** canonical name (not the Vantage raw name) — e.g., "Entry Fountain" not "ENTRY POUNTAIN"
- `content.vantage`: same schema as above
- Linked via `located_in` relationship to the appropriate ROOM entity

This way, kittenkong queries for "all devices in the pool area" return both HomeKit and Vantage-only devices from the same query.

### 3.3 Create ROOM entities for Vantage areas that aren't HomeKit rooms

The property has outdoor zones (entry, pool area, paths, fountain areas) that exist in Vantage but aren't real HomeKit "rooms." Create these as ROOM entities with `source_type: "imported"`, linked to the HOME as `located_in`.

### 3.4 Notes for quirks and history

For each mapping that required judgment (typo fixes, ambiguous name matches, loads that share a single physical fixture), attach a `note` entity with:
- `entity_type: "note"`
- `source_type: "manual"`
- Relationship: `documented_by` from the HomeKit device to the note
- `content`: `{"about": "mapping", "vantage_vid": N, "reason": "..."}`

This makes the mapping decisions auditable without cluttering the device `content`.

## 4. The Vantage Helper Tool

Once the graph is annotated, the tool pattern is:

```
User: "Turn on the entry fountain"
  ↓
Roland: kittenkong.search("entry fountain")
  → returns DEVICE entity (HomeKit "Entry Fountain" or imported)
  ↓
Roland: reads entity.content.vantage.vids → [2454]
  ↓
Roland: vantage_cli load 2454 100
  ↓
Vantage controller turns on VID 2454
```

The helper tool (`vantage_cli` or its Python equivalent):
- Takes HomeKit-canonical names OR entity UUIDs as input
- Looks up VIDs via FunkyGibbon (kittenkong for TypeScript, direct REST for Python)
- Executes the Vantage command via port 3001
- Optionally writes state changes back to FunkyGibbon (so the graph reflects current on/off/level)

The helper is dumb — it's a name→VID translator + TCP command sender. All intelligence (fuzzy matching, disambiguation, "which fountain did you mean") lives in Roland's reasoning layer, not in the tool.

## 5. Mapping Process — Build It Incrementally

### Phase 1: Schema & data
1. Dump current FunkyGibbon state (rooms + devices + relationships)
2. Dump current Vantage state via port 2001 XML (or `aiovantage` as reference)
3. Produce a side-by-side CSV/JSON for human review: `{vantage_vid, vantage_name, vantage_area, candidate_homekit_id, candidate_homekit_name, match_confidence}`

### Phase 2: Automated matching
For each Vantage load:
- Match by area name (case-insensitive, normalized: "BED" == "Bedroom", "LIV" prefix == "Living Room")
- Match by load name tokens (fuzzy — drop typos, stopwords)
- Assign confidence: `exact`, `likely`, `ambiguous`, `vantage_only`

### Phase 3: Human review
- Adrian reviews the `ambiguous` and `vantage_only` rows
- Adds corrections (correct name, correct area, intentional non-mapping)
- Output: authoritative mapping file

### Phase 4: Apply mappings via kittenkong
- Update HomeKit DEVICE entities with `content.vantage` bindings
- Create imported DEVICE entities for Vantage-only loads with proper names
- Create imported ROOM entities for outdoor Vantage areas
- Create `note` entities for quirks
- Establish relationships (`located_in`, `controls`)

### Phase 5: Helper tool
- Python CLI (`vantage_cli`) used by Roland internally
- Reads mappings from FunkyGibbon via REST
- Sends commands to Vantage port 3001
- No direct name lists — always queries live

### Phase 6: Feedback loop
- Each time Adrian uses a name that fails to match, log it
- Weekly review of unmatched queries → improvements to aliases

## 6. Alias Handling

HomeKit name is canonical, but people say things differently:

- "living room lights" → could match multiple loads
- "the main light" → ambiguous without context
- "pool lights" → could be pool house lights vs pool area underwater lights

Store aliases in `content.aliases` on each entity:

```json
{
  "name": "Living Room Overhead",
  "content": {
    "aliases": ["main light", "overhead", "ceiling light"],
    "vantage": { "vids": [1781] }
  }
}
```

The helper tool does:
1. Exact match on canonical name
2. Substring match on aliases
3. Fuzzy match (Levenshtein) on both if no hit

When multiple matches, Roland asks for clarification instead of guessing.

## 7. Open Questions for Adrian

1. ~~**Tasks/Scenes**: map to HomeKit scenes?~~ **DECIDED (2026-04-12): Vantage tasks and HomeKit scenes are independent. No cross-mapping. Vantage tasks stay Vantage-only.**
2. ~~**Keypad buttons**: model them or not?~~ **DECIDED (2026-04-12): Yes, model keypads and buttons. Adrian photographs each keypad during room walks; button labels (with their own typos and quirks) are captured and correlated to what each button controls. Keypads are DEVICE entities (one per keypad), buttons are DEVICE entities with `content.keypad_id`, and control is modeled via `controls` relationships from button → load/task. Photos of keypads stored as blobs.**
3. ~~**State sync direction**?~~ **DECIDED (2026-04-12): Query-on-demand only. FunkyGibbon holds structural data (what exists, where, connected to what). Runtime state (current load level, on/off, thermostat reading) stays in Vantage. When a user wants to change something, Roland queries current state first, sends the change command, then verifies it actually changed. No event-stream listener; no persistent state mirroring.**
4. ~~**Outdoor zone naming**?~~ **DECIDED (2026-04-12): Don't pre-plan. HomeKit already has some outdoor areas (pool area, driveway gate, etc.). The room-walk skill will reuse existing ones when they fit and create new `source_type: "imported"` ROOM entities interactively when a walk finds devices that don't belong to any current room. Adrian confirms the name at walk time.**
5. ~~**Vantage-only tasks**?~~ **DECIDED (2026-04-12): Only model the few user-facing tasks Adrian wants in a skill. The rest (scheduled automations, internal logic) stay inside Vantage and are not represented in FunkyGibbon. When modeling a task: create an `automation` entity with `source_type: "imported"`, store the Vantage task VID in `content.vantage.task_vid`, and link via `triggered_by` from any keypad buttons that invoke it. Selection of which tasks to model happens interactively during room walks when Adrian points to a keypad button that triggers a task.**

## 8. Non-Goals

- **Not** replacing Vantage as the automation engine (it stays authoritative for hardware control)
- **Not** replacing HomeKit as the user-facing registry (it stays canonical for names)
- **Not** exposing the full 360-task list — only the meaningful ones
- **Not** synchronizing in both directions without careful thought (Vantage→graph OK, graph→Vantage config is risky)

## 9. Next Step

Adrian reviews this plan and answers the questions in §7. Then Phase 1 (data dump + side-by-side) is ~a day of work, after which we have something concrete to review.
