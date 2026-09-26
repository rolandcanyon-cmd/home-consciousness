---
name: Never delete Messages chat.db files
description: Deleting ~/Library/Messages/chat.db breaks iCloud sync and causes persistent failures
type: feedback
originSessionId: 71dec245-8250-47e1-bfd3-839f95ec0a27
---
Never suggest deleting ~/Library/Messages/chat.db (or chat.db-wal, chat.db-shm) to fix iMessage issues.

**Why:** Deleting these files causes Messages.app to enter a broken iCloud sync state where it restores a stale snapshot from iCloud but stops writing new messages to the local database. This persisted across multiple restarts and workarounds and took hours to fix (zeroing the files in-place and rebooting was eventually required).

**How to apply:** When diagnosing iMessage/instar sync issues, never recommend deleting database files. If hardlinks are stale, re-run setup-imessage-hardlink.sh. If the database is corrupted, the correct approach is to zero the files in-place (preserving inodes/hardlinks) rather than deleting them.
