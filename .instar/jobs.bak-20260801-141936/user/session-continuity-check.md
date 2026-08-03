---
name: Session Continuity Check
description: "Verify that sessions produce lasting artifacts: handoff notes, memory updates, learnings."
schedule: 0 */4 * * *
priority: medium
expectedDurationMinutes: 2
model: haiku
enabled: true
tags:
  - cat:guardian
  - exec:prompt
gate: curl -sf http://localhost:4040/health >/dev/null 2>&1
toolAllowlist:
  - Read
---
Check recent session productivity: 1) List all handoff files modified in last 4 hours (find .instar/state -name 'job-handoff-*.md' -mtime -4h), 2) Check MEMORY.md last modified time - has it been updated in last 24h?, 3) Check evolution learnings created recently (curl http://localhost:4040/evolution/learnings?limit=10), 4) Look for sessions that ran but left no artifacts (ephemeral work with no learning). If sessions are running but producing no lasting value, flag with [ATTENTION]. If continuity looks good, exit silently.
