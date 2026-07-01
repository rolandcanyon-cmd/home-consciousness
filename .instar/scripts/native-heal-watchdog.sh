#!/bin/bash
# Roland — Node-Pin Enforcement + Native-Degradation Self-Heal Watchdog
#
# WHY THIS EXISTS  (root cause, established 2026-06-30)
#   This machine has TWO Homebrew installs owned by two macOS accounts:
#     - ~/homebrew  (user rolandcanyon)  node v25.8.2  ← VERIFIED-GOOD for the server
#     - /opt/homebrew (user adriancockcroft) node v26.4.0 ← CRASHES the full server
#       ("libc++abi: mutex lock failed: Invalid argument", EX_CONFIG crash-loop),
#       even though every native module require()s OK under it in isolation.
#   instar-boot.cjs has a node-symlink self-heal that, on a TRANSIENT post-reboot
#   better-sqlite3 load failure, searches candidates and PREFERS /opt/homebrew —
#   and its only test is "can this node load better-sqlite3?", which 26.4.0 PASSES
#   (N-API) before going on to crash the server. So after a macOS upgrade + reboot
#   the symlink can flip 25.8.2 -> 26.4.0 and the agent comes up broken.
#
#   This watchdog ENFORCES the good-node pin: if .instar/bin/node has drifted off
#   the good node, it repoints it and bounces the agent once. It also bounces once
#   if the server is up but degraded specifically from the SQLite/native binding
#   (a fresh process recovers cleanly). It is bounded by a cooldown + an hourly cap
#   and it ONLY restarts when it took a corrective action — it never blindly races
#   launchd/the fleet watchdog on a plain "server down".
#
#   AGENT-OWNED (not fleet-managed) so instar updates won't clobber it.
#
# Usage: native-heal-watchdog.sh [--dry-run] [--verbose]

set -uo pipefail

AGENT_DIR="/Users/rolandcanyon/.instar/agents/Roland"
PORT=4040
LABEL="ai.instar.Roland"
UID_NUM="$(id -u)"

# The verified-good node. The stable ~/homebrew brew symlink (auto-follows that
# brew's node) — NOT /opt/homebrew, whose node crashes this server. If a future
# brew upgrade moves ~/homebrew off a working node, revisit this pin.
GOOD_NODE="/Users/rolandcanyon/homebrew/bin/node"
NODE_SYMLINK="$AGENT_DIR/.instar/bin/node"

STATE_DIR="$AGENT_DIR/.instar/state"
LOG_FILE="$AGENT_DIR/.instar/logs/native-heal-watchdog.log"
LAST_RESTART_FILE="$STATE_DIR/native-heal-last-restart"
RESTART_LOG="$STATE_DIR/native-heal-restart-window"   # newline-separated epochs

COOLDOWN_SECONDS=180       # min seconds between our own restarts
MAX_RESTARTS_PER_HOUR=4    # give up (just log) past this — never loop forever
BOOT_WAIT_SECONDS=150      # how long to wait for the server to start responding

DRY_RUN=false; VERBOSE=false
for a in "$@"; do case "$a" in --dry-run) DRY_RUN=true;; --verbose) VERBOSE=true;; esac; done

mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"
log() { local m="[$(date '+%Y-%m-%d %H:%M:%S')] $1"; echo "$m" >> "$LOG_FILE"; $VERBOSE && echo "$m"; }
now() { date +%s; }

# --- restart guard ----------------------------------------------------------
can_restart() {
  local last=0; [ -r "$LAST_RESTART_FILE" ] && last="$(cat "$LAST_RESTART_FILE" 2>/dev/null || echo 0)"
  if [ $(( $(now) - last )) -lt "$COOLDOWN_SECONDS" ]; then
    log "skip restart: last was $(( $(now) - last ))s ago (< ${COOLDOWN_SECONDS}s cooldown)"; return 1
  fi
  local recent=0
  if [ -r "$RESTART_LOG" ]; then
    local cutoff=$(( $(now) - 3600 ))
    recent=$(awk -v c="$cutoff" '$1>=c' "$RESTART_LOG" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "${recent:-0}" -ge "$MAX_RESTARTS_PER_HOUR" ]; then
    log "GIVE-UP: $recent restarts in the last hour and still unhealthy — not bouncing again; needs a human look."
    return 1
  fi
  return 0
}

