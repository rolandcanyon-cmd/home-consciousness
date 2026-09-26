---
name: project-funkygibbon-backups
description: "FunkyGibbon has three backup layers; the iCloud mirror is change-detecting, so a stale-looking newest file is normal, not a failure"
metadata: 
  node_type: memory
  type: project
  originSessionId: c0ccb140-fb75-4164-9c47-8efd5c716a4c
  modified: 2026-07-31T22:52:29.307Z
---

FunkyGibbon (`~/the-goodies`, SQLite at `funkygibbon.db`, service on port 8000 via launchd `com.rolandcanyon.funkygibbon`) has THREE backup layers:

1. **Local daily** — in-process APScheduler (`funkygibbon/backup_scheduler.py`) writes `backups/funkygibbon_backup_<ts>.db` every 24h with checksummed `.json` manifests. Config says `backup_retention_days=30` but `backup_max_count=10` binds first → effective retention ~10 days, not 30.
2. **Local + iCloud change-detecting** — hourly cron running `scripts/backup-funkygibbon.py` writes `backups/scheduled_<ts>.db` AND mirrors to `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/FunkyGibbon-Backups`. Log: `logs/backup-mirror.log`.
3. **Hourly APFS local snapshots** (same disk — not real protection).

**The gotcha (I got this wrong on 2026-07-31):** layer 2 only writes a NEW snapshot when the DB content hash changes. If the database hasn't been written to in weeks, the newest iCloud file is weeks old — that is CORRECT behavior, not a broken mirror. Verify by reading `logs/backup-mirror.log` (healthy runs log `unchanged (sha256=…)`) and by comparing row counts + `MAX(updated_at)` in the newest iCloud copy against live. Do NOT conclude "copying stopped" from file mtimes alone.

Related: [[known_config_json_not_backed_up]], [[project_the_goodies]].

**Also true as of 2026-07-31:** Time Machine has a destination configured but it fails to mount (no external drive attached), so TM is not protecting anything machine-wide. `funkygibbon.db` and `backups/` are gitignored by design.
