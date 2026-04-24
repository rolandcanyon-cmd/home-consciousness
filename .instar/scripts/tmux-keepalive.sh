#!/bin/bash
# tmux-keepalive.sh — Independent watchdog for tmux + Claude auth.
# Runs via cron every 2 minutes. Checks two things:
# 1. Is tmux alive? If not, restart it.
# 2. Can Claude authenticate? If not, alert via imsg.
#
# This is intentionally outside the instar stack — if the server,
# scheduler, or Claude are all broken, this still works.

TMUX="/opt/homebrew/bin/tmux"
IMSG="/Users/rolandcanyon/homebrew/bin/imsg"
CLAUDE="/Users/rolandcanyon/homebrew/bin/claude"
LOGDIR="/Users/rolandcanyon/.instar/agents/Roland/.instar/logs"
PHONE="+14084424360"
AUTH_ALERT_FILE="/tmp/instar-claude-auth-alert-sent"

# Ensure log directory exists
mkdir -p "$LOGDIR"

# 1. tmux keepalive
if ! "$TMUX" ls &>/dev/null; then
  "$TMUX" new-session -d -s Roland-keepalive
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) tmux restarted" >> "$LOGDIR/tmux-keepalive.log"
fi

# 2. Claude auth canary (check every 10 minutes, not every 2)
# Use a timestamp file to throttle checks
CANARY_CHECK="/tmp/instar-canary-last-check"
NOW=$(date +%s)
LAST_CHECK=0
[ -f "$CANARY_CHECK" ] && LAST_CHECK=$(cat "$CANARY_CHECK")
ELAPSED=$((NOW - LAST_CHECK))

if [ "$ELAPSED" -ge 3600 ]; then
  echo "$NOW" > "$CANARY_CHECK"

  RESULT=$("$CLAUDE" --dangerously-skip-permissions --model haiku -p "reply with just OK" 2>&1 | head -3)

  if echo "$RESULT" | grep -qi "OK"; then
    # Auth works — clear alert flag
    rm -f "$AUTH_ALERT_FILE"
  else
    # Auth failed — send ONE alert (don't spam)
    if [ ! -f "$AUTH_ALERT_FILE" ]; then
      "$IMSG" send --to "$PHONE" --text "⚠️ Roland auth expired — I can receive messages but can't process them. Please open Claude Code and run /login to re-authenticate." --service imessage 2>/dev/null
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) auth alert sent" > "$AUTH_ALERT_FILE"
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Claude auth failed — alert sent" >> "$LOGDIR/tmux-keepalive.log"
    fi
  fi
fi
