---
name: Degradation Digest
description: Read DegradationReporter events, group repeated patterns, and escalate trends that need attention.
schedule: 0 */4 * * *
priority: medium
expectedDurationMinutes: 1
model: haiku
enabled: true
tags:
  - cat:guardian
  - exec:prompt
gate: test -f /Users/rolandcanyon/.instar/agents/Roland/.instar/degradations.json && python3 -c "import json; events=json.load(open('/Users/rolandcanyon/.instar/agents/Roland/.instar/degradations.json')); exit(0 if len(events) > 0 else 1)" 2>/dev/null
toolAllowlist:
  - Read
---
Read degradation events from .instar/degradations.json. Group by scope/operation and identify: 1) Repeating patterns (same error 5+ times), 2) High-impact failures (message injection, git sync, migrations), 3) Recent spikes (20+ events in 1 hour). For each significant pattern, report in plain language what's failing and why it matters. If there are critical message injection failures (user messages being dropped), flag with [ATTENTION]. If everything is noise or already resolved, say so briefly.
