---
name: project-corfe-uk-install
description: Corfe is the other Instar install, at Adrian's UK house; it pilots upgrades before this house
metadata:
  type: project
---

**Corfe is a separate Instar install at Adrian's UK house** (confirmed by Adrian
2026-08-28). It is a peer agent on its own machine — NOT another machine in this
agent's multi-machine pool, and not a Threadline-paired peer.

**Reachability (as of 2026-08-28):** no working agent-to-agent channel from here.
`GET /threadline/health` showed `pairedAgents: 0`, `mutualVerifiedCount: 0`, and the
only known peer fingerprint (`1589f8b6…`) had been stale since 2026-07-15 with 4
undelivered messages. Sharing anything with Corfe currently goes through Adrian, or
through a public repo it can fetch — that is how the `/imessage-doctor` skill was
shared (published to the public `home-consciousness` repo).

**Corfe pilots upgrades.** As of **2026-09-13** it is mid-upgrade on the-goodies stack;
this house upgrades afterwards using what Corfe learns. See
[[project-goodies-upgrade-and-repo-move]].

**How to apply:** when Adrian references Corfe, it is the UK house agent, not a local
machine — do not look for it in `GET /agents` or the session pool. If something needs to
reach it, expect to hand Adrian a link rather than sending directly.
