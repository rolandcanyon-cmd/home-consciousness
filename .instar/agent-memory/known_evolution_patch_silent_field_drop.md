---
name: known-evolution-patch-silent-field-drop
description: PATCH /evolution/proposals/:id accepts only status+resolution; any other field is silently dropped while still returning ok:true
metadata: 
  node_type: memory
  type: reference
  originSessionId: 88da3f47-c5b5-4872-9461-94c3fd3810a0
  modified: 2026-07-29T03:31:42.253Z
---

`PATCH /evolution/proposals/:id` destructures **only** `{ status, resolution }` (instar `src/server/routes.ts:21524`). `EvolutionProposal` (`src/core/types.ts:1417`) has **no** `rejectionReason` field.

A reason sent as `rejectionReason` / `reviewNotes` / `reason` is **silently discarded** — the request still returns `{ok:true}`, so nothing signals the loss. This is why 40 of 44 rejected proposals here had no reason, which in turn let the generator re-propose the same idea indefinitely.

**Always use `resolution`.** After patching, read the proposal back and confirm the reason persisted.

Fixed 2026-07-29 (EVO-048) by forking `evolution-proposal-evaluate` from the update-overwritten `.instar/jobs/instar/` namespace into `.instar/jobs/user/` — the durable fork is flipping `origin` from `instar` to `user` in `.instar/jobs/schedule/<slug>.json`. Filed upstream as fb-89f2c826-319.

Related: [[known_job_config_edits_need_restart]] — job definitions load at server start only.
