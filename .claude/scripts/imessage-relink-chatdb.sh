#!/bin/bash
# imessage-relink-chatdb.sh
#
# Fixes the #1 cause of "iMessage stopped responding" on this fork:
# the chat.db WAL/SHM hardlinks going STALE (usually after a reboot).
#
# WHY THIS EXISTS (the design):
#   The node daemon deliberately runs WITHOUT Full Disk Access. It reads the
#   Messages database through HARDLINKS in .instar/imessage/ (a non-TCC-protected
#   dir). SQLite keeps recent messages in the -wal sidecar; that sidecar's inode
#   is RECREATED whenever macOS Messages restarts (e.g. every reboot). When that
#   happens the private hardlink points at a dead inode, so the daemon reads only
#   stale checkpointed data and never sees new texts. IMessageAdapter.ensureChatDbHardlink()
#   is supposed to re-link at startup, but that requires FDA on node — and node's
#   FDA is lost on every node version bump. This script re-links from a process
#   that HAS FDA (your Terminal / an FDA-granted shell), which is the reliable path.
#
# SAFE: only unlinks/recreates the PRIVATE hardlinks under .instar/imessage/.
# It NEVER modifies ~/Library/Messages (hardlinking + unlinking a link never
# touches the live file's data).
#
# REQUIRES: must be run from a process WITH Full Disk Access (Terminal, or the
# Claude Code session's shell if that has FDA). If it can't read ~/Library/Messages
# it will say so and exit non-zero — that means FDA is the real problem (see the skill).
#
# Usage:  bash .claude/scripts/imessage-relink-chatdb.sh [--restart]
#   --restart  also restart the server so the adapter re-opens the fresh links.

set -euo pipefail

MSG="$HOME/Library/Messages"
AGENT_DIR="${AGENT_DIR:-$HOME/.instar/agents/Roland}"
PRIV="$AGENT_DIR/.instar/imessage"

# --- FDA preflight: can we actually read the protected dir? ---
if ! sqlite3 "$MSG/chat.db" "select 1;" >/dev/null 2>&1; then
  echo "❌ Cannot read $MSG/chat.db — this shell lacks Full Disk Access."
  echo "   Run this from a Terminal that has FDA (System Settings › Privacy & Security ›"
  echo "   Full Disk Access), or grant FDA to the node binary. See /imessage-doctor."
  exit 1
fi

mkdir -p "$PRIV"

echo "=== relinking chat.db + WAL + SHM (live → private) ==="
changed=0
for n in chat.db chat.db-wal chat.db-shm; do
  if [ ! -e "$MSG/$n" ]; then
    echo "  $n: not present in live (skipping)"
    continue
  fi
  live_ino=$(stat -f %i "$MSG/$n")
  priv_ino=$(stat -f %i "$PRIV/$n" 2>/dev/null || echo "MISSING")
  if [ "$live_ino" = "$priv_ino" ]; then
    echo "  $n: already current (inode $live_ino)"
  else
    rm -f "$PRIV/$n"
    ln "$MSG/$n" "$PRIV/$n"
    echo "  $n: RELINKED ($priv_ino → $live_ino)"
    changed=1
  fi
done

echo
echo "=== verify: private path sees live data ==="
live_latest=$(sqlite3 "$MSG/chat.db"  "select max(date) from message;")
priv_latest=$(sqlite3 "$PRIV/chat.db" "select max(date) from message;")
if [ "$live_latest" = "$priv_latest" ]; then
  echo "  ✅ private path is CURRENT (matches live)"
else
  echo "  ⚠️  mismatch: live=$live_latest priv=$priv_latest (SQLite may need a beat; re-run)"
fi

if [ "${1:-}" = "--restart" ]; then
  echo
  echo "=== restarting server so the adapter re-opens the links ==="
  launchctl kickstart -k "gui/$(id -u)/ai.instar.Roland"
  for i in $(seq 1 30); do
    if curl -s -m 3 http://localhost:4040/health 2>/dev/null | grep -q uptime; then
      echo "  ✅ server back up"; break
    fi
    sleep 1 2>/dev/null || true
  done
fi

echo
if [ "$changed" = "1" ]; then
  echo "Done — links were stale and are now fixed. Send a test iMessage to confirm."
else
  echo "Done — links were already current. If iMessage still isn't responding, the"
  echo "problem is elsewhere: check /imessage-doctor (adapter connected? session spawning?)."
fi
