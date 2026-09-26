---
name: No hot patching
description: Always build and install changes cleanly via npm — never copy individual dist files into shadow-install
type: feedback
---

ALWAYS build and install changes. No hot patching.

**Why:** Copying individual .js files into the shadow-install is fragile — misses dependencies between files (AgentServer, routes, types), can leave stale modules, and doesn't update node_modules resolution. Hot patching caused the iMessage reply endpoint to return "not configured" because AgentServer.js wasn't updated.

**How to apply:** When deploying changes from instar-dev to the running agent:
1. `cd /Users/rolandcanyon/instar-dev && npm run build`
2. `cd /Users/rolandcanyon/.instar/agents/Roland/.instar/shadow-install && npm install /Users/rolandcanyon/instar-dev`
3. Re-install any optional deps that get removed: `npm install better-sqlite3`
4. Restart the server
