---
name: known-health-status-always-degraded
description: "GET /health has read status=degraded continuously since 2026-07-13 — all 26 degradationSummary entries are the one accepted vault divergence, so status and the count are constants that prove nothing and mask a real 27th entry"
metadata: 
  node_type: memory
  type: project
  originSessionId: e195c8f4-0b32-40e6-aed6-55c6b7b90e5f
  modified: 2026-08-02T23:07:15.706Z
---

`GET /health` returns `status: "degraded"` with `degradations: 26` — permanently. Verified 2026-08-02: all **26** `degradationSummary` entries reduce to exactly **1 distinct** string, the `SecretStore.dualKeyRead` keychain-vs-file master key divergence Adrian deliberately accepted on 2026-07-13 (`forceFileKey`, see [[known_vault_master_key_mismatch]] — do not re-litigate that decision).

**Why it matters:** the status field is a dead signal. It cannot change, so "degraded" is not evidence of anything, and a genuinely new degradation would appear as one line among 26 identical ones. This is signal masking, not a vault problem — the vault question is closed.

**How to apply:** when reading `/health`, ignore `status` and `degradations`. Reduce `degradationSummary` to its **distinct** entries and drop any mentioning SecretStore / dualKeyRead / master key. Nothing distinct remaining = healthy. A server that fails to respond at all, or low disk, is still reportable normally.

Applied 2026-08-02 to `.instar/jobs/user/health-check.md` (runs every 5 min on haiku; 276 runs on 08-02, all silent — it had effectively learned to ignore the whole endpoint). That file is under `jobs/user/`, so the edit is durable; a built-in under `jobs/instar/` would have been reverted at the next update.

Same defect class as [[known_jobs_api_null_toplevel_fields]] and the gated-job pointer trap in [[known_silent_cron_slot_miss]]: a diagnostic reading a signal that does not mean what it appears to mean. Tracked collectively as EVO-056.
