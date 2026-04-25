#!/bin/bash
# log-rotate.sh — daily log maintenance for Roland.
#
# - Truncates live logs (server-launchd.log/err, meridian.log/err, attachments-watcher.log/err)
#   to last 20 MB using tail if they exceed 20 MB.
# - Deletes activity-YYYY-MM-DD.jsonl files older than 30 days.
# - Deletes old server/meridian log rotations if any.
#
# Runs from cron: 0 3 * * * /path/to/log-rotate.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="$(cd "${SCRIPT_DIR}/../.." && pwd)/logs"
MAX_SIZE_MB=20
RETAIN_DAYS=30

cd "$LOGDIR" || exit 0

# Truncate live logs to last N MB if oversized (keep tail, not head — recent matters)
for f in server-launchd.log server-launchd.err meridian.log meridian.err attachments-watcher.log attachments-watcher.err tmux-keepalive.log; do
    [ -f "$f" ] || continue
    size_kb=$(stat -f '%z' "$f" 2>/dev/null || echo 0)
    size_mb=$((size_kb / 1024 / 1024))
    if [ "$size_mb" -gt "$MAX_SIZE_MB" ]; then
        # Take last 2 MB of content, overwrite original
        tail -c $((2 * 1024 * 1024)) "$f" > "$f.tmp" && mv "$f.tmp" "$f"
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) rotated $f (was ${size_mb}MB, kept last 2MB)" >> log-rotate.log
    fi
done

# Delete activity-YYYY-MM-DD.jsonl files older than retention
find . -maxdepth 1 -name 'activity-*.jsonl' -mtime +"$RETAIN_DAYS" -delete 2>/dev/null || true

# Delete rotated log backups older than retention
find . -maxdepth 1 \( -name '*.log.old' -o -name '*.err.old' -o -name '*.gz' \) -mtime +"$RETAIN_DAYS" -delete 2>/dev/null || true

exit 0
