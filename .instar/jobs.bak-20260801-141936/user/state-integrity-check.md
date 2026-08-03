---
name: State Integrity Check
description: Cross-validate state file consistency, detect orphaned references and bloat.
schedule: 0 */6 * * *
priority: medium
expectedDurationMinutes: 1
model: haiku
enabled: true
tags:
  - cat:guardian
  - exec:prompt
gate: curl -sf http://localhost:4040/health >/dev/null 2>&1
toolAllowlist:
  - Read
---
Verify state file integrity: 1) Parse all JSON files in .instar/state/ and .instar/ - report any that fail to parse, 2) Check .instar/config.json for required fields (port, authToken, projectName), 3) Check .instar/jobs.json structure validity, 4) Look for orphaned session references in state files, 5) Check file sizes - flag any state files >1MB as potential bloat. If all files are healthy and parseable, exit silently. Only report actual integrity issues.
