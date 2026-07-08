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

## Root cause #2 — STALE DUPLICATE `IMDPersistenceAgent` deadlocks the message store (2026-07-08)

**Symptom:** Messages.app is open and signed in, the conversation shows then *clears*, and `chat.db` is **completely frozen** — the `-wal` is byte-for-byte identical (same size, same mtime) for tens of minutes. No new rows, not even for messages you SEND. Hardlinks are perfect, Roland's adapter is connected. It looks like iMessage is signed out; it isn't.

**Cause:** a macOS **logout/login leaves orphaned `imagent` + `IMDPersistenceAgent` processes behind**. A stale `IMDPersistenceAgent` opens `chat.db` and holds it without writing, so the live agent can never persist. The WAL freeze timestamp matches the stale agent's start time *exactly* — that's the tell.

**Diagnose:**
```bash
# duplicate daemons with DIFFERENT start times = the bug
ps -o pid,lstart,comm -p $(pgrep -f "imagent|IMDPersistenceAgent" | tr '\n' ',' | sed 's/,$//')
# who holds the frozen WAL?
lsof ~/Library/Messages/chat.db-wal | grep IMDPers
# WAL frozen? (same size+mtime across minutes = no writes at all)
stat -f "%Sm %z" -t "%H:%M:%S" ~/Library/Messages/chat.db-wal
```
Compare the WAL's frozen mtime against the stale agent's `lstart`. If they match, that agent is the deadlock.

**Fix:**
```bash
osascript -e 'tell application "Messages" to quit'; sleep 2
pkill -9 -f "IMDPersistenceAgent"; pkill -9 -f "IMCore.framework/imagent"
sleep 5; open -a Messages
# verify: WAL size starts changing within ~20s, and new rows appear
```

**Important:** a **logout/login does NOT clear these orphans** (they can even survive `kill -9` from the new session — orphans from the logged-out session persist). Only a **real Mac reboot** guarantees a clean single set. Always check `sysctl -n kern.boottime` — a user saying "I restarted" often means they restarted Messages or logged out/in, not the machine.

**NOT Instar:** verified by fully unloading the Roland server and removing every hardlink — the DB stayed frozen. Roland's read-write handle on chat.db is not the blocker.

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

## Triage order (do this first)

1. **Is the Roland server even up?** `curl -s localhost:4040/health`. If it crash-loops with `[single-instance] lock held by FOREIGN host`, a stale `.instar/local/server-instance.lock` is the cause (it used to be git-tracked; now gitignored). Clear it if its pid is dead, restart.
2. **Is `chat.db` FROZEN?** Compare `stat` on `chat.db-wal` twice, 30s apart. Frozen (identical size+mtime) + no new rows ⇒ **Root cause #2** (stale `IMDPersistenceAgent`) — Messages isn't writing at all; nothing to do with hardlinks.
3. **Is `chat.db` moving but Roland sees stale data?** ⇒ the **-wal hardlink is stale** (Root cause #1) ⇒ Fix A / the Go watcher.
4. Watcher log says `operation not permitted` ⇒ re-grant Full Disk Access (Fix C).

## One-line summary
iMessage silent ⇒ first check the server is up, then check whether `chat.db` is **frozen** (⇒ stale `IMDPersistenceAgent`, kill the daemons — root cause #2) or **moving but unseen** (⇒ stale `-wal` hardlink, Fix A / Go watcher — root cause #1).
