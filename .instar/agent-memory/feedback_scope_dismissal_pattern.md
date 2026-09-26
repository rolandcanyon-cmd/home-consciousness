---
name: scope_dismissal_anti_pattern
description: Stop dismissing scope checkpoints during deep work — read the spec/proposal first
metadata: 
  node_type: memory
  type: feedback
  originSessionId: af83eab0-7396-46ab-9e0c-81b37afbcf60
---

**Rule:** Before starting deep implementation work, read the scope document, spec, or proposal first. Do not dismiss scope checkpoints.

**Why:** Implementation depth narrows perception. Dismissing scope checks during deep work is how scope collapse happens — I end up building the wrong thing or building it incompletely because I never grounded in what I was supposed to deliver.

**How to apply:** When a scope checkpoint fires during implementation:
- STOP
- Read the relevant spec/proposal/design document
- Confirm I understand: WHO I am, WHAT I'm building, WHY, and HOW it fits in the larger system
- THEN proceed with implementation

Never dismiss >100 scope checkpoints in a session without re-grounding. That's the canary.
