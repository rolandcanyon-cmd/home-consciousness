---
name: known-degradation-feedback-flood
description: "DegradationReporter forwards ~814 duplicate vault-divergence reports/day upstream and has evicted the agent's entire feedback history; feedback fb-af466c05-2b1 filed 2026-08-02"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7e3d897b-e041-48b9-9e2e-85b980735b56
  modified: 2026-08-03T03:06:29.250Z
---

`.instar/feedback.json` is a **1000-entry ring buffer and 995 of those entries are the same
`[DEGRADATION] SecretStore.dualKeyRead` report**, all `forwarded: true`. Measured over
2026-08-01T21:40Z → 2026-08-03T03:00Z: 29.3h span, 33.9/hr, **~814/day**, median inter-arrival
gap 0s (bursts within the same second).

**Root cause (traced in source, not theorised):** `SecretStore.noteReadKeySource()`
(src/core/SecretStore.ts:391) calls `DegradationReporter.report()` on *every read* where the
decrypting key ≠ primary. This agent's keychain/file master keys have permanently diverged —
the accepted 2026-06-05 bifurcation, running `forceFileKey` per Adrian's explicit call
(see [[known-vault-master-key-mismatch]]). So the condition is true on **every vault read**,
and the emit rate is the read rate. `DegradationReporter` *does* have a per-feature cooldown,
but it guards only the Telegram alert path (~line 776); the feedback submission (~line 741)
runs before it and is **not** cooldown-gated. The user is protected from spam; the maintainers
are not.

**Two harms:** upstream signal pollution at ~814/day from one agent, and *silent local data
loss* — the ring buffer has evicted essentially all prior feedback (only 5 non-duplicate
entries survive).

**Why it matters:** don't read a large `/feedback` count as "lots of issues found", and don't
trust `.instar/feedback.json` as a historical record — it holds roughly the last 30 hours of
noise. Filter by title before drawing any conclusion from it. Related but distinct from
[[known-health-status-always-degraded]], which is about `/health` degradationSummary, not the
feedback store.

**Filed upstream:** fb-af466c05-2b1 (2026-08-02). Fix requested: cooldown the feedback path,
and stop treating a persistent accepted divergence as a fresh event per read. Until that ships,
the flood continues — re-check the duplicate ratio before filing anything new.