do_restart() {
  local why="$1"
  if $DRY_RUN; then log "DRY-RUN: would restart $LABEL ($why)"; return 0; fi
  echo "$(now)" > "$LAST_RESTART_FILE"
  echo "$(now)" >> "$RESTART_LOG"
  tail -50 "$RESTART_LOG" > "$RESTART_LOG.tmp" 2>/dev/null && mv "$RESTART_LOG.tmp" "$RESTART_LOG"
  log "RESTARTING $LABEL — $why"
  launchctl kickstart -k "gui/$UID_NUM/$LABEL" >> "$LOG_FILE" 2>&1
  log "kickstart exit=$?"
  # verify
  local d=$(( $(now) + 70 )) NEWH=""
  while [ "$(now)" -lt "$d" ]; do NEWH="$(curl -s --max-time 4 "http://localhost:$PORT/health" 2>/dev/null)"; [ -n "$NEWH" ] && break; sleep 4; done
  local st="$(printf '%s' "$NEWH" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("status","?"))
except: print("?")' 2>/dev/null)"
  log "post-restart status=$st"
}

# ========================================================================
# STEP 1 — enforce the good-node pin (the real recurrence fix)
# ========================================================================
CUR="$(readlink "$NODE_SYMLINK" 2>/dev/null || echo '')"
if [ "$CUR" != "$GOOD_NODE" ]; then
  log "NODE DRIFT: $NODE_SYMLINK -> '$CUR' (expected '$GOOD_NODE') — boot.cjs likely flipped to the crashing node"
  if [ -x "$GOOD_NODE" ]; then
    if ! $DRY_RUN; then ln -sfn "$GOOD_NODE" "$NODE_SYMLINK"; fi
    log "repinned $NODE_SYMLINK -> $GOOD_NODE"
    if can_restart; then do_restart "node symlink drifted to '$CUR'; repinned to good node"; fi
    exit 0
  else
    log "ERROR: good node $GOOD_NODE not executable — cannot enforce pin"
    exit 0
  fi
fi
$VERBOSE && log "node pin OK ($CUR)"

# ========================================================================
# STEP 2 — wait for the server, then act only on a native-SQLite degradation
# ========================================================================
H=""; deadline=$(( $(now) + BOOT_WAIT_SECONDS ))
while :; do H="$(curl -s --max-time 4 "http://localhost:$PORT/health" 2>/dev/null)"; [ -n "$H" ] && break; [ "$(now)" -ge "$deadline" ] && break; sleep 5; done
if [ -z "$H" ]; then
  # Server down but the node pin is correct — that's launchd / the fleet watchdog's
  # job. We do NOT pile on (avoids restart races with the single-instance guard).
  $VERBOSE && log "server not responding, node pin correct — deferring to fleet watchdog"
  exit 0
fi

read -r STATUS NATIVE <<EOF
$(printf '%s' "$H" | python3 -c '
import sys, json
TAB = "\t"
try:
    d = json.load(sys.stdin)
except Exception:
    print("parse-error" + TAB + "0"); sys.exit(0)
status = d.get("status", "")
blob = " ".join(d.get("degradationSummary", []) or []).lower()
sig = ("better-sqlite3" in blob or "sqlite-backed" in blob or
       "knowledge graph" in blob or "rebuilt binding" in blob or
       "rebuild better" in blob or "npm rebuild" in blob)
print(status + TAB + ("1" if (status == "degraded" and sig) else "0"))
')
EOF

if [ "$STATUS" = "ok" ]; then $VERBOSE && log "healthy"; exit 0; fi
if [ "$NATIVE" != "1" ]; then log "degraded (status=$STATUS) but NOT a native-SQLite signature — leaving alone"; exit 0; fi

log "DETECTED native-SQLite degradation on the good node — a fresh process should clear it"
if can_restart; then do_restart "native-SQLite degradation (status=$STATUS)"; fi

# trim log
if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 500 ]; then tail -300 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"; fi
exit 0
