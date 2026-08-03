---
name: Evolution Proposal Evaluate
description: "Phase A: Read pending evolution proposals, evaluate their merit, accept or reject. Paired with evolution-proposal-implement."
schedule: 0 */6 * * *
priority: medium
expectedDurationMinutes: 3
model: sonnet
enabled: true
tags:
  - cat:learning
  - role:worker
  - exec:prompt
  - pair:evolution-proposal-implement
gate: "curl -sf -H \"Authorization: Bearer $INSTAR_AUTH_TOKEN\" -H \"X-Instar-AgentId: $INSTAR_AGENT_ID\" http://localhost:${INSTAR_PORT:-4040}/evolution/proposals?status=proposed 2>/dev/null | python3 -c \"import sys,json; d=json.load(sys.stdin); exit(0 if len(d.get('proposals',[])) > 0 else 1)\""
toolAllowlist: "*"
unrestrictedTools: true
mcpAccess: none
---
AUTH="${INSTAR_AUTH_TOKEN:-$(python3 -c "import json; v=json.load(open('.instar/config.json')).get('authToken',''); print(v if isinstance(v, str) else '')" 2>/dev/null)}"
AGENT_ID="${INSTAR_AGENT_ID:-$(python3 -c "import json; print(json.load(open('.instar/config.json')).get('projectName',''))" 2>/dev/null)}"
PORT="${INSTAR_PORT:-4040}"

Review pending evolution proposals: curl -s -H "Authorization: Bearer $AUTH" -H "X-Instar-AgentId: $AGENT_ID" "http://localhost:$PORT/evolution/proposals?status=proposed"

FIRST, load the full history once — you must not re-litigate settled ideas, and you must not reject the same idea twice without saying why:
curl -s -H "Authorization: Bearer $AUTH" -H "X-Instar-AgentId: $AGENT_ID" "http://localhost:$PORT/evolution/proposals"

For each pending proposal:
1. Read the title, description, type, and source.
2. DUPLICATE CHECK: does an existing proposal (ANY status, including rejected) already cover the same intent against the same target? If yes and the older one was rejected, reject this one as a duplicate and cite the prior EVO id in the reason. Only the most recent of a duplicate set should ever survive.
3. REALITY CHECK: verify the described problem still exists before accepting. A proposal describing a problem that is already solved is a reject, not an approve. If the source is 'insight-harvest' or 'memory-hygiene' and current state no longer matches the description, reject it and say what you actually observed.
4. Evaluate what survives: Is this a genuine improvement? Is the effort worth the impact? Does it align with our goals?
5. If approved: curl -s -X PATCH -H "Authorization: Bearer $AUTH" -H "X-Instar-AgentId: $AGENT_ID" http://localhost:$PORT/evolution/proposals/EVO-XXX -H 'Content-Type: application/json' -d '{"status":"approved","resolution":"Why this is worth doing."}'
6. If rejected or deferred, a REASON IS MANDATORY and it MUST go in the "resolution" field:
   curl -s -X PATCH -H "Authorization: Bearer $AUTH" -H "X-Instar-AgentId: $AGENT_ID" http://localhost:$PORT/evolution/proposals/EVO-XXX -H 'Content-Type: application/json' -d '{"status":"rejected","resolution":"Specific reason this was rejected."}'

CRITICAL — field name: the PATCH route accepts ONLY "status" and "resolution". A reason sent as "rejectionReason", "reviewNotes", "reason", or any other key is SILENTLY DISCARDED — the request still returns ok:true and the proposal is left with no recorded reason. This is exactly how the queue accumulated 40+ reasonless rejections. Always use "resolution".

Why this matters: a rejection with no reason cannot close a loop. The generator job has no way to learn the idea was already considered, so it re-proposes it on the next run forever. Your written reason is the thing that stops the treadmill.

After patching, VERIFY the reason actually persisted on at least one proposal you rejected this run:
curl -s -H "Authorization: Bearer $AUTH" -H "X-Instar-AgentId: $AGENT_ID" "http://localhost:$PORT/evolution/proposals" | python3 -c "import sys,json; ps=json.load(sys.stdin)['proposals']; print([(p['id'],p.get('resolution')) for p in ps if p['status']=='rejected'][-3:])"
If the resolution came back empty or null, say so in the handoff note — that is a real bug, not a formatting nit.

Do NOT implement approved proposals — that's handled by the paired evolution-proposal-implement job.

Write a brief [HANDOFF] note: how many proposals reviewed, approved, rejected, how many were suppressed as duplicates, and confirmation that reasons persisted.

If no proposals need attention, exit silently.
