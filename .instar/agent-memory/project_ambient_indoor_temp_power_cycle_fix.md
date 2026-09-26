---
name: ambient-indoor-temp-power-cycle-fix
description: AWN console indoor temp (tempinf) dropout — power-cycling the console fixes it; confirmed 2026-07-15
metadata:
  node_type: memory
  type: project
  originSessionId: f8495a47-4279-48d2-a1ae-310a26d2ff27
  modified: 2026-08-02T14:35:31.593Z
---

The Ambient Weather console ("Roland Canyon", mac `24:7D:4D:A3:6E:25`) sits in
the **Dining Room on the window near the pool** — mounted there so it can pick
up the floating pool sensor.

**Known remedy:** if `tempinf` (indoor temp) drops out while `humidityin` and
the outdoor/pool paths keep working — visible via
`node .claude/scripts/ambient-weather.mjs`, or the morning-weather report saying
"temp reading unavailable this cycle" — the first suggestion to Adrian is
**"try power-cycling the AWN console."** This is a confirmed low-effort fix, not
an open-ended "needs a physical check": a 3-day dropout in July 2026 cleared
immediately on a power cycle (78°F back on the next REST read). It reads as a
transient fault in the console's indoor sensor logic, not a code or vault bug.
Only escalate to a physical inspection if a power cycle doesn't resolve it.
