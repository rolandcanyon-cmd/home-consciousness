---
name: iMessage immediate acknowledgment
description: User wants immediate response to every incoming iMessage before processing - acknowledge receipt and restate the request
type: feedback
---

Always acknowledge iMessage messages immediately before processing. First output should repeat/restate the user's request, then work on the actual response.

**Why:** The user's primary frustration with iMessage is silence — they send a message and get nothing back for 30-90 seconds. The point of iMessage integration is responsiveness, not just eventual correctness.

**How to apply:** In every iMessage session, the FIRST action after receiving a message must be to send a brief ack via imessage-reply.sh that mirrors the request ("Checking on that now...", "On it — looking at the weather..."). Then process and send the full answer as a second message. This applies to both new sessions and follow-up messages in existing sessions.
