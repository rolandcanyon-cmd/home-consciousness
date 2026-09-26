---
name: known-node-pin-crash
description: Server must run ~/homebrew node v25; /opt/homebrew node v26 crash-loops it. boot.cjs can flip the symlink after a reboot; a watchdog re-pins it.
metadata: 
  node_type: memory
  type: project
  originSessionId: 313c0acf-d8c8-4dcc-8351-eac02f6e69da
---

After a macOS upgrade + reboot/login (first seen 2026-06-30), Roland's Instar server came up **degraded** (SQLite/knowledge-graph offline, iMessage down) and later crash-looped (`libc++abi: mutex lock failed: Invalid argument`, exit `EX_CONFIG`).

**Root cause — two Homebrew node installs at different majors:**
- `~/homebrew/bin/node` (user `rolandcanyon`, **v25.8.2**) — the VERIFIED-GOOD node. Server runs healthy here.
- `/opt/homebrew/bin/node` (user `adriancockcroft`, **v26.4.0**, bumped by the OS upgrade) — **CRASHES the full server** even though every native module `require()`s fine under it in isolation (they're all N-API).

`instar-boot.cjs` `selfHealNodeSymlink()` self-heals `.instar/bin/node`; on a *transient* post-reboot `better-sqlite3` load failure it searches candidates, **prefers `/opt/homebrew`**, and its only test is "can this node load better-sqlite3?" — which v26 passes (then crashes). The agent's own `~/homebrew` node is NOT in its candidate list, so it can't heal back.

**Fix deployed (agent-owned, survives instar updates):**
- `.instar/bin/node` pinned to `~/homebrew/bin/node`.
- LaunchAgent `ai.instar.Roland.nativeheal` (RunAtLoad + every 300s) → `.instar/scripts/native-heal-watchdog.sh`: if the symlink drifted off the good node it re-pins and bounces the agent once; also bounces once on a native-SQLite degradation. Bounded by 180s cooldown + 4/hour cap; never blindly restarts a plain-down server (avoids racing the fleet watchdog / single-instance guard → the `EX_CONFIG` churn).
- Upstream bug filed: `fb-40b57728-c71`. Self-knowledge fact recorded (shows at session start).

**Manual recovery if it recurs:** `readlink ~/.instar/agents/Roland/.instar/bin/node` — if it points to `/opt/homebrew`, `ln -sfn /Users/rolandcanyon/homebrew/bin/node` that path, then `launchctl kickstart -k gui/$(id -u)/ai.instar.Roland`. NEVER pin to `/opt/homebrew` (v26 crashes). Don't rapid-fire kickstarts — clean `launchctl bootout`+`bootstrap` once and wait. Related: [[project_instar_launchagent]].
