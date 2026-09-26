---
name: known-tunnel-exhausted-no-remote-access
description: "Tunnel is INTERMITTENT, not permanently dead — instar's ~12s reachability window loses a race with trycloudflare quick-tunnel cold start, so links are unavailable in stretches but sometimes work; ALWAYS read GET /tunnel at the moment of use; fb-955877a3-429"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7e3d897b-e041-48b9-9e2e-85b980735b56
  modified: 2026-08-03T07:04:53.192Z
---

**CORRECTED 2026-08-03 07:0xZ (insight-harvest, live probe): the tunnel is INTERMITTENT, not
permanently exhausted.** This run read `lifecycle.state: active` with a live URL
(`kim-created-prime-compile.trycloudflare.com`). The "handing Adrian a link is impossible"
claim below is therefore **too strong** — it was true at the moment it was written, not always.
**Read `GET /tunnel` at the moment you need a link; never assert either state from this note.**
The race mechanism below still explains why it fails often. (Same lesson as LRN-014: a state
field sampled once is not a standing fact.)

As originally observed 2026-08-02: `GET /tunnel` reported `lifecycle.state: exhausted`, `activeProvider: null`, `url: null`.
Every boot in the available server.log (8 boots, 2026-07-31T14:32Z onward) failed with
`reachability-failed: cloudflare-quick URL did not respond to /health`. Onset is unknown —
the log doesn't reach further back.

**It is not cloudflared and not a Cloudflare rate limit.** cloudflared 2026.7.0 is installed
and works; local /health returns 200. Two hand-started quick tunnels against the same port:
- one was reachable (HTTP 200 in 0.12–0.82s) when first probed ~80s after URL emission
- one polled every 2s was still HTTP 000 at t+98s and never came up

instar declares failure after `REACHABILITY_RETRY_DELAYS_MS = [2000, 4000, 6000]` — 4 probes
across ~12s. That comment was tuned for *named*-tunnel edge propagation; quick tunnels take
far longer. So the manager kills tunnels that would have worked, and the 15-min post-exhausted
retry replays the same race forever. `reachabilityRetryDelaysMs` is a **test-only** constructor
injection, so there is no operator config lever.

**Consequence worth remembering:** with no tunnelUrl, every private view / report link is
localhost-only, and the outbound advisory correctly refuses to send localhost links. So
"here's a link to the report" is currently **impossible** for Adrian, who is on iMessage and
has no other visual surface. If a task depends on handing over a link, that constraint is real
— say so rather than generating a link that can't be sent.

**The durable fix is a named tunnel** (Cloudflare account token): persistent URL, no
propagation race, and it also removes the quick-tunnel "URL changes on every restart" problem.
That needs Adrian's Cloudflare account — worth proposing.

**Filed upstream:** fb-955877a3-429 (2026-08-02). Verify with `GET /tunnel` before repeating
any of this diagnosis — do not re-derive it from scratch.
