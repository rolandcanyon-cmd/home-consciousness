---
name: known-attention-queue-dead-no-telegram
description: "POST /attention 503s on this agent because it hard-requires Telegram — every built-in guard's escalation path is a silent no-op; feedback fb-bbe74c6b-96c filed 2026-08-02"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7e3d897b-e041-48b9-9e2e-85b980735b56
  modified: 2026-08-03T03:09:42.750Z
---

`POST /attention` always returns `503 {"error":"Telegram not configured"}` here.
`routes.ts:15890` gates the handler on `ctx.telegram` as its **first** statement — before body
validation, before storage. This agent's adapters are `whatsapp` (session expired/logged-out)
and `imessage`; there is no Telegram and there isn't meant to be.

`GET /attention` reads **0 items**. That is not "nothing needed attention" — it is "nothing can
be written." Do not read an empty attention queue on this agent as a health signal.

**Why this is the important one.** CLAUDE.md points at the attention queue as *the* proactive
escalation path, and a long list of built-in guards escalate only through it: guard-posture
tripwire, sentinel escalations, resume-queue give-ups, burn detection, duplicate reconciler,
scope-accretion holds, machine-coherence, load-bearing-gap alerts. On this agent every one is a
silent no-op. The agent detects correctly and surfaces nothing.

This is the **cause of the invisibility** behind the two failures found on 2026-08-02 —
[[known-tunnel-exhausted-no-remote-access]] (dead for 8 boots) and
[[known-degradation-feedback-flood]] (29h, ~814/day). Both are precisely what the queue exists
to raise; neither could be raised. Treat those two as symptoms of this.

**Working surfaces on this agent are therefore: iMessage only.** No attention queue, no
dashboard/tunnel link, WhatsApp logged out. When something genuinely needs Adrian, iMessage is
the only channel that reaches him — plan on that rather than queueing and assuming it landed.

**Filed upstream:** fb-bbe74c6b-96c (2026-08-02), asking that recording be decoupled from
delivery so the item persists even when no adapter can render it.
