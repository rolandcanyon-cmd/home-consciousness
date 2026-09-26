---
name: known-homekit-fda-broken
description: homekit-dump.py currently fails with authorization denied — FDA grant invalidated by python3 upgrade
metadata: 
  node_type: memory
  type: project
  originSessionId: 3867dcfa-2921-4fd9-aefc-c0baebfa102f
  modified: 2026-09-22T11:49:50.341Z
---

Verified 2026-09-22: `homekit-dump.py` (reads `~/Library/HomeKit/core.sqlite`) fails on both `/opt/homebrew/bin/python3` ("unable to open database file") and `/usr/bin/python3` ("authorization denied"). This contradicts the older [[project_homekit_database]] memory claiming it works — that claim was never re-verified live before being repeated.

**Why:** macOS Full Disk Access (FDA) grants are tied to the exact resolved binary path/signature. Homebrew's `python3` symlink was repointed by a brew upgrade (Cellar path now `python@3.14/3.14.7`, installed Aug 19 2026), which invalidates any FDA grant made against the previous binary. Same failure class as [[known_tmux_upgrade_breaks_imessage_send]] — any homebrew-managed binary with a TCC grant is fragile across upgrades.

**How to apply:** Before claiming a HomeKit read works, run `python3 ~/.instar/agents/Roland/.claude/scripts/homekit-dump.py --brief` live and check for "authorization denied" / "unable to open database file" rather than trusting memory. Fix requires physical/screen-share access: System Settings > Privacy & Security > Full Disk Access > + > Cmd+Shift+G > paste `readlink -f $(which python3)` > add > toggle on. Adrian is away from the house (6-week trip starting ~2026-09-22) so this can't be fixed remotely — flag it as needing in-person or screen-share attention. Corfe (UK peer install) reported the same category of failure independently.
