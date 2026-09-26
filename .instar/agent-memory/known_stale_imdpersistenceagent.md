---
name: known-stale-imdpersistenceagent
description: Frozen chat.db (iMessage silent) caused by orphaned duplicate IMDPersistenceAgent after logout/login — kill the daemons
metadata: 
  node_type: memory
  type: project
  originSessionId: 30164ac5-1517-43cb-bb47-5b01b51408c9
---

**Symptom:** iMessage silent. Messages.app open + signed in, conversation shows then **clears**. `~/Library/Messages/chat.db-wal` is **byte-for-byte frozen** (same size AND mtime for tens of minutes), no new rows even for messages you SEND. Roland's adapter connected, hardlinks perfect. Looks like iMessage is signed out — it isn't.

**Root cause:** a macOS **logout/login leaves orphaned `imagent` + `IMDPersistenceAgent` processes**. A stale `IMDPersistenceAgent` holds `chat.db` open without writing, deadlocking the store so the live agent can never persist. **The WAL's frozen mtime matches the stale agent's start time exactly** — that's the tell.

**Diagnose:** `ps -o pid,lstart,comm -p $(pgrep -f "imagent|IMDPersistenceAgent" | tr '\n' ',' | sed 's/,$//')` → duplicates with different start times. `lsof ~/Library/Messages/chat.db-wal | grep IMDPers` → who holds it.

**Fix:** quit Messages, `pkill -9 -f IMDPersistenceAgent; pkill -9 -f "IMCore.framework/imagent"`, wait 5s, `open -a Messages`. WAL starts moving within ~20s.

**Critical gotchas:**
- **A logout/login does NOT clear the orphans** — they can survive `kill -9` from the new session. Only a **real reboot** guarantees one clean set.
- **Always verify a claimed reboot**: `sysctl -n kern.boottime`. On 2026-07-08 the user said "restarted" but the Mac had been up 104h — they'd restarted Messages, not the machine. That check redirected the whole diagnosis.
- **Instar is NOT the cause** — proven by fully unloading the Roland server and removing every hardlink; the DB stayed frozen. Roland's read-write handle on chat.db is not a blocker. Don't chase the hardlinks when the WAL is frozen.

**Distinguish from the OTHER root cause** ([[known-stale-hostname-lock]] is a third, separate one):
- chat.db **frozen** (no writes at all) → this bug (stale daemon).
- chat.db **moving but Roland sees stale data** → stale `-wal` hardlink → `/imessage-doctor` Fix A.

Full triage lives in the `/imessage-doctor` skill. Resolved 2026-07-08; verified end-to-end (inbound "Test3" 16:05:09 → Roland reply 16:05:10).
