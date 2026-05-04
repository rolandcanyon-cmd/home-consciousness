#!/bin/bash
# Sent once each time the instar server starts — reports version and health via iMessage.
# Runs as a separate LaunchAgent (ai.instar.AGENT.Announce.plist) that fires at login,
# waits for the server to be healthy, sends the message, then exits.

set -euo pipefail

AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="${AGENT_DIR}/.instar/config.json"

# Read config values
AUTH=$(python3 -c "import json; c=json.load(open('${CONFIG_FILE}')); print(c.get('authToken',''))" 2>/dev/null || echo "")
IMESSAGE_USERS=$(python3 -c "
import json
c=json.load(open('${CONFIG_FILE}'))
nums = c.get('imessage', {}).get('allowedNumbers', [])
print('\n'.join(nums))
" 2>/dev/null || echo "")
AGENT_NAME=$(python3 -c "
import json
c=json.load(open('${CONFIG_FILE}'))
print(c.get('agentName', 'House'))
" 2>/dev/null || echo "House")

if [[ -z "$IMESSAGE_USERS" ]]; then
    echo "No iMessage users configured — skipping startup announce"
    exit 0
fi

# Wait for server to be healthy (up to 60s)
for i in $(seq 1 60); do
    _status=$(curl -s --max-time 2 http://localhost:4040/health 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
    [[ "$_status" == "ok" || "$_status" == "degraded" ]] && break
    sleep 1
done

# Get version and health details
VERSION=$(curl -s --max-time 5 -H "Authorization: Bearer ${AUTH}" http://localhost:4040/updates 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('currentVersion','unknown'))" 2>/dev/null || echo "unknown")
HEALTH=$(curl -s --max-time 5 http://localhost:4040/health 2>/dev/null \
    | python3 -c "
import json, sys
h = json.load(sys.stdin)
status = h.get('status', 'unknown')
degradations = h.get('degradations', 0)
uptime = h.get('uptimeHuman', '')
if status == 'ok':
    print('healthy' + (f', uptime {uptime}' if uptime else ''))
elif status == 'degraded':
    print(f'degraded ({degradations} issue(s))')
else:
    print(status)
" 2>/dev/null || echo "unknown")

MESSAGE="${AGENT_NAME} v${VERSION} is online — ${HEALTH}."

# Send to all configured iMessage users
IMESSAGE_BIN="${HOME}/homebrew/bin/imsg"
[[ ! -x "$IMESSAGE_BIN" ]] && IMESSAGE_BIN=$(command -v imsg 2>/dev/null || echo "")

if [[ -z "$IMESSAGE_BIN" ]]; then
    echo "imsg not found — cannot send startup announcement"
    exit 0
fi

while IFS= read -r RECIPIENT; do
    [[ -z "$RECIPIENT" ]] && continue
    "$IMESSAGE_BIN" send "$RECIPIENT" "$MESSAGE" 2>/dev/null \
        && echo "Startup announce sent to ${RECIPIENT}: ${MESSAGE}" \
        || echo "Failed to send to ${RECIPIENT}"
done <<< "$IMESSAGE_USERS"
