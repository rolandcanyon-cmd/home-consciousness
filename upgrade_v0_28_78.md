---
name: Token Ledger Performance Fix (v0.28.78)
description: Bounded token ledger scan prevents startup stalls on deep session history
type: project
---

# Token Ledger Performance Fix — v0.28.78

**The Problem:** v0.28.77 token ledger had an unbounded synchronous first scan. On agents with deep Claude Code history (119K+ JSONL transcripts, 12 GB), the scan blocked the Node event loop for minutes, causing health checks to timeout and the lifeline supervisor to restart the server in a loop.

**The Fix:** Bounds the scan in three ways:

1. **Per-tick file cap** (default 500) with persistent cursor — First poll processes 500 files, next poll picks up where the previous stopped, cursor wraps to find newly-written sessions
2. **Intra-tick yielding** (every 25 files via setImmediate) — Event loop drains HTTP and health checks between batches, server stays responsive
3. **Optional max file age** (default 30 days) — Ignores transcripts older than the backfill window, focusing on recent activity first. Active sessions are never blackholed because appending a new turn updates mtime.

## What Changed

- New `scanAllAsync()` method in token ledger — the path the poller now uses
- Original `scanAll()` sync method preserved for tests and callers that don't need yielding
- No schema migration, no new routes, pure containment fix

## How to Use

On startup with deep session history:
- Tokens tab will fill in over the first few minutes instead of blocking until everything is read
- Server stays responsive to health checks and HTTP requests during the initial scan
- Configurable backfill window via `maxFileAgeMs` parameter (defaults to 30 days at wiring layer)

**Automatic on upgrade** — no configuration needed.
