#!/bin/bash
# tmux-keepalive.sh — Independent watchdog for tmux + Claude auth.
# Runs via cron every 2 minutes. Checks two things:
# 1. Is tmux alive? If not, restart it.
# 2. Can Claude authenticate? If not, alert via imsg.
#
# This is intentionally outside the instar stack — if the server,
# scheduler, or Claude are all broken, this still works.

TMUX="/opt/homebrew/bin/tmux"
IMSG="$(which imsg 2>/dev/null || echo "$HOME/homebrew/bin/imsg")"
CLAUDE="$(which claude 2>/dev/null || echo "$HOME/homebrew/bin/claude")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AGENT_NAME="$(basename "$AGENT_DIR")"
LOGDIR="${AGENT_DIR}/logs"
AUTH_ALERT_FILE="/tmp/instar-claude-auth-alert-sent"

# Read phone number from instar config
PHONE=$(python3 -c "import json; d=json.load(open('${AGENT_DIR}/.instar/config.json')); print(d.get('imessage',{}).get('userPhone',''))" 2>/dev/null || echo "")

# Ensure log directory exists
mkdir -p "$LOGDIR"

# 1. tmux keepalive
if ! "$TMUX" ls &>/dev/null; then
  "$TMUX" new-session -d -s "${AGENT_NAME}-keepalive"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) tmux restarted" >> "$LOGDIR/tmux-keepalive.log"
fi

# 2. Claude auth canary (check every 60 minutes, not every 2)
CANARY_CHECK="/tmp/instar-canary-last-check"
NOW=$(date +%s)
LAST_CHECK=0
[ -f "$CANARY_CHECK" ] && LAST_CHECK=$(cat "$CANARY_CHECK")
ELAPSED=$((NOW - LAST_CHECK))

if [ "$ELAPSED" -ge 3600 ]; then
  echo "$NOW" > "$CANARY_CHECK"

  AGENT_CONFIG="${AGENT_DIR}/.instar/config.json"
  CANARY_API_KEY=$(python3 -c "import json,sys; d=json.load(open('$AGENT_CONFIG')); print(d.get('sessions',{}).get('anthropicApiKey',''))" 2>/dev/null)

  # OAuth tokens (sk-ant-oat...) go in CLAUDE_CODE_OAUTH_TOKEN; API keys (sk-ant-api03...) go in ANTHROPIC_API_KEY
  if echo "$CANARY_API_KEY" | grep -q "^sk-ant-o"; then
    RESULT=$(CLAUDE_CODE_OAUTH_TOKEN="$CANARY_API_KEY" "$CLAUDE" --dangerously-skip-permissions --model haiku -p "reply with just OK" 2>&1 | head -3)
  else
    RESULT=$(ANTHROPIC_API_KEY="$CANARY_API_KEY" "$CLAUDE" --dangerously-skip-permissions --model haiku -p "reply with just OK" 2>&1 | head -3)
  fi

  if echo "$RESULT" | grep -qi "OK"; then
    rm -f "$AUTH_ALERT_FILE"
  else
    if [ ! -f "$AUTH_ALERT_FILE" ] && [ -n "$PHONE" ]; then
      "$IMSG" send --to "$PHONE" --text "⚠️ ${AGENT_NAME} auth failed — Claude canary check returned an error. Check the tmux-keepalive log for details." --service imessage 2>/dev/null
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) auth alert sent" > "$AUTH_ALERT_FILE"
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Claude auth failed — alert sent" >> "$LOGDIR/tmux-keepalive.log"
    fi
  fi
fi
