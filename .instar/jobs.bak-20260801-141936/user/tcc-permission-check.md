---
name: TCC Permission Check
description: Detect when macOS resets Full Disk Access / Messages TCC permissions (e.g. after an OS upgrade) so it surfaces proactively instead of as a silent popup-required surprise.
schedule: 0 9 * * *
priority: high
expectedDurationMinutes: 1
model: haiku
enabled: true
tags:
  - cat:guardian
  - exec:prompt
gate: curl -sf http://localhost:4040/health >/dev/null 2>&1
toolAllowlist:
  - Bash
---
Check whether macOS has reset Full Disk Access / Messages TCC permissions (this happens after OS upgrades and breaks unattended iMessage operation until manually re-granted via a GUI popup — it cannot be fixed from the command line).

Run these two checks:

1. `sqlite3 "$HOME/Library/Messages/chat.db" "select count(*) from message limit 1;"` — if this fails (permission denied / database locked), node has lost its Messages/Full Disk Access grant.
2. `curl -s -H "Authorization: Bearer $AUTH" http://localhost:4040/health` (read AUTH from `.instar/config.json` as usual) and inspect `systemReview.failedProbes` for an entry with `probeId` of `instar.platform.shell-fda` — if present, the shell has lost Full Disk Access too.

If either check fails, queue ONE attention item (`POST /attention`, priority `high`, source `tcc-permission-check`) describing in plain language what broke and that it needs a manual grant via System Settings > Privacy & Security > Full Disk Access (add the shell/terminal app and/or re-grant node). Do not attempt to fix it yourself — TCC grants for protected resources cannot be set from the command line.

If both checks pass, exit silently — no message needed.
