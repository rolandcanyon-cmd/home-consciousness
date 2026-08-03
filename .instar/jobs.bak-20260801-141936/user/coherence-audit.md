---
name: Coherence Audit
description: Verify topic-project bindings are still valid, state files are healthy, and no drift has occurred.
schedule: 0 8 * * 1
priority: medium
expectedDurationMinutes: 2
model: haiku
enabled: true
tags:
  - cat:maintenance
  - role:worker
  - exec:prompt
gate: curl -sf http://localhost:4040/health >/dev/null 2>&1
toolAllowlist:
  - Read
---
AUTH=$(python3 -c "import json; print(json.load(open('.instar/config.json')).get('authToken',''))" 2>/dev/null); curl -s -H "Authorization: Bearer $AUTH" http://localhost:4040/topic-bindings && curl -s -H "Authorization: Bearer $AUTH" http://localhost:4040/project-map?format=compact && echo 'Verify: 1) Do topic bindings match current project structure?, 2) Are there orphaned bindings for deleted projects?, 3) Has the working directory changed unexpectedly? If everything is coherent, exit silently. Flag drift with [ATTENTION].'
