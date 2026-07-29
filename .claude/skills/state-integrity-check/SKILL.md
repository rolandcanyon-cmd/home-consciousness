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

### 5. Handoff Note Staleness

Check \`.instar/state/job-handoff-*.md\` files. If any are older than 7 days and reference state that may have changed, flag them as potentially stale.

## On Issues Found

- Submit feedback for each issue found
- Fix what you can automatically (delete orphaned active-job.json, prune bloated files)
- Exit silently if everything checks out — no output means no problems
