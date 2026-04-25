---
name: imessage-fork-maintenance
description: Daily rebase of iMessage fork against upstream Instar. Rebuild, deploy, verify, rollback on failure.
metadata:
  user_invocable: "true"
---

# iMessage Fork Maintenance

Keep the Instar fork in sync with upstream. The goal is a working install with minimal divergence.

## Layout

- **Source**: `$HOME/instar-dev` (git repo)
  - Remote `origin` = JKHeadley/instar (upstream)
  - Remote `fork` = {{INSTAR_FORK_ORG}}/instar (our fork)
  - Branch `main` — upstream main + our one custom commit on top
- **Deploy target**: `$AGENT_DIR/.instar/shadow-install`
  - Package name: `@{{INSTAR_FORK_ORG}}/instar` (MUST use scoped name)
- **Server**: LaunchAgent `ai.instar.Roland`, port 4040

## Procedure

Run every step. If any step fails, jump to ROLLBACK.

```
cd $HOME/instar-dev
```

### 1. Record rollback point
```bash
ROLLBACK=$(git rev-parse HEAD)
```

### 2. Fetch upstream
```bash
git fetch origin
```

### 3. Check for PR comments and respond
Check all open PRs for new comments. If there are unresponded comments, address them:

```bash
# List open PRs from {{INSTAR_FORK_ORG}}
gh pr list --repo JKHeadley/instar --author {{INSTAR_FORK_ORG}} --state open --json number,title,updatedAt --limit 10
```

For each open PR:
```bash
# Check for new comments (review the comments with --comments flag)
gh pr view <NUMBER> --repo JKHeadley/instar --comments
```

If there are actionable comments from reviewers:
- Read the feedback carefully
- Check out the PR branch if needed
- Make the requested changes
- Run tests to verify fixes
- Commit and push changes
- Reply to comments acknowledging the fixes

Only proceed once all PR comments have been addressed.

### 4. Check if rebase needed
```bash
git log HEAD..origin/main --oneline
```
If empty — skip to step 8 (verify only).

### 5. Rebase
```bash
git rebase origin/main
```
If conflicts: try to resolve (prefer our changes for `src/messaging/imessage/`). If unresolvable: `git rebase --abort` and jump to ROLLBACK.

### 6. Build
```bash
npm run build
```
If fails: jump to ROLLBACK.

### 7. Deploy
```bash
cd $AGENT_DIR/.instar/shadow-install
npm install "@{{INSTAR_FORK_ORG}}/instar@file:../../../../../instar-dev"
npm install better-sqlite3

# Fix node symlink — npm install resets it to /opt/homebrew which lacks Full Disk Access
ln -sf $HOME/homebrew/bin/node $AGENT_DIR/.instar/bin/node

# Fix autoApply — must be false since we manage updates via this rebase job
python3 -c "
import json
c = json.load(open('$AGENT_DIR/.instar/config.json'))
c.setdefault('updates', {})['autoApply'] = False
json.dump(c, open('$AGENT_DIR/.instar/config.json', 'w'), indent=2)
"

# Daemon lives at SYSTEM level (/Library/LaunchDaemons/ai.instar.Roland.plist),
# NOT user gui level. `gui/$(id -u)/` kickstart silently no-ops on system daemons.
# Requires sudo. The job runner must have NOPASSWD configured for this command
# in /etc/sudoers.d/, or this step will hang waiting for a password.
UPTIME_BEFORE=$(curl -s http://localhost:4040/health | python3 -c "import json,sys; print(json.load(sys.stdin).get('uptime',0))")
sudo -n launchctl kickstart -k system/ai.instar.Roland || { echo "❌ daemon restart failed — sudo NOPASSWD missing?"; exit 1; }
sleep 8
UPTIME_AFTER=$(curl -s http://localhost:4040/health | python3 -c "import json,sys; print(json.load(sys.stdin).get('uptime',0))")
if [ "$UPTIME_AFTER" -ge "$UPTIME_BEFORE" ]; then
  echo "❌ daemon did not actually restart (uptime didn't reset)"
  exit 1
fi
echo "✅ daemon restarted (uptime reset from ${UPTIME_BEFORE}ms to ${UPTIME_AFTER}ms)"
```

