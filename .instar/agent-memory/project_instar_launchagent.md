---
name: project-instar-launchagent
description: "Correct LaunchAgent to restart for instar server — user-level gui, not system daemon"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7036217f-7139-4b94-879a-8984aafb39a9
---

The real instar server (port 4040) runs under the **user-level LaunchAgent**, not the system LaunchDaemon.

- **Correct restart**: `launchctl kickstart -k gui/$(id -u)/ai.instar.Roland` — no sudo needed
- **Wrong target**: `sudo launchctl kickstart -k system/ai.instar.Roland` — this restarts the stale duplicate (PID ~98673), NOT the server on port 4040

**Process tree:**
- `gui/UID/ai.instar.Roland` → PID 4162 (instar-boot.cjs, user agent, PPID=1) → PID 4176 (actual server on :4040)
- `system/ai.instar.Roland` → PID 98673 (instar-boot.js, stale system daemon, PPID=1) — the known duplicate [[Duplicate system launchd daemon (known)]]

**Plist files:**
- `/Users/rolandcanyon/Library/LaunchAgents/ai.instar.Roland.plist` — the REAL one (user-level)
- `/Library/LaunchDaemons/ai.instar.Roland.plist` — the stale duplicate (system-level, needs user sudo to remove)

**Why:** The skill documentation says `system/ai.instar.Roland` but that's wrong for this machine. The LaunchAgent was installed at user level, not system level. The skill needs updating (or the duplicate system plist needs removal).

**How to apply:** Always restart with `launchctl kickstart -k gui/$(id -u)/ai.instar.Roland` in the maintenance job. Verify restart by checking uptime drops.
