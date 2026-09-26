---
name: Anthropic API key location and canary test fix
description: ANTHROPIC_API_KEY is stored in config.sessions.anthropicApiKey; canary test in imessage-fork-maintenance must read it from config, not blank it
type: project
originSessionId: 137104d3-b846-4775-96e2-5ec293ed413f
---
The Anthropic API key used by Claude sessions is stored at `.instar/config.json` → `sessions.anthropicApiKey` (length 108 chars). SessionManager reads it from there and injects it into spawned sessions.

**Why:** The iMessage fork maintenance canary test was blanking `ANTHROPIC_API_KEY=""` in the tmux environment before running the `claude` binary, causing "Not logged in" failures. Actual production sessions work fine because SessionManager always injects the key.

**How to apply:** When running the `claude` binary outside of SessionManager (e.g., canary tests, shell scripts), always read the key first:
```bash
CANARY_KEY=$(python3 -c "import json; print(json.load(open('/Users/rolandcanyon/.instar/agents/Roland/.instar/config.json'))['sessions']['anthropicApiKey'])")
```
Then pass `-e "ANTHROPIC_API_KEY=$CANARY_KEY"` to the tmux session. Fixed in `.claude/skills/imessage-fork-maintenance/SKILL.md` step 8.
