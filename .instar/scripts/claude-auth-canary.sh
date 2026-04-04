#!/bin/bash
# claude-auth-canary.sh — Quick check if Claude can authenticate.
# Returns 0 if auth works, 1 if expired.
# Used by health checks and the tmux keepalive cron.

CLAUDE="${1:-/Users/rolandcanyon/homebrew/bin/claude}"
RESULT=$("$CLAUDE" --dangerously-skip-permissions --model haiku -p "reply with OK" 2>&1 | head -5)

if echo "$RESULT" | grep -qi "OK"; then
  exit 0
else
  echo "$RESULT" >&2
  exit 1
fi
