---
name: known-jobs-json-unwrapped-crash
description: A malformed .instar/jobs.json crash-loops the whole server at boot; seen 2026-10-26 after reboot+macOS 27.2 upgrade
metadata:
  node_type: memory
  type: project
  originSessionId: 2a851d5e-3d87-48e1-a98e-befe97737a48
  modified: 2026-10-27T03:47:06.969Z
---

On 2026-10-26 the server crash-looped after a reboot + macOS upgrade. The cause was not the OS. `.instar/jobs.json` had lost its `[ ]` array wrapper: 33 pretty-printed job objects were concatenated, owned by root:wheel, mtime Oct 16 01:46, probably from a jq edit without `-s` around when storm-watch was added. The running server kept its in-memory jobs and only logged "Refusing job … failed to reload jobs" for 10 days, so every scheduled job was silently refused. At restart, JobScheduler.start threw, and the whole server went down, iMessage included.

Fixed by parsing the objects with raw_decode and rewrapping them as an array. The corrupt copy was saved as jobs.json.corrupt-20261026-*. Reported upstream as a bug.

**Why:** the scheduler and server are fragile to this file, and any hand-edit of jobs.json can take the agent offline at the next restart.
**How to apply:** if the server is down or crash-looping, check the tail of .instar/logs/server-launchd.err first. After editing jobs.json, validate it with `python3 -c "import json;json.load(open('.instar/jobs.json'))"`. A "Refusing job … failed to reload jobs" line in server.log is an early warning.

Same incident: tmux was brew-upgraded to 3.8 at 20:32 that night. The iMessage send probe under 3.8 passed, so the Automation grant held this time. See [[known_tmux_upgrade_breaks_imessage_send]]. Orphaned imagent/IMDPersistenceAgent processes from 12:22 were present, but only the 20:14 agent held the WAL and the DB kept updating, so there was no deadlock. See [[known_stale_imdpersistenceagent]].
