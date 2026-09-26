---
name: funkygibbon-sync-push-broken
description: "blowing-off's local-cache-first-then-sync design is correct (offline-first, by design) — the bug is specifically that sync push (local -> server) doesn't work; fg_client.py works around it with direct REST calls"
metadata:
  node_type: memory
  type: project
  originSessionId: f8495a47-4279-48d2-a1ae-310a26d2ff27
---

> **RESOLVED 2026-09-13 by the v0.8.0 upgrade.** UPGRADE.md states the root cause plainly:
> *"MCP writes were never committed. Every write through `/api/v1/mcp/tools/{name}` was rolled
> back when the request ended."* Not a client bug. Do not re-diagnose; re-test against v0.8.0
> before treating anything here as live. See [[project-goodies-v080-upgrade-done]].


Discovered 2026-07-15 during a /room-edit session (adding the AWN console's Dining Room location). **Correction (per Adrian, same day):** local-cache-first-then-sync is the *intended* offline-first architecture for blowing-off's `LocalGraphOperations`/`LocalGraphStorage` — that pattern is correct by design, not itself a bug. The actual, narrower defect: the sync mechanism's **push** direction (local cache → server) does not appear to work. `self._client.sync()` reports success (`synced_entities: 420`) but this looks like a pull only — writes made via `create_entity`/`update_entity`/`create_relationship` landed in the local JSON cache (`.instar/state/.blowing-off-graph/{entities,relationships,index}.json`) and appeared to succeed, but never reached the real server database at `~/the-goodies/funkygibbon.db`.

Root cause confirmed by direct comparison: a raw REST call (`POST/PUT/GET http://localhost:8000/api/v1/graph/...` with the Bearer token from `~/the-goodies/.blowingoff.json`) persisted correctly and was immediately visible in the real server db; the identical operation through the old `fg_client.py` (via blowing-off's local graph layer) was not.

**Why this matters:** it's unclear whether any *update-type* room-edit operation (rename, alias, status change, move) had ever actually pushed to the server before this — the 5 historical room walks (Kitchen, Studio, Bar BQ, Living Room, Dining Room) only ever used `create_entity`, the same op type that failed to push here, yet real device data for those rooms clearly exists server-side today. Either an earlier version of the sync push worked and has since regressed, or those creates went through a different path (e.g. a populate/seed script, or the `oook` CLI) — not fully root-caused, and not worth re-investigating unless something looks newly missing.

**How to apply — this is a workaround, not a fix to the underlying sync engine:** `.claude/scripts/fg_client.py` was rewritten 2026-07-15 to call the REST API directly via `httpx`, bypassing blowing-off's local cache + sync entirely. This is reasonable for Claude Code agent scripts (always online, same machine as the server) but **it discards the offline-first capability the local-cache design is for** — it is not a substitute for actually fixing blowing-off's sync push, which would be the more correct long-term fix if offline operation (e.g. a mobile client, or the server being briefly down) ever matters for this tool. Public method signatures on `FGClient` (`create_entity`, `get_entity`, `update_entity`, `list_entities`, `find_entity_by_name`, `search_entities`, `create_relationship`, `list_relationships`, `upsert_alias`, `remove_alias`, `set_status`, `delete_entity`, `upload_blob`, `get_home`) are unchanged, so `room_commit.py`/`room_session.py` didn't need edits. **Always verify a room-walk/room-edit session's changes landed for real** (e.g. `fg.get_entity(id)` after commit) rather than trusting a clean `commit_session()` result alone.

Also fixed along the way (same session, independent of the sync-push issue): `Entity.to_dict()` and `EntityRelationship.to_dict()` in `the-goodies-python/inbetweenies/models/` crashed with `AttributeError: 'str' object has no attribute 'isoformat'` on freshly-created entities/relationships whose `created_at`/`updated_at` hadn't round-tripped to a real datetime yet — now defensively check `hasattr(..., "isoformat")` first. And `fg_client.py`'s old `update_entity` passed the content dict directly as `changes` instead of `{"content": content}`, which caused `Entity.create_new_version()` to merge content sub-fields (e.g. `"system"`, `"homekit_pk"`) onto the entity's top-level dict, crashing entity reconstruction — fixed by properly nesting `changes["content"]` (this one applies regardless of REST-vs-local-cache, since the server's own PUT /entities/{id} route does the same nesting correctly and would have hit the same class of bug if fg_client had kept using it wrong).

See also [[known_funkygibbon_relationship_version_pinning]] for a related, still-unfixed gotcha this surfaced.
