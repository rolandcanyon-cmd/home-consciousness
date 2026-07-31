---
name: state-integrity-check
description: Cross-validate state file consistency, detect orphaned references and bloat
metadata:
  user_invocable: "false"
---

# State Integrity Check — Cross-Validation of Agent State

## Purpose

Cross-validate agent state files for logical consistency. Detect orphaned references, bloated files, config-reality mismatches, and stale handoff notes. Fix what can be fixed automatically.

## Procedure

Read the auth token:

\`\`\`
AUTH=$(python3 -c "import json; print(json.load(open('.instar/config.json')).get('authToken',''))" 2>/dev/null)
\`\`\`

### 1. Active Job Orphan

If \`.instar/state/active-job.json\` exists, verify the session it references is actually running:

\`\`\`
curl -s -H "Authorization: Bearer $AUTH" http://localhost:${INSTAR_PORT:-4040}/sessions
\`\`\`

Check if the session name matches. If the session is dead but active-job.json persists, it's orphaned — delete it.

### 2. Job-Topic Orphan

Read \`.instar/state/job-topic-mappings.json\`. For each mapping, verify the topic ID is reachable:

\`\`\`
curl -s -H "Authorization: Bearer $AUTH" http://localhost:${INSTAR_PORT:-4040}/telegram/topics
\`\`\`

If topics have been deleted, the mapping is stale — flag it.

### 3. State File Bloat

Check sizes of all state files. Any file over 1MB is a bloat signal. Common culprits:
- \`degradation-events.json\` growing unbounded
- Activity logs accumulating

Report bloated files and prune where safe.

### 4. Config-Reality Match

Read \`.instar/config.json\`. If Telegram is configured, verify the bot is connected:

\`\`\`
curl -s -H "Authorization: Bearer $AUTH" http://localhost:${INSTAR_PORT:-4040}/health
\`\`\`

Check if the telegram field shows connected. If config says telegram but health says disconnected, report the discrepancy.

Then check the guard posture for config-vs-runtime divergence — a config edit that never reached the runtime:

\`\`\`
curl -s -H "Authorization: Bearer $AUTH" http://localhost:${INSTAR_PORT:-4040}/guards
\`\`\`

Two classes matter, and BOTH mean "the config claims a guard is on, the runtime says otherwise":

- \`effective: off-runtime-divergent\` — config says enabled, the runtime is not doing the work. The usual cause is a dry-run-first guard where \`enabled: true\` was set without \`dryRun: false\`. Read the feature's own status route; a disabled string starting with \`dryRun\` confirms it.
- \`effective: diverged-pending-restart\` — the config differs from what the running process loaded.

For each such row, report the guard key, how long it has been divergent if known, and whether a restart or a \`dryRun: false\` is the missing step. Never conclude a guard is working because the config says so — the runtime snapshot is authoritative.

### 4b. Staged-But-Unloaded Config

Config is read at server start; there is no hot reload. If \`.instar/config.json\` was modified AFTER the server started, any edit in it is staged but NOT in effect:

\`\`\`
stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" .instar/config.json
ps -eo lstart,command | grep "instar-boot.cjs server" | grep -v grep
\`\`\`

If the config mtime is later than the server start time, say so plainly and name what is waiting on the restart. This is the check that turns "verify after next restart" from an intention into an observation.

### 4c. Reverted Job-Priority Overrides

Built-in job files under `.instar/jobs/schedule/` are regenerated wholesale from shipped
templates on update, build/deploy, and some server starts. Only `enabled` is preserved —
**`priority` is NOT**, so a low→medium override silently reverts and the job goes back to being
shed. This has recurred twice (07-28, 07-30).

```
AUTH=$(python3 -c "import json; print(json.load(open('.instar/config.json')).get('authToken',''))")
curl -s -H "Authorization: Bearer $AUTH" http://localhost:4040/jobs \
  | jq -r '(.jobs // .)[] | select(.enabled and .priority=="low") | .slug'
```

Any *enabled* job reporting `priority: "low"` is at risk: while the quota source is
`claude-jsonl` (degraded), low-priority jobs are refused unconditionally regardless of usage.
Cross-check with `jq -r '.[] | select(.metadata.gateReason=="quota") | .metadata.slug' .instar/logs/activity-$(date +%F).jsonl | sort | uniq -c`.

**An enabled+low hit is not automatically a defect.** Separate the two cases before remediating:

- **Low *and* being shed** → a real regression. Re-apply `"priority": "medium"` to
  `.instar/jobs/schedule/<slug>.json`, restart, confirm via `GET /jobs`.
- **Low but running on schedule** (`state.lastRun` current for its cron, no `gateReason=="quota"`
  entries) → at-risk, not broken. Record it; do not remediate. As of 07-31 `feedback-retry` and
  `instar-state-snapshot` are permanently in this bucket — flagging them every run is a false
  positive.

Note that a low-priority job may have **no schedule file at all** — the `low` then comes from the
shipped built-in definition, not from a reverted override. Confirm with
`ls .instar/jobs/schedule/<slug>.json` before concluding a regeneration reverted anything. If such
a job does need pinning, the override file must be **created**, and it will then carry its own
distinct mtime like any other override.

**Always run the regeneration-fingerprint check — not only when a job is being shed.** The
revert is caused by an EVENT (a wholesale rewrite), so a quiet window proves nothing: the
previous application of this fix survived 28 hours before a regeneration reverted it. Check the
event directly:

```
ls -lT .instar/jobs/schedule/*.json | awk '{print $6,$7,$8,$9}' | sort | uniq -c | sort -rn
```

Overridden files should sit on a LATER, distinct mtime than the bulk regeneration group. If they
have collapsed into the shared group mtime, a rewrite ran and every `priority` override needs
re-applying now — before any skip appears in the logs.

**Reporting rule:** state the behavioral result and the durability question SEPARATELY. "No
quota sheds in N hours" closes the behavior half only; durability is closed by the mtime
evidence above, never by elapsed time. Reporting a quiet window as if the regression were
resolved is a false all-clear.

### 5. Handoff Note Staleness

Check \`.instar/state/job-handoff-*.md\` files. If any are older than 7 days and reference state that may have changed, flag them as potentially stale.

## On Issues Found

- Submit feedback for each issue found
- Fix what you can automatically (delete orphaned active-job.json, prune bloated files)
- Exit silently if everything checks out — no output means no problems
