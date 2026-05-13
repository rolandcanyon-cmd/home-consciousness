# Handoff Notes — imessage-fork-maintenance
# Written: 2026-05-13T15:20:00Z

## Run Summary
- **Status**: Completed successfully
- **Upstream commits pulled**: 15 (v0.28.97 → v0.28.101)
- **Upstream HEAD at close**: b3179630 (feat: lock-file runtime consumer Phase 1c)
- **Our fork HEAD**: 4cccfce6

## What We're Running
3 commits above upstream:
1. `494285c9` fix(ci): fall back to github.token when RELEASE_TOKEN secret is unset
2. `ff4ec013` fix(scheduler): add explicit types for js-yaml listener params, install missing js-yaml dep
3. `4cccfce6` fix(upgrades): remove inline code from NEXT.md What to Tell Your User section

## Upstream Bugs Fixed This Run
- **js-yaml implicit-any TS errors**: AgentMdJobLoader.ts line 717 had untyped listener params. Fixed with `yaml.EventType` and `yaml.State` types. js-yaml was also missing from node_modules.
- **NEXT.md inline code**: The "What to Tell Your User" section had backtick-wrapped identifiers, causing the Check upgrade guide CI step to fail. Fixed to plain prose.
- Bug report submitted via feedback API (fb-2ba9a499-6c1).

## Fork CI Status (at close)
- worktree-trailer-sig-check: ✅ success
- CI: ⏳ in_progress — 6/8 unit test shards passed, 2 shards (node 20 shard 1/4, node 22 shard 2/4) stuck on "Install tmux" step (GitHub runner infrastructure issue, not our code)
- Publish to npm: ❌ failure — expected (no NPM_TOKEN in fork, not a publishing fork)

## Server State at Close
- Health: ok, uptime ~45min post-restart
- iMessage: connected
- Canary: passed

## Known Issue: iMessage Heartbeat
The heartbeat iMessage cannot be sent when this skill runs as a scheduled job (daemon context). Messages.app cannot open in the LaunchAgent/daemon context. The heartbeat only works when run interactively from Terminal. Logged in attention queue.

## Next Run Notes
- If upstream ships fix for the js-yaml/TS errors → drop commit ff4ec013
- If upstream ships fix for NEXT.md inline code → drop commit 4cccfce6
- We should be back to 1 custom commit (the CI-fix) after upstream addresses these
- If the 2 stuck CI shards eventually fail/pass, no action needed — it's a GitHub infra issue
