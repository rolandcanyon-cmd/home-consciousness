# Known False Signals

Verified signals that look like problems but are not action items.

## SecretStore Master Key Divergence

**Signal**: `/health` degradationSummary contains "The next write() re-encrypts with the primary key (v2 format), converging the sources. If divergence persists, inspect the per-agent keychain entry and .instar/machine/secrets-master.key. Using Decrypted with the file key instead in the meantime — everything else is working fine."

**Status**: Accepted and intentional. Adrian explicitly decided to leave the dual-key state as-is (verified 07-13, confirmed in CLAUDE.md).

**Action**: Ignore this entirely. Drop from degradation summary. Do not report or investigate.

---

## iOS Simulator High Disk Usage

**Signal**: `/dev/disk14s1` shows 98% full (16Gi / 17Gi used).

**Status**: Normal for iOS simulator caches. Not a real issue.

**Action**: Ignore. This is expected simulator artifact usage.

---
