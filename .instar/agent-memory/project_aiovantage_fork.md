---
name: aiovantage fork is intentional
description: rolandcanyon-cmd/aiovantage fork and /Users/rolandcanyon/aiovantage-dev clone are required — do not delete
type: project
originSessionId: fc2a6623-0c20-49f5-8339-e61be5a29b52
---
Adrian maintains a fork of aiovantage at `rolandcanyon-cmd/aiovantage` with a local clone at `/Users/rolandcanyon/aiovantage-dev`.

**Why:** The Vantage controller runs an older firmware version that required patches to the upstream aiovantage library. The fork carries those patches.

**How to apply:** Do not propose deleting the fork or the local clone. If considering "cleanup" passes, treat aiovantage-dev as intentional infrastructure, not cruft.
