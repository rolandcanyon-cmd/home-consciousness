---
name: imessage-doctor
description: Diagnose and fix iMessage not responding / not receiving on the Instar fork. Covers the stale-WAL-hardlink root cause, Full Disk Access (TCC) issues, and the self-healing Go watcher. Trigger words - imessage not working, imessage not responding, not getting imessage, imessage stopped, imessage broken, chat.db, messages not coming through.
metadata:
  user_invocable: "true"
---

# /imessage-doctor — iMessage debugging & repair

Use this when iMessage isn't responding, isn't receiving, or "worked yesterday, broke after a reboot." It encodes the real architecture so you don't re-diagnose from scratch.

## The architecture (READ THIS FIRST — it explains every failure)

The node server daemon **deliberately does NOT have Full Disk Access (FDA)**. macOS protects `~/Library/Messages/` behind TCC, and the node binary's FDA grant is lost on every node version bump — so relying on it is fragile.

Instead, the daemon reads the Messages database through **hardlinks** in a non-protected dir:

```
~/Library/Messages/chat.db        ──hardlink──▶  .instar/imessage/chat.db
~/Library/Messages/chat.db-wal    ──hardlink──▶  .instar/imessage/chat.db-wal   ← the critical one
~/Library/Messages/chat.db-shm    ──hardlink──▶  .instar/imessage/chat.db-shm
```

`dbPath` in `config.json` points at `.instar/imessage/chat.db` — **this is correct and intentional, not a hack.** Do NOT "fix" it by pointing at the live path; node lacks FDA and will fail with `unable to open database file`.

**Why the -wal file is everything:** SQLite (Messages.app) writes new messages to the `-wal` sidecar; they only land in the main `chat.db` on a *checkpoint*, which is irregular. A reader sees new messages only if it reads the **live** `-wal`. The hardlink shares the live inode, so live writes are visible — UNTIL macOS Messages recreates the `-wal` with a **new inode** (happens on every **machine reboot** / Messages restart). Then the private hardlink points at a dead inode, the daemon sees only stale checkpointed data, and **iMessage silently stops responding to anything new.** This is the #1 root cause.

Two processes with FDA maintain the hardlinks:
- **`instar-attachments-sync`** (Go binary, LaunchAgent `ai.instar.AttachmentsWatcher`) — HAS FDA. Mirrors photo attachments AND (as of 2026-07-06) continuously re-links chat.db/wal/shm every 2s, so the daemon self-heals after a reboot. Source: `~/instar-dev/scripts/attachments-sync/main.go`.
- `IMessageAdapter.ensureChatDbHardlink()` — runs at daemon startup, but needs FDA on node (usually absent), so it's best-effort only.

Note: a plain **server restart** (`launchctl kickstart ai.instar.Roland`) does NOT recreate the WAL, so it does NOT break the links. Only a **machine reboot / Messages restart** does.

## Fast diagnosis (run these in order)

```bash
AGENT=/Users/rolandcanyon/.instar/agents/Roland
MSG=$HOME/Library/Messages

# 1) Is the adapter even connected?
AUTH=$(python3 -c "import json;print(json.load(open('$AGENT/.instar/config.json')).get('authToken',''))")
curl -s -H "Authorization: Bearer $AUTH" http://localhost:4040/imessage/status   # want {"state":"connected"}

# 2) THE key check — does the daemon's copy match the live DB?
echo "live :"; sqlite3 "$MSG/chat.db" "select datetime(max(date)/1000000000+978307200,'unixepoch','localtime') from message;"
echo "priv :"; sqlite3 "$AGENT/.instar/imessage/chat.db" "select datetime(max(date)/1000000000+978307200,'unixepoch','localtime') from message;"
#   → if priv is OLDER than live, the WAL hardlink is stale. This is the bug.

# 3) Confirm it's the inodes (the wal one will differ when broken)
for n in chat.db chat.db-wal chat.db-shm; do
  printf "%-14s live=%s priv=%s\n" "$n" "$(stat -f %i "$MSG/$n" 2>/dev/null)" "$(stat -f %i "$AGENT/.instar/imessage/$n" 2>/dev/null)"
done

# 4) Is the FDA watcher healthy? (permission errors here = FDA problem, see below)
tail -5 "$AGENT/.instar/logs/attachments-watcher.log"
```

## Fixes

### Fix A — relink now (immediate, needs an FDA shell)
If priv is older than live / inodes differ, re-link from a shell **that has Full Disk Access** (a Terminal with FDA, or this Claude session if it has it):

```bash
bash $AGENT/.claude/scripts/imessage-relink-chatdb.sh --restart
```

The script re-links all three files and verifies. If it prints `this shell lacks Full Disk Access`, FDA is the real problem → Fix C.

### Fix B — the durable self-heal (the robust Go watcher)
The `instar-attachments-sync` Go binary re-links chat.db/wal/shm every 2s, so reboots self-heal with no manual step. Source lives at `~/instar-dev/scripts/attachments-sync/main.go` (`syncChatDb` + `chatDbLoop`). To rebuild + deploy:

```bash
cd ~/instar-dev/scripts/attachments-sync && go build -o /tmp/iasync . 
BIN=$AGENT/.instar/bin/instar-attachments-sync
cp -p "$BIN" "$BIN.bak-$(date +%s)"    # backup (keeps the FDA-granted bytes)
cp /tmp/iasync "$BIN"
launchctl kickstart -k gui/$(id -u)/ai.instar.AttachmentsWatcher
tail -5 "$AGENT/.instar/logs/attachments-watcher.log"
```

⚠️ **Rebuilding CHANGES the binary's signature and macOS TCC will flip its FDA grant to DENIED** (`operation not permitted` in the log). After ANY rebuild you MUST re-grant FDA → Fix C. This is the one unavoidable manual step; it is NOT needed on reboots, only on binary rebuilds (rare).

### Fix C — re-grant Full Disk Access (GUI, user-only — TCC is SIP-protected)
The agent CANNOT toggle FDA (no CLI grants it; TCC.db can't be written even by root). The user must:

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Find **instar-attachments-sync** in the list. If present, toggle it **OFF then ON** (this re-records the current binary's signature). If the toggle doesn't take, click **–** to remove it, then **+** and add:
   `/Users/rolandcanyon/.instar/agents/Roland/.instar/bin/instar-attachments-sync`
3. Restart the watcher: `launchctl kickstart -k gui/$(id -u)/ai.instar.AttachmentsWatcher`
4. Verify the log shows `initial chatdb sync: relinked N file(s)` and NO `operation not permitted`.

Check the live TCC state (read-only): 
```bash
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
 "select client,auth_value from access where service='kTCCServiceSystemPolicyAllFiles' and client like '%attachments-sync%';"
# auth_value 2 = granted, 0 = DENIED
```

## Also-check (when links are fine but still no reply)
- **Server up?** `curl -s http://localhost:4040/health` — after a Mac reboot the server only starts on GUI login (see `[[known-reboot-login-required]]`).
- **Adapter session spawning?** `grep 'imessage→session' $AGENT/.instar/logs/server.log | tail`
- **`database disk image is malformed`** errors → transient WAL corruption; usually clears on the next adapter reconnect. Only act if it persists across restarts.
- **Sending** happens via `imessage-reply.sh → imsg send` from the Claude session (AppleScript perms don't propagate through LaunchAgent), not through the daemon.

## One-line summary
iMessage stopped after a reboot ⇒ the chat.db **-wal hardlink went stale** ⇒ run Fix A (or let the robust Go watcher self-heal) ⇒ if the watcher log says `operation not permitted`, re-grant Full Disk Access (Fix C).
