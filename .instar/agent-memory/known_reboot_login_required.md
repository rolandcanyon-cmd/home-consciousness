---
name: known-reboot-login-required
description: After a Mac reboot the Instar server does NOT auto-start until GUI login; iMessage synced db is stale until then
metadata: 
  node_type: memory
  type: project
  originSessionId: 30164ac5-1517-43cb-bb47-5b01b51408c9
---

The Instar server for Roland runs as a **GUI-domain LaunchAgent** (`gui/$(id -u)/ai.instar.Roland`), so after a macOS reboot it does NOT start until a user logs into the desktop session. This is by design for an iMessage agent: `~/Library/Messages/chat.db` and imagent only populate after GUI login, so a system-level LaunchDaemon wouldn't help.

Symptom seen 2026-07-06: after reboot Adrian reported "Roland not running" + "did not respond to iMessage". Server started at 09:44 the moment he logged in — not a crash.

Two stacked causes of the no-response:
1. Server down (reboot → waiting at login screen) = no polling, no replies.
2. The adapter polls a SYNCED COPY at `.instar/imessage/chat.db` (dbPath in config), NOT the live `~/Library/Messages/chat.db`. That copy goes stale while the server is down and only re-syncs after the server restarts (refreshed 09:48 in this incident). Verify currency: compare latest message timestamps in the synced copy vs live db.

Auto-login is NOT possible: **FileVault is On**, and macOS forbids automatic login while FileVault is enabled (the encrypted-disk unlock screen at boot IS the login). Enabling classic auto-login would require disabling FileVault (disk no longer encrypted at rest + hours to re-encrypt). Adrian chose **Leave as-is (2026-07-06)** — keep FileVault on, log in manually, accept the few-seconds gap. DO NOT re-offer auto-login unless he asks. Note: at the FileVault boot screen, unlocking AS the `rolandcanyon` user logs it straight in and starts the server with no second login (the server's GUI LaunchAgent lives in rolandcanyon's session, not adriancockcroft's).

The "database disk image is malformed" poll errors in server.log were all from 2026-07-02 and are historical/resolved — do not re-diagnose as current.

Restart lever if needed: `launchctl kickstart -k gui/$(id -u)/ai.instar.Roland` (see [[project_instar_launchagent]]). Related: [[feedback_never_delete_chat_db]].
