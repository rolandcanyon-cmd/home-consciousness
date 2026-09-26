---
name: Use reference implementations
description: When building new adapters/features for Instar, copy working patterns from Telegram/Slack/OpenClaw — don't invent custom approaches
type: feedback
---

When building new adapters or features in Instar, always copy patterns from the reference implementations (Telegram, Slack, OpenClaw) instead of inventing custom approaches.

**Why:** The iMessage adapter used a custom session lifecycle (spawn empty, manual wait loop, separate injection) instead of copying Telegram's proven pattern (pass bootstrap as initialMessage to spawnInteractiveSession, which handles everything). This caused sessions to fail because the custom code didn't handle the lifecycle correctly.

**How to apply:** Before writing any session management, message routing, or adapter code:
1. Read how Telegram does it in `server.ts` (spawnSessionForTopic, respawnSessionForTopic, injectTelegramMessage)
2. Read how Slack does it (SlackAdapter, ring buffers, channel registry)
3. Check OpenClaw source for additional patterns
4. Use the exact same code paths — same functions, same parameters, same flow
5. The only differences should be platform-specific (tags, reply scripts, message format)
