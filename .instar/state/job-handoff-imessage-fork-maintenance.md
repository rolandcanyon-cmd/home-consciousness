# Handoff Notes — imessage-fork-maintenance
# Written: 2026-06-19T14:35:00Z

## Run Summary
- **Status**: Completed successfully (rebase run)
- **Upstream commits pulled**: 9 (v1.3.622–626)
- **Upstream HEAD after rebase**: e9f36088 (chore: release v1.3.626)
- **Our fork HEAD**: f6ced0e7

## What Was Pulled
- `ca105a50` fix(ws52): wire the 3 enroll seams so account-follow-me works end-to-end
- `73d4863e` fix(ws52): real login link (code=t de-wrap) + tap-simple Pending Logins card
- `b27fc027` feat(ws52): operator code paste-back for account-follow-me (off-chat, self-serve)
- Release v1.3.622, v1.3.623, v1.3.624 chores
- `6105b9c3` feat(subscriptions): account × machine matrix — in-dashboard cross-machine account setup (#1230)
- `54b192d3` feat(testing): enforce scrape/parser tests use REAL captured fixtures (#1229)
- `e9f36088` chore: release v1.3.626

## Our Commits (still 2 above upstream)
1. `98a40ff6` fix(ci): fall back to github.token when RELEASE_TOKEN secret is unset
2. `f6ced0e7` chore(fork): add side-effects review artifact for v1.3.619 CI fix [skip ci]

## Verification Checks (all passed)
- Server: healthy
- OAuth routing: present in shadow-install dist
- iMessage: connected (reconnect attempts: 0)
- tmux: alive
- Canary: passed (Claude haiku replied OK)
- Daemon restart: confirmed (uptime reset from 55719820ms to 7590ms)

## Push
Pushed to fork with --force-with-lease. CI not triggered (top commit has [skip ci]).

## Fork CI Status
No runs for current SHA (expected — [skip ci]).
Previous SHA `a5423ddd`: CI ✅, Publish to npm ❌ (upstream upgrade guide quality lint — pre-existing issue, not caused by our changes).

## Heartbeat
Sent via iMessage to +14084424360 ✅ (interactive session has Automation permission — still fails from LaunchAgent job context).

## Next Run Notes
- Neither custom commit was merged upstream in this batch — still 2 commits above
- The js-yaml types fix (previously in `a5423ddd`) was merged upstream, replaced by newer CI-fix + side-effects artifact
- The Publish to npm CI failure is a pre-existing upstream issue with historical upgrade guide formatting; ignore unless upstream fixes it
- Watch for upstream equivalents of our github.token fallback fix (then we can drop to 1 commit)
- Goal: return to 1 commit (the CI-fix only) once upstream ships an equivalent