### 8. Verify
Run ALL of these. Every one must pass.
```bash
# Server is up
curl -s http://localhost:4040/health | grep -q '"status"'

# Fresh code deployed — verify OAuth routing exists in compiled dist
grep -q "CLAUDE_CODE_OAUTH_TOKEN" $AGENT_DIR/.instar/shadow-install/node_modules/@{{INSTAR_FORK_ORG}}/instar/dist/core/SessionManager.js || { echo "❌ shadow-install is stale (missing OAuth routing)"; exit 1; }

# iMessage adapter connected
AUTH=$(python3 -c "import json; print(json.load(open('.instar/config.json')).get('authToken',''))")
curl -s -H "Authorization: Bearer $AUTH" http://localhost:4040/imessage/status | grep -q '"connected"'

# tmux alive
/opt/homebrew/bin/tmux ls

# Claude can spawn a session (read API key from config — same as SessionManager uses)
CANARY_KEY=$(python3 -c "import json; print(json.load(open('$AGENT_DIR/.instar/config.json'))['sessions']['anthropicApiKey'])")
# OAuth tokens (sk-ant-oat...) go in CLAUDE_CODE_OAUTH_TOKEN; API keys (sk-ant-api03...) go in ANTHROPIC_API_KEY
if echo "$CANARY_KEY" | grep -q "^sk-ant-o"; then
  KEY_ENV="CLAUDE_CODE_OAUTH_TOKEN=$CANARY_KEY"
else
  KEY_ENV="ANTHROPIC_API_KEY=$CANARY_KEY"
fi
/opt/homebrew/bin/tmux new-session -d -s verify-canary -e "CLAUDECODE=" -e "$KEY_ENV" \
  "bash -c '$HOME/homebrew/bin/claude --dangerously-skip-permissions --model haiku -p \"reply OK\" > /tmp/canary.txt 2>&1; sleep 10'"
sleep 15
grep -qi "OK" /tmp/canary.txt
/opt/homebrew/bin/tmux kill-session -t verify-canary 2>/dev/null
```

If ANY check fails after a rebase+deploy: jump to ROLLBACK.
If checks fail on a verify-only run (no rebase): report the issue but don't rollback (the problem isn't from the rebase).

### 9. Push
Only if rebase happened and verify passed:
```bash
cd $HOME/instar-dev
git push fork main --force-with-lease --no-verify
```

### ROLLBACK
```bash
cd $HOME/instar-dev
git rebase --abort 2>/dev/null
git reset --hard $ROLLBACK
npm run build
cd $AGENT_DIR/.instar/shadow-install
npm install "@{{INSTAR_FORK_ORG}}/instar@file:../../../../../instar-dev"
npm install better-sqlite3
launchctl kickstart -k gui/$(id -u)/ai.instar.Roland
sleep 5
curl -s http://localhost:4040/health
```
Report the failure via iMessage.

## Reporting

Send via `imsg send --to "$(python3 -c "import json; d=json.load(open(.instar/config.json)); print(d.get(imessage,{}).get(userPhone,))")" --text "MESSAGE"` only if:
- Upstream had new commits (say what changed)
- Conflicts occurred
- Build/verify failed
- Rollback performed

Silent when nothing changed.

## Our customizations (for reference)

As of 2026-04-24, all our custom commits have been merged upstream. We are at **zero divergence** — instar-dev/main = JKHeadley/instar/main at v0.28.73.

Previously maintained custom commits (now upstream):
- **Immediate ack**: sends "..." before session spawn
- **1:1 trigger fix**: mention mode only gates group chats
- **OAuth vs API key auto-detect**: routes tokens to correct env var (CLAUDE_CODE_OAUTH_TOKEN vs ANTHROPIC_API_KEY) — this was the auth message fix
- **directMessageTrigger config respect**
- **Attachment hardlinking** (multiple commits)

When new customizations are needed, add ONE commit on top of upstream and keep it rebased. If upstream merges equivalent features, drop our commit and rebase clean.
