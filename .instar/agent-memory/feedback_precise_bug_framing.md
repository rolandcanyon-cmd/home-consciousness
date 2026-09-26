---
name: precise-bug-framing-not-whole-system
description: "When diagnosing a bug in a multi-part system (e.g. local-cache-then-sync), name the specific broken mechanism, not the whole architecture"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f8495a47-4279-48d2-a1ae-310a26d2ff27
---

Adrian corrected me 2026-07-15 after I described FunkyGibbon's local-cache-first-then-sync client as "broken." The local-cache-first design is intentional, correct offline-first architecture — the actual defect was narrower and specific: the sync **push** (local → server) doesn't work, while pull and local writes are fine. Calling the whole client "broken" overstated the finding and mischaracterized a deliberate design choice as a mistake.

**Why:** sweeping architectural claims are more likely to be wrong than a narrow, mechanism-specific claim, and they read as a judgment on a design decision rather than a bug report. He wants the framing to distinguish "this specific piece doesn't work" from "this whole approach is wrong."

**How to apply:** when reporting a bug in a system with multiple cooperating pieces (cache + sync + server, client + protocol + backend, etc.), identify and name the *specific* mechanism that fails (e.g. "push half of sync") rather than the umbrella term for the whole subsystem (e.g. "the local cache"). If a workaround bypasses more than the broken piece (e.g. bypassing the cache entirely to work around a broken sync-push), say so explicitly and note what capability is being traded away, rather than presenting the workaround as a full fix.
