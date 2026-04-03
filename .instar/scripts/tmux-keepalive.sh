#!/bin/bash
# tmux-keepalive.sh — Independent watchdog for tmux server.
# Runs via cron every 2 minutes. If tmux is dead, restarts it.
# This is intentionally outside the instar stack — if the server,
# scheduler, or Claude are all broken, this still works.

TMUX="/opt/homebrew/bin/tmux"

if ! "$TMUX" ls &>/dev/null; then
  "$TMUX" new-session -d -s Roland-keepalive
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) tmux restarted" >> /Users/rolandcanyon/.instar/agents/Roland/.instar/logs/tmux-keepalive.log
fi
