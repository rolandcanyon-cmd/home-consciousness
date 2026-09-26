---
name: Claude Code auth — annual API key preferred over /login
description: Annual Anthropic API key is the preferred fix for Claude Code auth expiry, not /login
type: feedback
originSessionId: cfd421d3-33a1-4a67-bbbb-f2e43368115e
---
The "⚠️ Roland auth expired" alert comes from tmux-keepalive.sh (cron, every 10 min). It runs `claude` bare without the API key that SessionManager injects into real sessions. This means it triggers false positives — production sessions work but the canary doesn't.

**Why:** The canary doesn't inject CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY from config. Real sessions get these from config.sessions.anthropicApiKey via SessionManager.

**Bug filed:** fb-5f487e66-5d7

**How to apply:** If the alert fires again, check whether actual sessions are processing messages before panicking. The alert is often a false positive from the broken canary, not a real outage.
