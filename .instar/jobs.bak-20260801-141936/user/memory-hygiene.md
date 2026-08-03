---
name: Memory Hygiene
description: Review MEMORY.md for stale entries, duplicates, and quality issues. Propose cleanup.
schedule: 0 7 * * *
priority: high
expectedDurationMinutes: 5
model: haiku
enabled: true
tags:
  - cat:maintenance
  - role:worker
  - exec:prompt
gate: test -f .instar/MEMORY.md && wc -w < .instar/MEMORY.md | python3 -c "import sys; exit(0 if int(sys.stdin.read().strip()) > 100 else 1)" 2>/dev/null
toolAllowlist:
  - Read
---
Step 1: Sync the memory index before analysis (AUTH=$(python3 -c "import json; print(json.load(open('.instar/config.json')).get('authToken',''))" 2>/dev/null); curl -s -X POST -H "Authorization: Bearer $AUTH" http://localhost:4040/memory/sync >/dev/null 2>&1). Step 2: Read .instar/MEMORY.md and review for: 1) Duplicate or redundant entries (same learning stated multiple ways), 2) Stale information (outdated facts, deprecated workflows), 3) Low-value noise (trivial observations that don't warrant long-term memory), 4) Missing structure (unclear categories, hard to navigate). If you find significant issues (>10% of content should be removed/refactored), create an evolution proposal for cleanup. ALWAYS write a handoff note at the end: WORDS=$(wc -w < .instar/MEMORY.md | tr -d " "); echo "Last hygiene: $(date). Words: $WORDS." > .instar/state/job-handoff-memory-hygiene.md. IMPORTANT: If MEMORY.md exceeds 5000 words, this is a critical finding regardless of organization quality — identify the lowest-value 20% and create an evolution proposal for removal.
