---
name: known-hmac-rescan-churn
description: "CapabilityMapper manifest HMAC verification fails ~89/hr — known benign-but-wasteful churn, feedback filed"
metadata: 
  node_type: memory
  type: project
  originSessionId: 192f4c05-6843-43e1-a2a6-37c07ced3b5a
---

CapabilityMapper logs `[WARN] Manifest HMAC verification failed — will rescan` at a steady ~89×/hour (every ~40s) in logs/server.log. The rescan never persists a valid signature, so every read re-fails and re-scans. System stays healthy otherwise (quota normal, no attention items). Likely a sign/verify mismatch — manifest rescanned but not re-signed, or re-signed with a non-matching key/serialization.

Filed as instar feedback `fb-e939c536-f41` (bug) on 2026-06-22. Do NOT re-diagnose from scratch or re-file — if it's still occurring after an instar update, check whether the fix landed before submitting again. Not user-facing; don't alert the user about it.
