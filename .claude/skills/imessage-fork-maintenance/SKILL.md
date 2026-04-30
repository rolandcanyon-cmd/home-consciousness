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
- **Server**: LaunchAgent `ai.instar.{AGENT_NAME}`, port 4040

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

# Daemon lives at SYSTEM level (/Library/LaunchDaemons/ai.instar.{AGENT_NAME}.plist),
# NOT user gui level. `gui/$(id -u)/` kickstart silently no-ops on system daemons.
# Requires sudo. The job runner must have NOPASSWD configured for this command
# in /etc/sudoers.d/, or this step will hang waiting for a password.
UPTIME_BEFORE=$(curl -s http://localhost:4040/health | python3 -c "import json,sys; print(json.load(sys.stdin).get('uptime',0))")
sudo -n launchctl kickstart -k system/ai.instar.{AGENT_NAME} || { echo "❌ daemon restart failed — sudo NOPASSWD missing?"; exit 1; }
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

### 10. Monitor fork CI after push
After pushing, wait for GitHub Actions to complete on the fork. Check both the `CI` workflow and the `Publish to npm` workflow:

```bash
# Wait up to 15 minutes for CI runs triggered by the push to complete
FORK_REPO="rolandcanyon-cmd/instar"
PUSH_SHA=$(git rev-parse HEAD)
DEADLINE=$(($(date +%s) + 900))  # 15 min timeout

echo "Waiting for CI to start on $PUSH_SHA..."
sleep 30  # give GitHub time to queue the run

while [ $(date +%s) -lt $DEADLINE ]; do
  # Get the latest runs for this SHA
  RUNS=$(gh run list --repo "$FORK_REPO" --commit "$PUSH_SHA" --json name,status,conclusion,databaseId 2>/dev/null)
  
  if [ -z "$RUNS" ] || [ "$RUNS" = "[]" ]; then
    echo "No runs yet, waiting..."
    sleep 30
    continue
  fi
  
  # Check if all runs are complete
  IN_PROGRESS=$(echo "$RUNS" | python3 -c "import json,sys; runs=json.load(sys.stdin); print(sum(1 for r in runs if r['status'] not in ('completed','')))")
  
  if [ "$IN_PROGRESS" = "0" ]; then
    # All done — check for failures
    FAILURES=$(echo "$RUNS" | python3 -c "import json,sys; runs=json.load(sys.stdin); print('\n'.join(f\"{r['name']}: {r['conclusion']}\" for r in runs if r['conclusion'] not in ('success','skipped','')))")
    
    if [ -n "$FAILURES" ]; then
      echo "❌ CI failures detected:"
      echo "$FAILURES"
      
      # Get failure details for each failed run
      echo "$RUNS" | python3 -c "
import json,sys,subprocess
runs=json.load(sys.stdin)
for r in runs:
    if r['conclusion'] not in ('success','skipped',''):
        result = subprocess.run(['gh','run','view',str(r['databaseId']),'--repo','$FORK_REPO','--log-failed'], capture_output=True, text=True)
        print(f'=== {r[\"name\"]} ===')
        print(result.stdout[-3000:] if len(result.stdout) > 3000 else result.stdout)
" 2>&1
      
      # Attempt to fix the specific known failure: RELEASE_TOKEN → github.token fallback
      # Check if it's the Publish to npm workflow failing on token
      PUBLISH_FAIL=$(echo "$RUNS" | python3 -c "import json,sys; runs=json.load(sys.stdin); print('yes' if any(r['name']=='Publish to npm' and r['conclusion']=='failure' for r in runs) else 'no')")
      
      if [ "$PUBLISH_FAIL" = "yes" ]; then
        echo "Publish to npm failed — checking if publish.yml has the github.token fallback..."
        if grep -q 'RELEASE_TOKEN || github.token' .github/workflows/publish.yml; then
          echo "Fallback already in place. Check NPM_TOKEN secret and re-run."
          # Re-trigger the failed publish run
          PUBLISH_RUN_ID=$(echo "$RUNS" | python3 -c "import json,sys; runs=json.load(sys.stdin); r=[x for x in runs if x['name']=='Publish to npm'][0]; print(r['databaseId'])")
          gh run rerun "$PUBLISH_RUN_ID" --repo "$FORK_REPO" --failed 2>&1 && echo "Re-triggered Publish to npm run"
        else
          echo "Applying github.token fallback to publish.yml..."
          sed -i 's/token: \${{ secrets.RELEASE_TOKEN }}/token: ${{ secrets.RELEASE_TOKEN || github.token }}/' .github/workflows/publish.yml
          git add .github/workflows/publish.yml
          git commit -m "fix(ci): fall back to github.token when RELEASE_TOKEN secret is unset [skip ci]"
          git push fork main --force-with-lease --no-verify
          echo "Fix pushed — CI will re-run automatically"
        fi
      fi
      
      # Report the CI failure regardless
      FAIL_SUMMARY=$(echo "$RUNS" | python3 -c "import json,sys; runs=json.load(sys.stdin); print(', '.join(f\"{r['name']}\" for r in runs if r['conclusion'] not in ('success','skipped','')))")
      # (report handled in Reporting section below)
      CI_STATUS="failed: $FAIL_SUMMARY"
    else
      echo "✅ All CI checks passed"
      CI_STATUS="passed"
    fi
    break
  else
    echo "$IN_PROGRESS run(s) still in progress, waiting..."
    sleep 30
  fi
done

if [ $(date +%s) -ge $DEADLINE ]; then
  echo "⚠️ CI timeout after 15 minutes"
  CI_STATUS="timeout"
fi
```

Include `$CI_STATUS` in the push report. Alert via iMessage if CI failed or timed out.

### ROLLBACK
```bash
cd $HOME/instar-dev
git rebase --abort 2>/dev/null
git reset --hard $ROLLBACK
npm run build
cd $AGENT_DIR/.instar/shadow-install
npm install "@{{INSTAR_FORK_ORG}}/instar@file:../../../../../instar-dev"
npm install better-sqlite3
launchctl kickstart -k gui/$(id -u)/ai.instar.{AGENT_NAME}
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
