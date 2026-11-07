---
name: ambient-pool-float-sensor-fix
description: "Ambient Weather pool floating sensor losing connection to base station — fix requires a battery-pull power cycle of the float itself, not just the channel reset; confirmed 2026-10-25"
metadata:
  node_type: memory
  type: project
  type_detail: known-fix
  originSessionId: 634f093e-5e2b-4722-906f-c13c216a944b
  modified: 2026-10-25T18:42:17.152Z
---

The pool floating water-temp sensor (gateways via the AWN base station/console
in the Dining Room, see [[ambient-indoor-temp-power-cycle-fix]]) stopped
connecting after its channel button got bumped to the wrong setting while it
was being dried out. Adrian set the channel back to 2 and power-cycled it, but
it still wouldn't connect.

**Confirmed fix (2026-10-25):** channel reset alone was not enough — the float
sensor needed a full **battery-pull power cycle** (physically remove the
batteries, not just toggle power) in addition to the correct channel setting.
That combination fixed it.

**How to apply:** if the pool float sensor drops off again (or any AWN remote
sensor — float, outdoor temp) and a simple power cycle / channel check doesn't
restore the connection, the next step is a battery-pull reset on the sensor
itself before escalating to "needs physical replacement."
