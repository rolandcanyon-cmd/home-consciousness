---
name: known-tmutil-stale-store
description: tmutil listbackups/latestbackup can read a stale unmounted store and falsely report no recent backup — verify on the destination volume instead
metadata: 
  node_type: memory
  type: reference
  originSessionId: c0ccb140-fb75-4164-9c47-8efd5c716a4c
  modified: 2026-08-01T03:58:05.544Z
---

`tmutil listbackups` and `tmutil latestbackup` can enumerate a **stale backup store that is not
the active destination**, making a successful backup look like it never happened.

Observed 2026-07-31: after a successful backup completed at 20:50, `tmutil listbackups` still
reported 92 backups with 2026-01-11 as the newest, and `tmutil latestbackup` still returned the
January path. Both were reading store `D1B85E6B-C17C-4F31-A1C4-3E31CF0179DE`, which was **not
mounted** — `/Volumes/.timemachine/` contained only `196E528A-A7C6-42CB-8F04-558266761B51`, and
`tmutil destinationinfo` reported a third ID (`9B10C965-…`) for the destination itself.

**Ground truth is the destination volume**, not tmutil:

```
ls -1dt "/Volumes/<dest volume>/"*/ | head
```

Suffixes are the verdict — this drive labels them explicitly:
- `.backup` → succeeded (e.g. `2026-07-31-205009.backup`)
- `.interrupted` → failed (e.g. `2026-03-27-122608.interrupted`)
- `.previous` → older retained backup

**Also useful:** destination free-space delta (`df -k`) confirms bytes actually written.
A first backup after a long gap writes far less than `totalBytes` suggests, because unchanged
files are hardlinked, not recopied — 232 GB written against an 846 GB headline figure.
And the `Percent` field tracks files evaluated, not bytes, so it jumps non-linearly.

Phase meaning: `ThinningPostBackup` only runs **after** a backup succeeds — reaching it is itself
positive evidence.

Machine context: hostname `escapepod-3`; TM destination volume is `Backups of escapepod-3` on a
3.6 TB Seagate that also holds `Backups of Adrian's MacBook Pro`. Backups only run when that
drive is physically attached. See [[project_funkygibbon_backups]].
