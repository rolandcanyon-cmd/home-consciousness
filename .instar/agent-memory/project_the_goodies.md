---
name: The Goodies Ecosystem
description: FunkyGibbon knowledge graph server, blowing-off Python client, oook CLI, KittenKong TS client — architecture, usage status, and how to use them
type: project
originSessionId: fa7f4361-7f07-42c7-a90a-d1809fb61a19
---
## The Goodies — Smart Home Knowledge Graph Stack

### FunkyGibbon
The knowledge graph server. Stores entities (rooms, devices, apps, notes) and relationships. Runs at `http://localhost:8000`. Requires Bearer token auth on all endpoints (except health). Admin login: `POST /api/v1/auth/admin/login` with `{"password": "admin"}`.

Key endpoints:
- `GET /api/v1/graph/entities?q=...&entity_type=...` — search/list entities
- `GET /api/v1/graph/entities/{id}` — get by ID
- `POST /api/v1/graph/entities` — create entity
- `PATCH /api/v1/graph/entities/{id}` — update entity
- `POST /api/v1/graph/relationships` — create relationship

**Why:** `GET /api/v1/graph/search` returns 405. The correct search endpoint is `/api/v1/graph/entities` with `?q=` params.

### blowing-off (Python)
**The canonical Python client for FunkyGibbon.** Local SQLite cache with bidirectional sync. All Python scripts in home-consciousness should use this — not kittenkong_helper.py.

- Source: `the-goodies-python/blowing-off/`
- Install: `PYTHONPATH=the-goodies-python pip3 install -e the-goodies-python/inbetweenies/ && pip3 install -e the-goodies-python/blowing-off/`
- Async library — callers must use `async/await`
- One shared database path: `.instar/state/blowingoff.db`
- Depends on: `inbetweenies` (shared models/protocol, in `the-goodies-python/inbetweenies/`)

**Migration status:** kittenkong_helper.py (hand-written HTTP wrapper used by app_commit.py, room-walk scripts) needs to be replaced with blowing-off. Tracked in `.claude/todo/app-walk-cross-reference.md`.

### oook (CLI)
Direct command-line interface to FunkyGibbon for testing and verification. Good for checking that blowing-off synced correctly.

- Source: `the-goodies-python/oook/`
- Install: `pip3 install -e the-goodies-python/oook/`
- Run: `PYTHONPATH=the-goodies-python python3 -m oook -s http://localhost:8000 <command>`
- Commands: `stats`, `search "query"`, `get <id>`, `tools`, `execute <tool>`, `interactive`
- **Auth gap:** oook's MCPClient doesn't send a Bearer token — gets 401 on authenticated endpoints. Needs fix: add `--auth-token` option and pass it in Authorization header.

### KittenKong (TypeScript)
TypeScript port of blowing-off. Full-featured: in-memory graph cache (not disk-backed, unlike blowing-off), sync, all 12 MCP tools including a real `src/mcp-server.ts`. Lives in `the-goodies-typescript/packages/kittenkong/`.

**Still NOT registered in `.mcp.json`** as of 2026-07-15 (verified, not just carried over from this stale note). Tested end-to-end that day: `createEntity`+sync push works and is verified against the real server; `updateEntity`+sync push is broken (sends 0 changes). See [[known_kittenkong_update_sync_broken]] before wiring it in.

### kittenkong_helper.py (deprecated)
Hand-written Python HTTP wrapper for FunkyGibbon. Lives in `.claude/scripts/kittenkong_helper.py`. Does NOT use blowing-off — bypasses local cache, hits server directly. Was used by room-walk and app-walk scripts. Should be replaced with blowing-off.

**Why:** Was written before blowing-off was available/understood. Now that blowing-off is installed, use it instead.

## How to apply

- Writing Python code that reads/writes the knowledge graph → use blowing-off
- Verifying what's in FunkyGibbon from the command line → use oook (once auth is fixed)
- TypeScript code needing the knowledge graph → use KittenKong (when needed)
- Never use kittenkong_helper.py for new code
