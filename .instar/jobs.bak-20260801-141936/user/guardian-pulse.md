---
name: Guardian Pulse
description: "Meta-monitor: verify other jobs are running, healthy, and not silently failing."
schedule: 0 */8 * * *
priority: high
expectedDurationMinutes: 2
model: haiku
enabled: true
tags:
  - cat:guardian
  - exec:prompt
gate: curl -sf http://localhost:4040/health >/dev/null 2>&1
toolAllowlist:
  - Read
---
AUTH=$(python3 -c "import json; print(json.load(open('.instar/config.json')).get('authToken',''))" 2>/dev/null); curl -s -H "Authorization: Bearer $AUTH" http://localhost:4040/jobs | python3 -c "import sys,json; jobs=json.load(sys.stdin); enabled=[j for j in jobs if j.get('enabled')]; print(f'Total enabled jobs: {len(enabled)}'); failing=[j for j in enabled if j.get('state',{}).get('consecutiveFailures',0)>2]; never_run=[j for j in enabled if j.get('state',{}).get('lastRun') is None and 'cat:guardian' in j.get('tags',[])]; [print(f'FAILING: {j[\"slug\"]} - {j.get(\"state\",{}).get(\"consecutiveFailures\")} consecutive failures') for j in failing]; [print(f'NEVER RUN: {j[\"slug\"]} - enabled but has never executed') for j in never_run]" && echo 'If any FAILING or NEVER RUN jobs found, flag with [ATTENTION]. Otherwise exit silently.'
