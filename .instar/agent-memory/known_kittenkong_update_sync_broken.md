---
name: kittenkong-update-sync-push-broken
description: "KittenKong (TypeScript, the-goodies-typescript/packages/kittenkong) create_entity+push works and is verified; update_entity+push sends 0 changes -- not yet wired into .mcp.json because of this"
metadata: 
  node_type: memory
  type: project
  originSessionId: f8495a47-4279-48d2-a1ae-310a26d2ff27
---

> **RESOLVED 2026-09-13 by the v0.8.0 upgrade.** UPGRADE.md states the root cause plainly:
> *"MCP writes were never committed. Every write through `/api/v1/mcp/tools/{name}` was rolled
> back when the request ended."* Not a client bug. Do not re-diagnose; re-test against v0.8.0
> before treating anything here as live. See [[project-goodies-v080-upgrade-done]].


> **STALE AS OF 2026-09-13 — CHECK BEFORE ACTING.** `rolandcanyon-cmd/the-goodies-typescript`
> is now deprecated; the primary TypeScript repo moved to the `adrianco` account, and an upgrade
> of the-goodies stack is underway (Corfe pilots it first). Do NOT fix this defect here without
> confirming the work still belongs in this repo. See [[project-goodies-upgrade-and-repo-move]].

2026-07-15, following the FunkyGibbon sync-push investigation ([[known_funkygibbon_sync_push_broken]]): Adrian asked whether room-walk/room-edit should use KittenKong's MCP server instead of hand-rolled REST. KittenKong (`the-goodies-typescript/packages/kittenkong`) is NOT abandoned — real code, all 12 MCP tools implemented (`src/mcp-server.ts`), explicit sync push logic (`src/sync/engine.ts`, `src/sync/protocol.ts` POSTs to `/api/v1/sync/`) — but it was never registered in this project's `.mcp.json`, so it isn't available as an MCP tool.

Rebuilt (`npm run build --workspace=@the-goodies/kittenkong`, was stale since April) and tested end-to-end with a standalone `tsx` script importing `KittenKongClient` directly:

- **`createEntity` + `sync()`: verified working.** A test entity created locally and synced showed up immediately in the real server DB (confirmed via direct REST read).
- **`updateEntity` + `sync()`: broken.** Updating the same entity's content, then calling `sync()` again, reported `changesSent: 0` — the server-side entity's version never changed. `KittenKongClient` is an explicit TS port of the Python `blowing-off` client (docstring says so), so this looks like the same defect class carried over, though the specific mechanism differs: `sync()` does pull-then-push in one call (`src/sync/engine.ts` `sync()`, Step 1 pull / Step 4 push), and the pull step's `applySingleChange` for the SAME entity plausibly overwrites the just-updated in-memory copy before the push step's `getLocalChanges()` reads `pendingSyncEntities` — not fully root-caused/fixed, just characterized enough to know it's real and where to look next.

**How to apply:** do NOT register kittenkong in `.mcp.json` as the primary graph interface until `updateEntity`'s sync push is fixed and re-verified (same standalone-script test pattern works well: create → sync → verify via REST; update → sync → verify via REST). Until then, Python-side room-walk/room-edit work should keep using `fg_client.py`'s direct-REST approach (confirmed working). If/when kittenkong's update-push is fixed, `LocalGraphStorage` (`src/graph/local-storage.ts`) is also worth noting as pure in-memory (no disk persistence at all, unlike Python's JSON-file cache) — it starts empty every process, so a fresh client always needs a pull before any read/update makes sense.

Test probe entities: `ent-1784163314056-xlxk3z` (marked `status: diagnostic-probe` via REST afterward) — harmless, safe to ignore, do not re-diagnose.
