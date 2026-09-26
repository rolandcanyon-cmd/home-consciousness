---
name: unjustified_stop_gate_failing
description: "UnjustifiedStopGate 100% error rate (07-31) has CLEARED — 4% over 24h as of 2026-08-02. Residual: p95 latency ~28-30s on haiku."
metadata:
  node_type: memory
  type: project
  originSessionId: 34358655-dfb2-47d6-b5f2-55e8c89a370d
  modified: 2026-08-02T14:37:30.268Z
---

**CLEARED — re-verified live 2026-08-02 07:40 PDT.** On 2026-07-31 this gate
showed a 100% error rate (169/169 calls). It has since recovered on its own; no
fix was applied by anyone here.

Live `GET /metrics/features?feature=UnjustifiedStopGate`:

| window | calls | errors | rate |
|---|---|---|---|
| 24h | 171 | 7 | 4% |
| 6h | 42 | 2 | 5% |
| 1h | 6 | 1 | 17% (small sample) |

So the alarming figure is **historical, not current**. Do not re-open this as a
100%-failure incident without re-reading the metrics first.

**Residual worth knowing:** p95 latency is **~28–30s**, running on `haiku`. That
is slow for a gate on the outbound path — the gate FAILS CLOSED (holds the
message and queues it for retry rather than silently delivering), so latency
here shows up as delayed sends, not lost ones. A ~4% error baseline means a
small share of sends take the hold-and-retry path.

**Why the original note misled:** it recorded a raw counter (`169 errors / 169
calls`) with no window and no follow-up check, so a transient outage read as a
permanent 100% failure for two days. A rate needs a time window attached, and a
"what we DON'T know" list needs a scheduled re-check or it just ages.
See [[feedback_apply_fix_dont_just_note_it]].
