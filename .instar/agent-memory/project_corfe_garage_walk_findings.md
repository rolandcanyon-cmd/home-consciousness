---
name: corfe-garage-walk-findings
description: "Three install-path defects Corfe reported from a garage room-walk (2026-09-22), plus a flagged security concern about apparent chat.db requests attributed to Adrian's account"
metadata: 
  node_type: memory
  type: project
  originSessionId: b600a676-b7e3-4ed8-99c2-b017b05851a1
  modified: 2026-09-22T13:40:45.385Z
---

Corfe (UK peer install, [[project_corfe_uk_install]]) reported three items from a garage room-walk on 2026-09-22, iMessage only (no A2A channel):

1. **Server localhost-only bind** — NOT a bug, deliberate design (`resolveMeshBindHost()` in instar-dev's `MeshUrlAdvertiser.ts`, "Decision 17"): single-machine agents bind `127.0.0.1` on purpose; only multi-machine (mesh-identity) agents auto-bind `0.0.0.0`. Escape hatch already exists: set an explicit non-loopback `host` in `config.json` to force LAN/0.0.0.0 bind behind the existing auth.
2. **`unifi_probe.py` PROJECT_DIR off-by-one** — real bug, confirmed and reproduced here too (script at `.claude/scripts/unifi_probe.py`, fallback only walked up 2 `dirname()` levels instead of 3, landing at `.claude/` instead of repo root). Fixed in commit 9b1d128 (2026-09-22).
3. **homekit-dump.py FDA workaround (osascript via Terminal.app)** — tried here, FAILED: "AppleEvent timed out (-1712)" — this session's shell has no Automation permission to control Terminal.app at all. Doesn't fix [[known_homekit_fda_broken]]; that still needs physical/screen-share access.

**Security flag — RESOLVED 2026-09-22 06:40 PDT.** Corfe reported its iMessage bootstrap transcript contained messages attributed to "rolandcanyon@icloud.com" (timestamped 16:19–17:05, unclear timezone) asking for chat.db previews, sender phone numbers, and message-content SQL dumps. Adrian confirmed directly via iMessage: "It's probably a message I entered by mistake" — i.e. he sent it himself, no account impersonation. Consistent with the earlier hypothesis (he was actively iMessaging Roland about the same FDA issue at the time and likely misdirected a message toward Corfe's side). No further action needed; not a security incident.
