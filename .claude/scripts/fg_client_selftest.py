#!/usr/bin/env python3
"""
fg_client_selftest.py — live gates for the FG client.

Runs against the real server with throwaway entities that are cleaned up at
the end. Every write is read back in a SEPARATE PROCESS to ensure durability.

    python3 .claude/scripts/fg_client_selftest.py
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from fg_client import FGClient, FGError

PASS = FAIL = 0

def ok(m):
    global PASS
    PASS += 1
    print(f"  ✓ {m}")

def bad(m):
    global FAIL
    FAIL += 1
    print(f"  ✗ {m}")

def check(cond, m):
    (ok if cond else bad)(m)

def readback_other_process(entity_id):
    """Read an entity from a fresh interpreter — no shared connection."""
    code = ("import sys,json; sys.path.insert(0,%r); from fg_client import FGClient; "
            "ent = FGClient().get_entity(%r); print(json.dumps(ent) if ent else '{}')") % (HERE, entity_id)
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
    try:
        return json.loads(out.stdout or "{}")
    except json.JSONDecodeError:
        return {}

def main():
    fg = FGClient()
    cleanup = []

    try:
        # Gate 1: Basic connectivity
        print("\n== gate 1: basic connectivity ==")
        rooms = fg.list_entities("room")
        check(isinstance(rooms, list), f"list_entities('room') returns a list ({len(rooms)} existing rooms)")

        # Gate 2: Create a test room
        print("\n== gate 2: create room and read back ==")
        test_room = fg.create_entity("room", "TestRoom_Selftest_001", {"source": "selftest"})
        check(test_room and test_room.get("id"), f"create_entity('room') returned id: {test_room.get('id')}")
        if test_room.get("id"):
            cleanup.append(test_room["id"])

            # Verify it's durable in another process
            rb = readback_other_process(test_room["id"])
            check(rb.get("id") == test_room["id"], f"created room persists (other process reads it)")
            check(rb.get("name") == "TestRoom_Selftest_001", f"room name correct: {rb.get('name')}")

            # Gate 3: Find by name
            print("\n== gate 3: find by name ==")
            found = fg.find_entity_by_name("room", "TestRoom_Selftest_001", strict=True)
            check(found and found.get("id") == test_room["id"], f"find_entity_by_name resolves correctly")

            # Gate 4: Update and verify
            print("\n== gate 4: update entity ==")
            fg.update_entity(test_room["id"], name="TestRoom_Updated", content={"source": "selftest", "updated": True})
            rb = readback_other_process(test_room["id"])
            check(rb.get("name") == "TestRoom_Updated", f"update persisted (name changed to: {rb.get('name')})")
            check(rb.get("content", {}).get("updated") == True, "update persisted (content updated)")

        # Gate 5: Create a note entity for variety
        print("\n== gate 5: create note entity ==")
        note = fg.create_entity("note", "selftest-note", {"body": "Testing...", "tags": ["test"]})
        check(note and note.get("id"), f"create_entity('note') returned id: {note.get('id')}")
        if note.get("id"):
            cleanup.append(note["id"])
            rb = readback_other_process(note["id"])
            check(rb.get("name") == "selftest-note" and rb.get("content", {}).get("body"), "note persists")

    except Exception as e:
        bad(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()

    finally:
        # Cleanup: tombstone test entities
        print("\n== cleanup ==")
        for entity_id in cleanup:
            try:
                fg.delete_entity(entity_id, reason="selftest cleanup")
                print(f"  tombstoned {entity_id}")
            except Exception as e:
                bad(f"Failed to cleanup {entity_id}: {e}")

        print(f"\n--- {PASS} passed, {FAIL} failed ---")
        sys.exit(0 if FAIL == 0 else 1)

if __name__ == "__main__":
    main()
