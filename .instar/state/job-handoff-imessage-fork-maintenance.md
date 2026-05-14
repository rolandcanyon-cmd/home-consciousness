# Handoff Notes — imessage-fork-maintenance
# Written: 2026-05-14T14:40:00Z

## Run Summary
- **Status**: Completed successfully
- **Upstream commits pulled**: 47 (v0.28.101 → v0.28.105, tag v0.28.102)
- **Upstream HEAD at close**: 656360b5 (feat(remediation): A47 — PrimaryAggregatorLease + failover)
- **Our fork HEAD**: a5423ddd

## What We're Running
2 commits above upstream (down from 3 — NEXT.md fix was merged upstream):
1. `0aceee8b` fix(ci): fall back to github.token when RELEASE_TOKEN secret is unset
2. `a5423ddd` fix(scheduler): add explicit types for js-yaml listener params, install missing js-yaml dep

## Rebase Notes
- **NEXT.md commit dropped**: Our `4cccfce6` was redundant — upstream merged `5df626f1` (same fix). Skipped cleanly during rebase.
- **js-yaml conflict**: Trivial conflict in `builtin-manifest.json` (timestamp/version). Resolved by accepting upstream HEAD values. Fix itself applied cleanly.

## Fork CI Status (at close)
- worktree-trailer-sig-check: ✅ success
- CI: ✅ success (all shards passed — GitHub infra issue from last run is resolved)
- Publish to npm: ❌ failure — NOT NPM_TOKEN this time. Failing on "Check upgrade guide":
  - v0.28.103.md has inline code in "What to Tell Your User"
  - v0.28.103.md references camelCase config keys directly (e.g. "silentReject: false")
  - v0.28.103.md "What Changed" claims bug fix but has no Evidence section
  - Upstream quality issue in their upgrade guide, NOT caused by our commits
  - Our fork doesn't publish anyway (no NPM_TOKEN), so this is cosmetic

## Server State at Close
- Health: ok, uptime ~20s post-restart
- iMessage: connected
- Canary: passed
- Node symlink: fixed to ~/homebrew/bin/node
- autoApply: false

## Next Run Notes
- If upstream fixes v0.28.103.md upgrade guide → Publish to npm will progress further (until NPM_TOKEN)
- If upstream merges equivalent js-yaml types fix → drop `a5423ddd`
- We're at 2 commits above upstream; goal is 1 (the CI-fix)
- The 47-commit update included major new infrastructure: Remediator, ServerSupervisor, MachineLocks, DegradationReporter wiring, pre-prompt memory recall, pre-compaction memory flush

## Known Issue: iMessage Heartbeat
Phone number not configured in imessage config — heartbeat reported to chat session only.
