---
name: agent-passport
description: View this agent's digital passport (identity + trust + allowed/forbidden actions) and verify a peer's passport against a proposed action (EXO 3.0).
metadata:
  user_invocable: "true"
---

# /agent-passport

Salim Ismail's EXO 3.0 "digital passport": every AI agent carries metadata saying what it's allowed and forbidden to do, and other agents watch compliance. Packages Instar's identity (name + routing fingerprint), trust level, and ORG-INTENT constraints into one portable passport + a peer-run compliance check.

## How
Your own passport:
```bash
curl -H "Authorization: Bearer $AUTH" http://localhost:${INSTAR_PORT:-4040}/passport
```
→ `{ version, agent, fingerprint, trustLevel, allowedCapabilities, forbiddenActions, issuedAt }` (forbiddenActions = your ORG-INTENT constraints).

Verify an action against a passport (peer-watches-compliance):
```bash
curl -X POST -H "Authorization: Bearer $AUTH" -H 'Content-Type: application/json' \
  -d '{"passport":{...},"action":"wire funds to a new vendor"}' \
  http://localhost:${INSTAR_PORT:-4040}/passport/verify
```
→ `{ permitted, basis, reason, matched? }` where basis = `forbidden-action` | `trust-floor` (untrusted may observe, not act) | `out-of-scope` | `ok`. Deterministic + advisory. Pairs with `/intent/org/test-action`.
