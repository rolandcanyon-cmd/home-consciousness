---
name: Room walk progress (as of 2026-04-14)
description: Five rooms fully walked in FunkyGibbon (Kitchen, Studio, Bar BQ, Living Room, Dining Room); other rooms are partial or empty
type: project
originSessionId: fc2a6623-0c20-49f5-8339-e61be5a29b52
---
As of 2026-04-14, five rooms have completed room walks in FunkyGibbon:

- Kitchen: 155 devices (Vantage loads for Kitchen area), plus room-edit adding Zone 2 volume control
- Studio: 38 devices, 3 doors
- Bar BQ: 12 devices (Samsung Frame TV, Wolf BBQ, extractor fan, pool remote, etc.), 1 door
- Living Room: 18 devices (4 Flair vents, Flair Puck, 2 Zone 2 volume controls, fireplace, chandelier, etc.), 3 doors
- Dining Room: 8 devices (2 Lutron drapes, 3 standard vents, wall speaker), 2 doors

Living Room + Dining Room together form the "Great Room" — both rooms now have an explicit "Great Room" alias in FunkyGibbon as of 2026-07-15.

Remaining rooms are either empty or have sparse entries from ad-hoc updates. Empty rooms aren't a data-integrity bug — they're rooms that haven't been walked yet.

**2026-07-15 update:** the AWN weather console ("Ambient Weather Base Station Display", entity `7507092c-5378-49a6-85f1-e5097b6fa56a`) was corrected from Living Room to Dining Room (mounted on the window near the pool, for the floating pool sensor) — same physical unit, not a new device. See [[known_funkygibbon_sync_push_broken]] and [[known_funkygibbon_relationship_version_pinning]] for real bugs found/fixed in the room-edit tooling during that correction.

**How to apply:** When evaluating FunkyGibbon contents, don't flag empty or sparse rooms as anomalies. Gaps fill in via `/room-walk`. Only the five walked rooms above reflect actual cataloguing — treat other room numbers as placeholders.
