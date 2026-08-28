---
name: imessage-doctor
description: Diagnose and fix iMessage not responding, not receiving, or not replying on macOS Instar agents. Covers the stale WAL-hardlink root cause, the deadlocked IMDPersistenceAgent, and the tmux/terminal Automation (TCC) grant that silently breaks sending after a Homebrew upgrade. Trigger words - imessage not working, imessage not responding, not getting imessage, imessage stopped, imessage broken, no reply, chat.db, apple events not authorized, -1743.
license: MIT
metadata:
  author: sagemindai
  version: "1.1"
  homepage: https://instar.sh
---

# imessage-doctor — diagnose & repair the macOS iMessage path

Use this when iMessage isn't responding, isn't receiving, or "worked yesterday, broke after an
update/reboot." It encodes the real architecture so you don't re-diagnose from scratch.

Set these once per session:

```bash
AGENT="$(cd "$(dirname "${BASH_SOURCE:-$PWD}")" && pwd)"   # or just: AGENT=/path/to/.instar/agents/<Name>
MSG="$HOME/Library/Messages"
AUTH=$(python3 -c "import json;print(json.load(open('$AGENT/.instar/config.json')).get('authToken',''))")
```

## Split the problem in two FIRST

iMessage has two independent halves, and they fail for completely different reasons:

