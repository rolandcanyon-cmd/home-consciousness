---
name: Telegram forwarding quieter
description: v0.28.76 removes noisy critical logs for backward-compatible Telegram lifeline forwards
type: project
---

**Release**: v0.28.76

**What changed**: The Telegram message forwarding system no longer reports false critical-level degradation events when a lifeline (that hasn't been restarted yet) forwards a message without the Stage-B version field. The forward itself still succeeds; only the noisy error log goes away.

**What you notice**: Fewer spurious critical alerts in the feedback system. The Telegram forwarding still works the same way.

**How it applies**: Automatic on upgrade. No action needed.
