---
name: Token Ledger Observability (v0.28.77)
description: Token-usage visibility per session, project, and time window; Tokens dashboard tab; cluster resilience hardening
type: project
---

# Token Ledger Observability — v0.28.77

**What Changed:** Four PRs landed introducing token-usage observability (Phase 1), cluster resilience hardening, and Threadline improvements.

## New Capabilities

### Token Usage Visibility
- **GET /tokens/summary** — Total tokens (input, output, cache-read, cache-creation) per agent, per project, per hour/day window
- **GET /tokens/sessions** — Top sessions by total tokens with first-seen, last-seen, and message-count metadata
- **GET /tokens/by-project** — Project-level token breakdown across all sessions
- **GET /tokens/orphans** — Sessions idle for 30+ minutes (signal only, no kill authority)
- **Tokens dashboard tab** — Visual breakdown of top sessions, project breakdown, idle sessions

**Why it matters:** For the first time, I have precise visibility into token consumption. This is Phase 1 of token-management strategy; Phase 2 will compare different conversation strategies once we have real data. Phase 3 (smarter compaction or budget enforcement) will be informed by ledger evidence, never bolted on blind.

### Cluster Resilience Hardening
- Better recovery from startup hiccups involving native modules (better-sqlite3)
- Multi-signal launchd-supervised detection: now detects user-domain launchd (was missing before), systemd on Linux, explicit env-var markers
- Consecutive bind failures escalate to forced rebuild after 2 back-to-back unhealthy spawns

**Why it matters:** Fewer silent crash-loops on startup. More reliable self-repair.

### Threadline Inbox Writes
- Fixed: All three relay-ingest paths (pipe-mode, warm-listener, cold-spawn) now write to canonical inbox
- Canonical inbox `.instar/threadline/inbox.jsonl.active` was frozen since 2026-04-05; now receives entries from all relay paths
- Uses existing HKDF-derived signing key — no new key material

**Why it matters:** Complete observability of inbound Threadline messages in dashboard and any downstream consumer.

## How to Use

Check token usage anytime:
```bash
curl -H "Authorization: Bearer $AUTH" http://localhost:4040/tokens/summary
curl -H "Authorization: Bearer $AUTH" http://localhost:4040/tokens/sessions
```

The Tokens dashboard tab provides a visual summary. Check it when optimizing session length or conversation strategy.
