---
name: known-memory-md-regenerated-daily
description: .instar/MEMORY.md is rewritten wholesale every morning by memory-export — appending to it is not durable
metadata: 
  node_type: memory
  type: project
  originSessionId: ca024778-c5c6-4596-b996-66e3318c4147
  modified: 2026-08-02T19:05:50.756Z
---

`.instar/MEMORY.md` is **auto-generated**, not hand-maintained. The `memory-export`
job (cron `5 6 * * *`, ~06:05 local) rewrites it wholesale from SemanticMemory —
the file mtime matches the job run exactly, and it ends with an
`*Auto-generated from SemanticMemory (N entities)…*` footer.

Anything appended by hand is destroyed within 24 hours. This includes the
`reflection-trigger` job's own instruction, which literally says "append to
.instar/MEMORY.md" — that instruction is stale and produces work that
silently evaporates.

**Why:** same class as [[feedback_verify_durability_not_just_landing]] and
[[feedback_repair_belongs_in_the_reverting_event]] — a write that lands once is
not a write that persists; put the record where the *regenerating* process will
carry it forward.

**How to apply:** to persist a learning, `POST /evolution/learnings` (feeds
SemanticMemory, so it survives regeneration) and/or write a file here in the
Claude Code auto-memory. Never trust a raw append to `.instar/MEMORY.md`.
Verified 2026-08-02 (LRN-009).
