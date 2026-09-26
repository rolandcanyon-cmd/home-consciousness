---
name: hardlinks share inodes, don't count as space
description: Don't propose retention/cleanup for hardlinked attachment directories — they share inodes with the originals
type: feedback
originSessionId: fc2a6623-0c20-49f5-8339-e61be5a29b52
---
Hardlinked directories (like `.instar/imessage/attachments/`) share inodes with their source files. `du` reports the same bytes against both locations, but only one copy exists on disk.

**Why:** Adrian corrected me when I proposed adding retention to the 170MB attachments dir — the space is phantom accounting, not actual duplication. Deleting old hardlinks wouldn't free any disk.

**How to apply:** For any directory that's a hardlink mirror of another (attachments, chat.db hardlink), don't propose retention/cleanup on space grounds. If retention is needed for other reasons (privacy, index size), say so explicitly — don't justify it by disk usage.
