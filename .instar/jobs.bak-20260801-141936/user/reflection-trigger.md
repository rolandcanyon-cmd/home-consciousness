---
name: Reflection Trigger
description: Review recent work and update MEMORY.md if any learnings exist.
schedule: 0 */4 * * *
priority: medium
expectedDurationMinutes: 5
model: opus
enabled: true
tags:
  - cat:learning
toolAllowlist:
  - Read
---
Review what has happened in the last 4 hours by reading recent activity logs. If there are any learnings, patterns, or insights worth remembering, update .instar/MEMORY.md. If nothing significant happened, do nothing.
