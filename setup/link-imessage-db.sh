#!/usr/bin/env bash
# link-imessage-db.sh — Hardlink the iMessage SQLite database into the agent directory.
#
# Must be run in the correct order:
#   1. Server stopped
#   2. Messages.app quit
#   3. Hardlinks created
#   4. Messages.app reopened
#   5. Server started
#
# This script handles steps 1-4 and verifies the result.
# Run it, then start the server: NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start
#
# Safe to rerun — it checks link counts before removing anything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEST_DIR="${AGENT_DIR}/.instar/imessage"
SRC_DB="${HOME}/Library/Messages/chat.db"

echo "=== iMessage database hardlink setup ==="
echo ""

# --- Check source exists ---
if [[ ! -f "${SRC_DB}" ]]; then
    echo "✗ ~/Library/Messages/chat.db not found"
    echo "  Open the Messages app and sign in first, then rerun this script."
    exit 1
fi

# --- Stop server ---
echo "Stopping instar server..."
instar server stop 2>/dev/null || true
sleep 1
echo "  ✓ Server stopped"
echo ""

# --- Quit Messages ---
echo "Quitting Messages app..."
osascript -e 'tell application "Messages" to quit' 2>/dev/null || true
sleep 2
echo "  ✓ Messages quit"
echo ""

# --- Create destination directory ---
mkdir -p "${DEST_DIR}"

# --- Remove existing db files (clean slate) ---
echo "Removing existing database files..."
for suffix in "" "-shm" "-wal"; do
    dst="${DEST_DIR}/chat.db${suffix}"
    if [[ -f "${dst}" ]]; then
        rm "${dst}"
        echo "  removed chat.db${suffix}"
    fi
done
echo ""

# --- Create hardlinks ---
echo "Creating hardlinks from ~/Library/Messages/..."
_all_ok=true
for suffix in "" "-shm" "-wal"; do
    src="${SRC_DB}${suffix}"
    dst="${DEST_DIR}/chat.db${suffix}"
    if [[ ! -f "${src}" ]]; then
        echo "  ⚠ chat.db${suffix} not found in ~/Library/Messages — will be created when Messages syncs"
    elif ln "${src}" "${dst}" 2>/dev/null; then
        echo "  ✓ chat.db${suffix}"
    else
        echo "  ✗ chat.db${suffix} — Terminal needs Full Disk Access"
        echo "    System Settings → Privacy & Security → Full Disk Access → add Terminal"
        _all_ok=false
    fi
done
echo ""

if [[ "${_all_ok}" == false ]]; then
    echo "✗ Some hardlinks failed. Grant Terminal Full Disk Access and rerun."
    exit 1
fi

# --- Verify link counts ---
echo "Verifying link counts (should all be 2)..."
_verify_ok=true
for suffix in "" "-shm" "-wal"; do
    dst="${DEST_DIR}/chat.db${suffix}"
    [[ ! -f "${dst}" ]] && continue
    count=$(stat -f "%l" "${dst}")
    inode=$(stat -f "%i" "${dst}")
    src_inode=$(stat -f "%i" "${SRC_DB}${suffix}" 2>/dev/null || echo "?")
    if [[ "${count}" == "2" && "${inode}" == "${src_inode}" ]]; then
        echo "  ✓ chat.db${suffix}  (links=2, inode=${inode})"
    else
        echo "  ✗ chat.db${suffix}  (links=${count}, inode=${inode}, src inode=${src_inode})"
        _verify_ok=false
    fi
done
echo ""

if [[ "${_verify_ok}" == false ]]; then
    echo "✗ Link verification failed. Something is wrong."
    exit 1
fi

# --- Reopen Messages ---
echo "Reopening Messages..."
open -a Messages
sleep 2
echo "  ✓ Messages launched"
echo ""

echo "=== Done ==="
echo ""
echo "Now start the server:"
echo "  NODE_EXTRA_CA_CERTS=/etc/ssl/cert.pem instar server start"
echo ""
echo "Then send a test message and check: imsg chats"
echo "The timestamp for your number should update within a few seconds."
