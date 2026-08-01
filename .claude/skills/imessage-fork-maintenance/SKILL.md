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

# Fix node-candidates.json — server re-evaluates this on restart and can re-pick /opt/homebrew
# (Adrian's Homebrew) over ~/homebrew (Roland's), causing a TCC permission popup
python3 -c "
import json, os
f = os.path.expanduser('~') + '/.instar/agents/Roland/.instar/bin/node-candidates.json'
d = json.load(open(f))
correct = os.path.expanduser('~/homebrew/bin/node')
if d.get('primary') != correct:
    d['primary'] = correct
    json.dump(d, open(f,'w'), indent=4)
    print('Fixed node-candidates.json primary: was', repr(d.get('primary')), '-> now', repr(correct))
else:
    print('node-candidates.json primary already correct:', repr(correct))
"

# Fix autoApply — must be false since we manage updates via this rebase job
python3 -c "
import json
c = json.load(open('$AGENT_DIR/.instar/config.json'))
c.setdefault('updates', {})['autoApply'] = False
json.dump(c, open('$AGENT_DIR/.instar/config.json', 'w'), indent=2)
"

# Daemon runs as user-level LaunchAgent (gui/UID), NOT the system LaunchDaemon.
# The system plist (/Library/LaunchDaemons/ai.instar.{AGENT_NAME}.plist) is a stale
# duplicate that manages a separate process — kickstarting it does NOT restart the server.
# Use gui/$(id -u)/ which requires no sudo.
UPTIME_BEFORE=$(curl -s http://localhost:4040/health | python3 -c "import json,sys; print(json.load(sys.stdin).get('uptime',0))")
launchctl kickstart -k gui/$(id -u)/ai.instar.{AGENT_NAME} || { echo "❌ daemon restart failed"; exit 1; }
sleep 8
UPTIME_AFTER=$(curl -s http://localhost:4040/health | python3 -c "import json,sys; print(json.load(sys.stdin).get('uptime',0))")
if [ "$UPTIME_AFTER" -ge "$UPTIME_BEFORE" ]; then
  echo "❌ daemon did not actually restart (uptime didn't reset)"
  exit 1
fi
echo "✅ daemon restarted (uptime reset from ${UPTIME_BEFORE}ms to ${UPTIME_AFTER}ms)"

# Fix job priorities — MUST run AFTER the restart, then restart AGAIN.
# The installer regenerates jobs/schedule/*.json AT SERVER BOOT (mtimes land ~1s before
# scheduler_start), preserving `enabled` but NOT `priority` — so these four revert to `low`.
# A repair written BEFORE the kickstart is wiped by the very boot it precedes (confirmed
# 07-31: repaired 15:02Z, still shed 15:00–19:51Z because the loader read the regenerated
# files). The quota gate in degraded mode (source claude-jsonl) refuses ALL low-priority
# jobs unconditionally, so a reverted priority means these four are silently shed all day.
# Job definitions load at server start — no hot reload — hence the second restart.
REPAIRED=$(python3 -c "
import json, os
d = os.path.expanduser('~') + '/.instar/agents/Roland/.instar/jobs/schedule'
n = 0
for slug in ['insight-harvest', 'overseer-development', 'relationship-maintenance', 'rope-health-digest']:
    f = d + '/' + slug + '.json'
    if not os.path.exists(f): continue
    j = json.load(open(f))
    if j.get('priority') == 'low':
        j['priority'] = 'medium'
        json.dump(j, open(f, 'w'), indent=2)
        n += 1
print(n)
")
echo "priority repairs applied: $REPAIRED"
# warn about any OTHER enabled+low override that would also be shed
python3 -c "
import json, os
d = os.path.expanduser('~') + '/.instar/agents/Roland/.instar/jobs/schedule'
for f in sorted(x for x in os.listdir(d) if x.endswith('.json')):
    j = json.load(open(d + '/' + f))
    if j.get('enabled') and j.get('priority') == 'low':
        print('  ⚠ enabled+low (will be shed in degraded quota mode): ' + f)
"
if [ "$REPAIRED" -gt 0 ]; then
  UPTIME_BEFORE2=$(curl -s http://localhost:4040/health | python3 -c "import json,sys; print(json.load(sys.stdin).get('uptime',0))")
  launchctl kickstart -k gui/$(id -u)/ai.instar.{AGENT_NAME} || { echo "❌ second daemon restart failed"; exit 1; }
  sleep 8
  UPTIME_AFTER2=$(curl -s http://localhost:4040/health | python3 -c "import json,sys; print(json.load(sys.stdin).get('uptime',0))")
  if [ "$UPTIME_AFTER2" -ge "$UPTIME_BEFORE2" ]; then
    echo "❌ second restart did not take (priorities NOT loaded — jobs will be shed today)"
    exit 1
  fi
  # boot regeneration wipes priority again — so confirm the LOADED definitions, not the files
  AUTH=$(python3 -c "import json; print(json.load(open('$AGENT_DIR/.instar/config.json')).get('authToken',''))")
  curl -s -H "Authorization: Bearer $AUTH" http://localhost:4040/jobs | python3 -c "
import json,sys
jobs = json.load(sys.stdin).get('jobs', [])
bad = [j['slug'] for j in jobs if j.get('slug') in ('insight-harvest','overseer-development','relationship-maintenance','rope-health-digest') and j.get('priority') != 'medium']
print('❌ loaded priority still wrong: ' + ', '.join(bad) if bad else '✅ loaded priorities confirmed medium')
"
fi
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
After pushing, wait for GitHub Actions to complete on the fork (checks whichever workflows actually run — as of 2026-07-13 that's `CI`, `Docs Coverage Weekly Audit`, and `worktree-trailer-sig-check`; the rest are disabled, see "Our customizations" below):

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
      
      # Report the CI failure
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
ln -sf $HOME/homebrew/bin/node $AGENT_DIR/.instar/bin/node
python3 -c "
import json, os
f = os.path.expanduser('~') + '/.instar/agents/Roland/.instar/bin/node-candidates.json'
d = json.load(open(f))
d['primary'] = os.path.expanduser('~/homebrew/bin/node')
json.dump(d, open(f,'w'), indent=4)
"
launchctl kickstart -k gui/$(id -u)/ai.instar.{AGENT_NAME}
sleep 5
curl -s http://localhost:4040/health
```
Report the failure via iMessage.

## Reporting

**Always send a heartbeat at the end of every run**, even when nothing changed. Use:

```bash
PHONE=$(python3 -c "
import json
d = json.load(open('$AGENT_DIR/.instar/config.json'))
phone = d.get('imessage', {}).get('userPhone', '')
if not phone:
    for m in d.get('messaging', []):
        if m.get('type') == 'imessage':
            contacts = m.get('config', {}).get('authorizedContacts', [])
            phone = next((c for c in contacts if not c.startswith('+') or c.startswith('+1')), contacts[0] if contacts else '')
            break
print(phone)
")
cat <<MSG | $AGENT_DIR/.claude/scripts/imessage-reply.sh "$PHONE"
MESSAGE TEXT HERE
MSG
```

**Heartbeat format (no-change run):**
```
Instar daily sync ✓ — upstream unchanged, still at [SHORT_SHA]. Our CI-fix commit in place. Server healthy.
```

**Heartbeat format (rebase run):**
```
Instar daily sync — pulled [N] upstream commit(s): [one-line summary of changes]. Rebuilt and restarted. CI: [passed/failed/timeout].
```

**Always escalate immediately (same message) if:**
- Conflicts occurred (include which files)
- Build failed (include error summary)
- Verify checks failed
- Rollback was performed
- CI failed after push

## Our customizations (for reference)

As of 2026-07-21, we have **5 commits** above upstream (JKHeadley/instar):

- **`a3c46f385` fix(ci): fall back to github.token when RELEASE_TOKEN secret is unset** — keeps fork CI green when RELEASE_TOKEN secret is absent. Candidate for upstream PR.
- **`3f388413b` chore(fork): add side-effects review artifact for v1.3.619 CI fix [skip ci]** — maintenance artifact, not functional.
- **`a0929d88f` feat(imessage): self-heal chat.db/WAL/SHM hardlinks in FDA watcher** — macOS recreates chat.db-wal with a new inode on every reboot, orphaning the private hardlink the no-FDA daemon reads Messages through; this re-links it automatically. Candidate for upstream PR.
- **`c00bf680f` fix(ci): truncate docs-coverage issue body to GitHub's 65536-char limit** — weekly docs-coverage tracking issue was failing with "Body is too long" as the doc tree grew. Candidate for upstream PR.
- **`7ea921220` docs(upgrades): add release-note fragment for docs-coverage truncation fix** — release-note fragment for the commit above, not functional.

Previously maintained custom commits (now merged upstream):
- **Immediate ack**: sends "..." before session spawn
- **1:1 trigger fix**: mention mode only gates group chats
- **OAuth vs API key auto-detect**: routes tokens to correct env var
- **directMessageTrigger config respect**
- **Attachment hardlinking** (multiple commits)
- **fix(scheduler): add explicit types for js-yaml listener params** — merged in v1.3.620/621
- **fix(upgrades): remove inline code from NEXT.md** — merged in v1.3.620/621

When new customizations are needed, add commits on top of upstream and keep them rebased. If upstream merges equivalent features, drop our commit and rebase clean. The goal is to return to 1 commit (the CI-fix) as soon as upstream ships an equivalent.
