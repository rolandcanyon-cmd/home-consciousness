---
name: room-edit
description: Edit a previously-catalogued room — rename, add/remove aliases, move devices between rooms, fix typos, mark devices inoperable, remove dead entries. Same review-before-commit pattern as /room-walk.
metadata:
  user_invocable: "true"
---

# /room-edit

Targeted edits to an already-catalogued room. Loads the current state, walks through changes the user wants, produces a review, commits on confirm.

If the room has never been catalogued, tell the user to use `/room-walk` instead.

Design spec: `.instar/context/room-walk-skill-spec.md` — same machinery as `/room-walk`, but starts from "what's there" rather than "what's missing".

## When to use

- "Fix the Living Room" / "Edit [room]" / `/room-edit [room]`
- You need to rename a device, add an alias, mark something inoperable
- A device was catalogued in the wrong room — needs moving
- Removing a device that's been physically removed from the house
- Updating quirks/notes on an existing device

For adding new devices you just discovered, `/room-walk` is better (it's discovery-first). If you want to do both in one flow, start with `/room-walk` — it can also fix mis-located devices along the way.

## Helpers (shared with /room-walk)

Under `.claude/scripts/`:
- `kittenkong_helper.py` — FunkyGibbon REST client
- `vantage_probe.py` — needed only if the edit involves a Vantage probe to identify something
- `room_session.py` — session state
- `render_review.py` — review generator
- `room_commit.py` — applies diffs
- `image_compress.py` — new-photo handling

## Conversation shape

### Phase 1 — Snapshot

1. **Resolve the room** via kittenkong_helper:
   ```bash
   python3 .claude/scripts/kittenkong_helper.py rooms
   ```
   Handle ambiguity / missing rooms the same way `/room-walk` does. If the room has no devices (`list_devices_in_room` empty), suggest: "That room has no catalogued devices. Did you mean `/room-walk` instead?"

2. **Check for open sessions**:
   ```python
   open_sessions = RoomSession.find_open_for_room(room_name)
   ```
   Offer to resume if any exists.

3. **Build the snapshot**:
   ```python
   from kittenkong_helper import FunkyGibbon
   fg = FunkyGibbon()
   room = fg.find_entity_by_name("room", room_name)
   devices = fg.list_devices_in_room(room["id"])
   doors = fg.list_doors_for_room(room["id"])
   ```

4. **Create the session in edit mode**:
   ```python
   session = RoomSession.create(
       room_entity_id=room["id"], room_name=room["name"],
       mode="edit", initial_snapshot={"devices": devices, "doors": doors},
   )
   ```

5. **Present the current state** to the user via iMessage. Keep it concise:
   > "**Living Room** currently has 5 devices and 2 doors:
   >   • Front Drape (Lutron) — aliases: 'west drape'
   >   • Rear Drape (Lutron)
   >   • Overhead Light (Vantage VID 1781) — aliases: 'ceiling'
   >   • Floor Plug (Vantage VID 1799)
   >   • Big Picture Light (Vantage VID 1781)
   >
   > Doors: Living Room to Hall (manual), Living Room to Patio (exterior, smart Schlage)
   >
   > Room aliases: 'main room', 'big room'
   >
   > What would you like to change?"

### Phase 2 — Edit loop

Parse the user's requests into diffs. Common patterns:

**Rename**:
> "Call the Big Picture Light 'Fireplace Picture Light' instead"
```python
session.add_diff({
    "action": "rename_entity",
    "entity_id": "<device-id>",
    "old_name": "Big Picture Light",
    "new_name": "Fireplace Picture Light",
})
```

**Add alias**:
> "Also call it 'the painting light'"
```python
session.add_diff({
    "action": "add_alias",
    "entity_id": "<device-id>",
    "alias": "the painting light",
})
```

**Remove alias**:
```python
session.add_diff({
    "action": "remove_alias",
    "entity_id": "<device-id>",
    "alias": "obsolete name",
})
```

**Move to another room**:
> "The Big Picture Light is actually in the Dining Room, not here"
```python
dining = fg.find_entity_by_name("room", "Dining Room")
session.add_diff({
    "action": "move_to_room",
    "entity_id": "<device-id>",
    "new_room_id": dining["id"],
})
```

**Mark inoperable** (device is broken/dead but stays in the graph for history):
> "The Owner LIFX doesn't work anymore"
```python
session.add_diff({
    "action": "set_status",
    "entity_id": "<device-id>",
    "status": "inoperable",
    "reason": "bulb died 2026-04-12",
})
```

**Delete** (device physically gone, remove from graph — versioning preserves history):
> "The old Echo Dot is gone, we threw it out"
```python
session.add_diff({
    "action": "delete_entity",
    "entity_id": "<device-id>",
    "reason": "physically removed from house",
})
```

**Update content** (system metadata, notes, etc.):
```python
session.add_diff({
    "action": "update_device",
    "entity_id": "<device-id>",
    "patch": {
        "content_merges": {"notes": "Replaced LED strip in 2026-04"},
        "aliases_add": ["new alias"],
        "aliases_remove": ["old alias"],
    },
})
```

**Attach a new photo**:
```python
photo_id = session.attach_photo(source_path="/tmp/photo.jpg",
                                 description="After replacement")
session.add_diff({
    "action": "attach_photo",
    "entity_id": "<device-id>",
    "photo_id": photo_id,
    "description": "After replacement",
})
```

**Add a note entity** documenting history:
```python
session.add_diff({
    "action": "add_note",
    "entity_id": "<device-id>",
    "note_text": "Replaced in March 2026 because of failing capacitor. Old one kept in garage shelf 3.",
})
```

### Phase 2.5 — Ambiguity handling

If the user's reference is ambiguous ("the drape"), list candidates and ask:
> "I have Front Drape and Rear Drape — which one?"

If the user refers to a device by alias and you find multiple matches, same treatment.

If the user wants to probe a Vantage load to confirm which it is (for renames involving "the one by the window"):
```python
from vantage_probe import VantageProbe
v = VantageProbe()
v.flash_load(vid, duration=3.0)
```

### Phase 3 — Review

Same as `/room-walk`:
```python
from render_review import post_session_review
view = post_session_review(session)
# Send view['tunnelUrl'] via iMessage, wait for 'confirm'
```

The review groups updates into clear sections: renames, aliases, moves, status changes, deletes, content updates.

### Phase 4 — Edit or Confirm

On `confirm`:
```bash
python3 .claude/scripts/room_commit.py <session.id>
```

On `discard`:
```python
session.set_status("discarded")
```

On change requests, modify diffs and regenerate the review.

### Phase 5 — Handoff

After commit:
- Write a brief summary to `.instar/state/job-handoff-room-edit.md`
- Append to `.instar/MEMORY.md` under "Room Edits" section:
  > - 2026-04-13: Living Room — renamed 1, moved 2, marked 1 inoperable, deleted 1. Session `abc123…`
- iMessage the commit summary

## Important differences from /room-walk

- **Starts from existing state** — no discovery prompts about "what else is here?"
- **Smaller diff types** dominate — mostly update/rename/move/status, rarely creates
- **Deletes are explicit** and show up clearly in the review with "DELETE" callouts
- **Handles tombstones well** — even after commit, entity versions survive; if the user changes their mind, we can resurrect via a new `/room-edit` (or just edit the entity to change status back to operational)

## Constraints (same as /room-walk)

- Never write to SQLite directly
- Never commit without review + confirm
- Photos downsampled before upload
- Sessions never auto-expire
- Transcript preserved in the session file (audit trail)
- Commit creates a `note` entity linking to the room with the session summary

## What success looks like

- Each rename/move/status-change reflected in FunkyGibbon
- Entity versions have new `parent_versions` entries capturing the history
- A note on the room documents the edit session
- MEMORY.md has a one-line log entry
- Session archived
- the user got a confirmation iMessage: "Edited: N renames, M moves, K status changes, 0 errors"
