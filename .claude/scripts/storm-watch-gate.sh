#!/bin/bash
# Gate for the storm-watch job: skip (exit 1) once the watch has been marked
# stopped (red flag warning lifted, final all-clear already sent). Cheap,
# no network — read live each tick so the job self-retires without needing
# a server restart.
STATE_FILE="$(dirname "$0")/../../.instar/state/storm-watch-state.json"
if [ -f "$STATE_FILE" ]; then
  stopped=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('stopped', False))" 2>/dev/null)
  if [ "$stopped" = "True" ]; then
    exit 1
  fi
fi
exit 0