| Half | Mechanism | Fails because |
|---|---|---|
| **RECEIVE** | daemon reads `chat.db` via hardlinks | stale `-wal` hardlink (#1) or frozen DB (#2) |
| **SEND** | `imsg`/AppleScript → Messages.app | Automation (AppleEvents) TCC grant (#3) |

**Do not skip this triage.** "Roland isn't responding" is usually SEND, not RECEIVE — the message
arrives, a session spawns, an ack goes out, and then the reply silently fails. Check both:

```bash
# RECEIVE healthy? live and private DBs must agree
echo -n "live : "; sqlite3 "$MSG/chat.db" "select datetime(max(date)/1000000000+978307200,'unixepoch','localtime') from message;"
echo -n "priv : "; sqlite3 "$AGENT/.instar/imessage/chat.db" "select datetime(max(date)/1000000000+978307200,'unixepoch','localtime') from message;"

# SEND healthy? this is the decisive one-liner
imsg send --to "+1XXXXXXXXXX" --text "probe" ; echo "exit=$?"
```

An exit of 0 from your *interactive* shell does **not** prove send works for the agent —
see #3, the grant is per-ancestor-process.

## The architecture (explains every RECEIVE failure)

The node server daemon **deliberately does NOT have Full Disk Access (FDA)**. macOS protects
`~/Library/Messages/` behind TCC, and node's FDA grant is lost on every node version bump — so
relying on it is fragile. Instead the daemon reads through **hardlinks** in a non-protected dir:

```
~/Library/Messages/chat.db      ──hardlink──▶  .instar/imessage/chat.db
~/Library/Messages/chat.db-wal  ──hardlink──▶  .instar/imessage/chat.db-wal   ← the critical one
~/Library/Messages/chat.db-shm  ──hardlink──▶  .instar/imessage/chat.db-shm
```

`dbPath` in `config.json` points at `.instar/imessage/chat.db` — **correct and intentional, not a
hack.** Do NOT "fix" it by pointing at the live path; node lacks FDA and fails with
`unable to open database file`.

**Why the -wal file is everything:** SQLite (Messages.app) writes new messages to the `-wal`
sidecar; they only land in `chat.db` on an irregular *checkpoint*. A reader sees new messages only
if it reads the **live** `-wal`. The hardlink shares the live inode — UNTIL macOS Messages
recreates the `-wal` with a **new inode** (every machine reboot / Messages restart). Then the
private hardlink points at a dead inode and iMessage **silently stops seeing anything new.**

A plain server restart does NOT recreate the WAL, so it does not break the links. Only a machine
reboot / Messages restart does.

Two FDA-holding processes maintain the hardlinks:
- **`instar-attachments-sync`** (Go, LaunchAgent `ai.instar.AttachmentsWatcher`) — re-links
  chat.db/wal/shm every 2s, so reboots self-heal.
- `IMessageAdapter.ensureChatDbHardlink()` — startup best-effort; needs FDA on node (usually absent).

## Fast diagnosis

```bash
# 1) adapter connected?
curl -s -H "Authorization: Bearer $AUTH" http://localhost:4040/imessage/status   # want {"state":"connected"}

# 2) THE key RECEIVE check — priv older than live ⇒ stale WAL hardlink
# (see the two sqlite3 lines above)

# 3) confirm via inodes (the wal one differs when broken)
for n in chat.db chat.db-wal chat.db-shm; do
  printf "%-14s live=%s priv=%s\n" "$n" "$(stat -f %i "$MSG/$n" 2>/dev/null)" "$(stat -f %i "$AGENT/.instar/imessage/$n" 2>/dev/null)"
done

# 4) watcher healthy? "operation not permitted" here = FDA problem
tail -5 "$AGENT/.instar/logs/attachments-watcher.log"

# 5) did a session spawn and did it reply?
grep -i 'imessage' "$AGENT/logs/server.log" | tail -30
```

Step 5 is the one people skip. `[imessage→session] Injecting…` followed by `Sent immediate ack`
and then **nothing** is the signature of a SEND failure (#3), not a receive failure.

---

## Root cause #1 — stale `-wal` hardlink

**Symptom:** `priv` timestamp older than `live`; inodes differ. Agent sees only stale checkpointed
data and silently stops responding to anything new.

**Fix A — relink now** (needs a shell WITH Full Disk Access):

```bash
bash "$AGENT/.claude/scripts/imessage-relink-chatdb.sh" --restart
```

If it prints `this shell lacks Full Disk Access`, FDA is the real problem → Fix C.

**Fix B — durable self-heal:** ensure the `instar-attachments-sync` watcher is running; it re-links
every 2s. After ANY rebuild of that binary macOS flips its FDA grant to DENIED
(`operation not permitted` in the log) → Fix C.

**Fix C — re-grant Full Disk Access** (GUI, user-only; TCC is SIP-protected):
System Settings → Privacy & Security → Full Disk Access → find `instar-attachments-sync`,
toggle OFF then ON (or remove with **–** and re-add with **+**), then:

```bash
launchctl kickstart -k gui/$(id -u)/ai.instar.AttachmentsWatcher
```

Verify (read-only): `auth_value` 2 = granted, 0 = denied.

```bash
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
 "select client,auth_value from access where service='kTCCServiceSystemPolicyAllFiles' and client like '%attachments-sync%';"
```

---

## Root cause #2 — stale duplicate `IMDPersistenceAgent` deadlocks the store

**Symptom:** Messages.app is open and signed in, the conversation shows then *clears*, and
`chat.db` is **completely frozen** — the `-wal` is byte-for-byte identical for tens of minutes. No
new rows, not even for messages you SEND. Hardlinks are perfect and the adapter is connected.
Looks like iMessage is signed out; it isn't.

**Cause:** a macOS logout/login leaves orphaned `imagent` + `IMDPersistenceAgent` processes. A
stale `IMDPersistenceAgent` holds `chat.db` open without writing, so the live agent can never
persist. **The WAL freeze timestamp matches the stale agent's start time exactly** — that's the tell.

```bash
ps -o pid,lstart,comm -p $(pgrep -f "imagent|IMDPersistenceAgent" | tr '\n' ',' | sed 's/,$//')
lsof ~/Library/Messages/chat.db-wal | grep IMDPers
stat -f "%Sm %z" -t "%H:%M:%S" ~/Library/Messages/chat.db-wal    # run twice, 30s apart
```

**Fix:**

```bash
osascript -e 'tell application "Messages" to quit'; sleep 2
pkill -9 -f "IMDPersistenceAgent"; pkill -9 -f "IMCore.framework/imagent"
sleep 5; open -a Messages
# verify: WAL size changes within ~20s and new rows appear
```

A logout/login does **NOT** clear these orphans — only a real reboot guarantees a clean set.
Always check `sysctl -n kern.boottime`; "I restarted" often means Messages or a logout, not the machine.

---

## Root cause #3 — Automation (AppleEvents) TCC grant lost after a Homebrew upgrade

**This one breaks SEND only, and it is invisible in every receive-side check.**

**Symptom:** messages arrive fine, a session spawns, the `...` ack goes out — and the real reply
never lands. The session transcript shows:

```
appleScriptFailure("execution error: Not authorized to send Apple events to Messages. (-1743)")
```

Meanwhile `imsg send` from *your own terminal* works perfectly. That contradiction is the tell.

**Cause:** macOS attributes AppleEvents permission to the **responsible ancestor process**, not to
`imsg`. For agent sessions that ancestor is **tmux**. The grant is keyed to the tmux binary's
**exact absolute path**, e.g. `/opt/homebrew/Cellar/tmux/3.6a/bin/tmux`. A
`brew upgrade tmux` installs a new Cellar path (`…/3.7c/bin/tmux`), which TCC treats as a brand-new
client with **no** grant — and a headless LaunchAgent context cannot show a consent prompt, so it
records a **denial (auth_value 0)** that never re-prompts. Sending dies silently and permanently.

The same applies to any terminal/multiplexer upgrade in the ancestry.

**Diagnose:**

```bash
# which tmux is actually running the agent's sessions?
for p in $(pgrep -x tmux); do lsof -p $p 2>/dev/null | awk '$4=="txt"{print $NF; exit}'; done

# the grants — 2 = allowed, 0 = DENIED
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
 "select client, indirect_object_identifier, auth_value from access where service='kTCCServiceAppleEvents';"
```

A row for the **old** tmux version with `2` plus a row for the **current** version with `0` is a
positive identification. Cross-check the timing: `ls -la /opt/homebrew/Cellar/tmux/` shows the
upgrade date, and it will match the day iMessage replies stopped.

**Prove it in 30 seconds** — same command, same user, only the ancestor differs:

```bash
TM=/opt/homebrew/bin/tmux
$TM -L probe new-session -d -s p
$TM -L probe send-keys -t p 'imsg send --to "+1XXXXXXXXXX" --text "probe" > /tmp/p.out 2>&1' Enter
sleep 6; cat /tmp/p.out; $TM -L probe kill-server
```

Works in your shell, `-1743` under tmux ⇒ confirmed.

**Fix (preferred, GUI — durable and surgical):**
System Settings → Privacy & Security → **Automation** → find **tmux** → enable **Messages**.

**Fix (agent-side, no GUI):** flip the single denied row. Back up first.

```bash
TCC="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
cp "$TCC" "/tmp/TCC.db.bak-$(date +%s)"
sqlite3 "$TCC" "update access set auth_value=2
  where service='kTCCServiceAppleEvents'
    and client='/opt/homebrew/Cellar/tmux/<VERSION>/bin/tmux'
    and indirect_object_identifier='com.apple.MobileSMS';"
```

⚠️ **A running tmux server caches its TCC verdict.** After the grant change, a *fresh* tmux server
sends fine while the *existing* one still returns `-1743`. You MUST bounce it:

```bash
tmux kill-server                                  # recycles agent sessions; they respawn
launchctl kickstart -k gui/$(id -u)/ai.instar.<AgentName>
```

Then re-probe. If the probe passes but the agent still doesn't reply, the sessions predate the
bounce — restart them.

**This recurs on every tmux upgrade.** Treat a silent send failure right after any
`brew upgrade` as this root cause until disproven, and consider pinning tmux
(`brew pin tmux`) so the grant survives.

---

## Also-check (links fine, still no reply)

- **Server up?** `curl -s http://localhost:4040/health`. After a reboot the server only starts on
  GUI login. If it crash-loops with `[single-instance] lock held by FOREIGN host`, clear the stale
  `.instar/local/server-instance.lock` when its pid is dead, then restart.
- **Session spawning?** `grep 'imessage→session' "$AGENT/logs/server.log" | tail`
- **`database disk image is malformed`** → transient WAL corruption; usually clears on reconnect.
- **Verify sends actually landed**, don't trust exit codes:

```bash
sqlite3 "$MSG/chat.db" "select datetime(date/1000000000+978307200,'unixepoch','localtime'),
  is_from_me, is_sent, is_delivered, error from message order by date desc limit 5;"
```

Outgoing rows show empty `text` because modern macOS stores the body in `attributedBody` — that is
normal and **not** a fault. Judge by `is_sent` / `is_delivered` / `error`.

## Triage order

1. **Server up?** → `/health`.
2. **`chat.db` FROZEN?** (WAL identical across 30s) ⇒ **#2**, stale `IMDPersistenceAgent`.
3. **DB moving but agent sees stale data?** ⇒ **#1**, stale `-wal` hardlink.
4. **Receive fine, ack sent, no reply?** ⇒ **#3**, Automation TCC grant after a tmux upgrade.
5. Watcher log `operation not permitted` ⇒ re-grant Full Disk Access (Fix C).

## One-line summary

iMessage silent ⇒ check the server is up, then decide whether it's **RECEIVE** (frozen DB ⇒ stale
`IMDPersistenceAgent`; or moving-but-unseen ⇒ stale `-wal` hardlink) or **SEND** (ack goes out but
no reply ⇒ tmux lost its Automation grant to Messages after a Homebrew upgrade).
