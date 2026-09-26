---
name: funkygibbon-relationship-version-pinning-gotcha
description: "FunkyGibbon relationships pin to the entity's version at creation time; updating an entity afterward silently hides its older relationships from queries"
metadata: 
  node_type: memory
  type: project
  originSessionId: f8495a47-4279-48d2-a1ae-310a26d2ff27
---

FunkyGibbon's `GraphRepository.get_relationships()` (`the-goodies-python/funkygibbon/repositories/graph_impl.py`) filters results to relationships whose `from_entity_version`/`to_entity_version` match the entity's **current** version — but a relationship's version fields are a snapshot pinned at the moment the relationship was created (entities are versioned/immutable; every `update_entity` call creates a new version). So: create a `located_in` relationship, then later update the device's content/aliases (a new version), and that `located_in` relationship becomes invisible to `get_devices_in_room` / `GET /entities/{id}?include_relationships=true` — even though the row still physically exists in `entity_relationships`. Nothing is deleted; it's just silently filtered out.

Discovered 2026-07-15: after updating the AWN console's content (mac, notes) and adding aliases, its Dining Room `located_in` relationship (created earlier in the same session) stopped appearing in Dining Room's incoming relationships — even though the raw DB row was there. Also NOT a hard bug for removing stale locations — since there's no relationship-delete API ([[known_funkygibbon_local_client_broken]]), an old `located_in` edge to a device's PREVIOUS room also goes invisible the same way once the entity's version moves on, which is a convenient (if accidental) side effect: a device doesn't visibly show as being in two rooms at once, it just silently drops the stale one.

**How to apply:** when a room-walk/room-edit session both (a) creates/needs a `located_in` (or any) relationship AND (b) updates the same entity's content/aliases/status in the same session, **create or re-create the relationship LAST**, after all content updates are done — so it's pinned to the entity's truly final version. If a relationship seems to have "disappeared" after an edit, this is almost certainly why — don't assume data loss, just re-create the relationship against the entity's current version.
