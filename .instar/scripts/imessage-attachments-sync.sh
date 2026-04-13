#!/bin/bash
# imessage-attachments-sync.sh
#
# Mirrors files from ~/Library/Messages/Attachments/ to .instar/imessage/attachments/
# via hardlinks. Hardlinks share the inode, so once created, any process can
# read them — including the Roland LaunchDaemon, which has no FDA.
#
# This script itself needs FDA to READ ~/Library/Messages/Attachments.
# When run from a Terminal session (or a LaunchAgent whose binary has FDA),
# that grant propagates.
#
# Modes:
#   imessage-attachments-sync.sh             # one-shot sync + exit
#   imessage-attachments-sync.sh --watch     # continuous watch via fswatch (LaunchAgent mode)
#
# The --watch mode requires fswatch: brew install fswatch, and grant it FDA.

set -e

SRC_DIR="$HOME/Library/Messages/Attachments"
DEST_DIR="/Users/rolandcanyon/.instar/agents/Roland/.instar/imessage/attachments"
LOG="/Users/rolandcanyon/.instar/agents/Roland/.instar/logs/attachments-watcher.log"

mkdir -p "$DEST_DIR"
mkdir -p "$(dirname "$LOG")"

sync_once() {
    local new_count=0
    # Walk src dir, hardlink new files. The ${uuid:0:8}__ prefix disambiguates
    # same-named files across different message UUIDs.
    while IFS= read -r -d '' srcfile; do
        base=$(basename "$srcfile")
        case "$base" in .*) continue ;; esac
        parent_dir=$(dirname "$srcfile")
        uuid=$(basename "$parent_dir")
        dest_name="${uuid:0:8}__${base}"
        destfile="$DEST_DIR/$dest_name"
        if [ -e "$destfile" ]; then
            if [ "$(stat -f '%i' "$srcfile" 2>/dev/null)" = "$(stat -f '%i' "$destfile" 2>/dev/null)" ]; then
                continue
            fi
            rm -f "$destfile"
        fi
        if ln "$srcfile" "$destfile" 2>/dev/null; then
            new_count=$((new_count + 1))
        fi
    done < <(find "$SRC_DIR" -type f \
        \( -name '*.jpeg' -o -name '*.jpg' -o -name '*.png' -o -name '*.heic' \
           -o -name '*.mov' -o -name '*.mp4' -o -name '*.pdf' \
           -o -name '*.gif' -o -name '*.caf' \
           -o -name '*.m4a' -o -name '*.3gpp' \) \
        -print0 2>/dev/null)

    # Prune dead hardlinks (link count 1 = source gone)
    while IFS= read -r -d '' destfile; do
        if [ "$(stat -f '%l' "$destfile" 2>/dev/null)" = "1" ]; then
            rm -f "$destfile"
        fi
    done < <(find "$DEST_DIR" -type f -print0 2>/dev/null)

    if [ "$new_count" -gt 0 ]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) linked $new_count new" >> "$LOG"
    fi
}

if [ "$1" = "--watch" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) watcher starting (fswatch mode)" >> "$LOG"
    if ! command -v fswatch >/dev/null 2>&1; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) ERROR: fswatch not installed, falling back to 5s polling" >> "$LOG"
        sync_once
        while :; do
            sleep 5
            sync_once
        done
    fi

    # Initial sync
    sync_once

    # Event-driven with 0.5s debounce. Use --latency for batching — if 5 photos
    # arrive in one message, we sync once after the batch settles.
    exec fswatch --latency=0.5 --recursive "$SRC_DIR" | while read -r _event; do
        sync_once
    done
else
    # One-shot mode (can be called manually or from cron)
    sync_once
fi
