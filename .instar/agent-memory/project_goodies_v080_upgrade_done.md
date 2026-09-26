---
name: project-goodies-v080-upgrade-done
description: the-goodies upgraded v0.3.0 to v0.8.0 on 2026-09-13; graph REST is gone, MCP is the interface, KittenKong runs via a tsx workaround
metadata:
  type: project
---

Completed **2026-09-13**. Server upgraded v0.3.0 → **v0.8.0** (`16375c6`), migration applied,
`migrate --verify --domain domains.house.manifest:HOUSE` = **PASS**.

**Data preserved exactly**: 423 entities / 461 relationships / 27 blobs / 3,741,948 blob bytes —
byte-identical to the pre-upgrade baseline (`.instar/state/upgrade/pre-v0.8-baseline-20260913.txt`).
Backup: `~/the-goodies/backups/pre-v0.8.0-20260913-155318.db` (verified by re-count + integrity_check).

Migration effects, all as predicted by the dry-run: 48 `part_of room→home` → `located_in`;
27 blob-carrying notes → `photo`; 26 `has_blob` → `has_photo`; 1455 type values lowercased;
461 edges converted to interval rows. My 104 `part_of device→device` (keypad buttons) survived
untouched — the #90 fix works on real data.

**What changed for me operationally:**
- `/api/v1/graph/*` is **GONE (404)**. MCP is the only interface: `/api/v1/mcp/tools/<name>`.
- Entity/relationship types are **lowercase** now (were UPPERCASE).
- Every write is a version; deletes are tombstones; ending an entity does NOT end its edges.
- Client token in `~/.oook/config.json`; KittenKong prefers `FUNKYGIBBON_TOKEN` over `FUNKYGIBBON_PASSWORD`.

**KittenKong v0.8.1** runs from the built artifact: `node .../packages/kittenkong/dist/mcp-server.js`,
declared once in `.claude/settings.json`. v0.8.0's build could not start under node (extensionless ESM
imports) — filed as adrianco/the-goodies-typescript#3, fixed same day in v0.8.1 (real ESM, `NodeNext`,
a `kittenkong-mcp` bin, and a dist-entrypoint smoke test). The `tsx` workaround is gone.

**Tooling migrated 2026-09-13 — no live caller of the dead REST remains.**
- `morning-weather` now resolves the Tempest URL over MCP (`search_entities` -> `get_entity_details`;
  `search_entities` returns summaries WITHOUT full `content`, so both calls are needed). Token key in
  `~/.oook/config.json` is **`auth_token`**, not `token`.
- Adopted upstream's house skills + scripts wholesale (room-walk, room-edit, app-walk, **align-rooms**,
  plus fg_client/room_session/room_commit/app_session/app_commit/render_review/image_compress).
  Upstream's `fg_client.py` keeps the old public method names, so callers work unchanged.
- `kittenkong_helper.py` RETIRED (every call used the removed REST; no live caller). Old copies in
  `.instar/state/upgrade/pre-v0.8-local-tooling-20260913-234024/` with a README.
- My two "missing upstream" capabilities were already in v0.8.0, generalised — launch links via
  `FG_APP_LAUNCH_URLS` + `app_session.get_launch_url()` (fed from `shortcut-library.json` into
  `.instar/state/app-launch-urls.json`), and the UniFi AP->room heuristic. Issue #95 closed.
- KittenKong declared ONCE, in `.claude/settings.json` (not `.mcp.json`), token-only — the
  `FUNKYGIBBON_PASSWORD` was dropped per the Corfe field notes.

**Verified by `fg_client_selftest.py`: 23 passed, 0 failed** (incl. separate-process read-backs and
`device part_of device: accepted`).

**TRAP — the self-test dirties a live graph.** It tombstones its throwaway entities but does NOT end
their edges, so relationships crept 461 -> 465 while `--verify` still said PASS. Cleaned with 4
`end_relationship` calls. Filed as issue #96. Always re-check counts after running it.

**TRAP — `migrate --verify` mislabels counts.** It reports `is_latest` rows and ALL edge rows as
"current" (431/466 here) while `get_statistics` reports genuinely current (423/461). The MCP number is
the right one. Filed as issue #97. Do not read a `--verify` count as a baseline comparison.
