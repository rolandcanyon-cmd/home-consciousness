---
name: Alexa smart plug routines
description: Alexa controls some smart plugs via routines in the house; these are devices to catalog during room walks
type: project
originSessionId: 722492ad-cb7d-40b3-b751-d382976d80b1
---
The user has Alexa routines that control smart plugs. These smart plugs are real devices that need to be catalogued during room walks.

**Why:** User mentioned this when setting up the Alexa integration (2026-04-13). Smart plugs controlled via Alexa routines may not appear in other inventories (HomeKit, Vantage, UniFi) so Alexa is the authoritative source for them.

**How to apply:** During room walks, when Alexa device list comes back, look specifically for smart plugs and associated routines. Include them as `create_device` diffs with `connectivity: "Amazon smart plug"`.
