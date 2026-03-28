# WhatsApp Integration Analysis

**Date**: 2026-03-28
**Purpose**: Compare openclaw and instar WhatsApp implementations to identify improvements

## Architecture Comparison

### OpenClaw WhatsApp Extension

**Structure:**
```
extensions/whatsapp/
├── src/
│   ├── session.ts          # Connection lifecycle & state
│   ├── login-qr.ts         # QR code auth flow
│   ├── active-listener.ts   # Global state management
│   ├── inbound/
│   │   ├── monitor.ts      # Inbox monitoring
│   │   ├── dedupe.ts       # Message deduplication
│   │   └── extract.ts      # Message parsing
│   ├── accounts.ts         # Multi-account support
│   ├── auth-store.ts       # Credential storage
│   └── send.ts             # Outbound messages
├── runtime-api.ts          # Public API surface
└── package.json
```

**Key Patterns:**
1. **Multi-account native** - Map-based storage for multiple WhatsApp accounts
2. **Modular architecture** - Separation of concerns (auth, messages, monitoring)
3. **Lazy loading** - QR login module loads on demand
4. **Session freshness** - 3-minute TTL for QR codes
5. **Graceful degradation** - Best-effort file permissions, backup on save failures
6. **Message deduplication** - Tracks outbound messages to prevent echo loops
7. **Append handling** - 60-second grace period for historical messages on reconnect
8. **Group metadata caching** - 5-minute TTL to reduce API calls

### Instar WhatsApp Integration

**Structure:**
```
instar/messaging/
├── WhatsAppAdapter.js       # High-level interface
├── backends/
│   └── BaileysBackend.js    # Baileys protocol implementation
└── shared/
    ├── MessageBridge.js     # Cross-platform routing
    └── PhoneUtils.js        # Phone number utilities
```

**Key Patterns:**
1. **Exponential backoff** - [2s, 5s, 10s, 30s, 60s] with 30% jitter
2. **Circuit breaker** - Max reconnect attempts (configurable)
3. **Version auto-fetch** - Dynamically fetches latest WA Web version to avoid 405 errors
4. **Stale credential detection** - Auto-clears auth if <5min old and getting 401
5. **Message ID tracking** - Prevents processing own outbound echoes
6. **Audio transcription** - Groq/OpenAI Whisper integration
7. **Pairing code auth** - Headless authentication without QR scanning
8. **Terminal failure detection** - Stops reconnecting on 405/403/401

## What Instar Does Better

### 1. Reconnection Strategy
✅ **Exponential backoff with jitter** - Prevents thundering herd
✅ **Circuit breaker** - Stops infinite reconnect loops
✅ **Transient vs terminal failure detection** - Smart decision on whether to retry

### 2. Version Management
✅ **Auto-fetch latest WA Web version** - Prevents 405 errors from stale protocol
✅ **Configurable browser identifier** - Defaults to MacOS to avoid 405

### 3. Stale Credential Recovery
✅ **Auto-clears recent incomplete pairings** - Fixes 401 from abandoned pairing attempts
✅ **Age-based heuristic** - Only clears if credentials <5 minutes old

### 4. Voice Transcription
✅ **Built-in audio transcription** - Converts voice messages to text
✅ **Provider flexibility** - Groq (cheaper) or OpenAI Whisper
✅ **Auto-detection** - Checks env vars to choose provider

## What OpenClaw Does Better

### 1. Multi-Account Support
✅ **Native multi-account** - Map-based storage for multiple WhatsApp accounts
✅ **Account isolation** - Each account has its own auth directory and state
✅ **Current account pointer** - Easy switching between accounts

### 2. Session Management
✅ **Session freshness TTL** - 3-minute window prevents stale QR codes
✅ **Queued credential saves** - Per-account queues prevent concurrent write conflicts
✅ **Backup on write** - Creates backups before overwriting credentials
✅ **JSON validation before save** - Prevents saving corrupted credentials

### 3. Message Handling
✅ **Dedicated deduplication module** - Centralized duplicate detection
✅ **Grace period for historical messages** - 60-second window on reconnect
✅ **Connection timestamp tracking** - Distinguishes old vs new messages
✅ **Group metadata caching** - 5-minute TTL reduces API overhead

### 4. Modular Architecture
✅ **Clear separation of concerns** - Auth, messages, monitoring in separate modules
✅ **Testable components** - Each module has contract tests
✅ **Lazy loading** - QR module only loads when needed
✅ **Type safety** - Full TypeScript implementation

## Recommended Improvements for Instar

### Priority 1: Session Stability

**Problem**: WhatsApp requires frequent re-authentication (per MEMORY.md observation)
**Solution**: Add session freshness checks and credential validation

```javascript
// Add to BaileysBackend
_sessionFreshnessTTL = 3 * 60 * 1000; // 3 minutes
_lastQrTimestamp = null;

isQrFresh() {
  if (!this._lastQrTimestamp) return false;
  return Date.now() - this._lastQrTimestamp < this._sessionFreshnessTTL;
}

// In connection.update handler, when qr event fires:
if (qr) {
  this._lastQrTimestamp = Date.now();
  // ...existing QR handling
}
```

**Benefit**: Prevents confusion from stale QR codes, improves UX

### Priority 2: Credential Backup

**Problem**: Auth state corruption can require full re-authentication
**Solution**: Backup credentials before writing, validate JSON structure

```javascript
// Add to BaileysBackend or create separate auth-manager module
async saveCredsWithBackup(credsPath) {
  // 1. Read current credentials
  let existing = null;
  try {
    existing = fs.readFileSync(credsPath, 'utf8');
    JSON.parse(existing); // Validate it's valid JSON
  } catch { /* No existing or invalid */ }

  // 2. Create backup if valid
  if (existing) {
    const backupPath = `${credsPath}.backup`;
    fs.writeFileSync(backupPath, existing, 'utf8');
  }

  // 3. Write new credentials (Baileys handles this via saveCreds)
}
```

**Benefit**: Quick recovery from corrupted auth state

### Priority 3: Per-Account Queues

**Problem**: Multi-agent scenarios could cause concurrent credential writes
**Solution**: Queued saves per auth directory (like openclaw)

```javascript
// Global state for credential save queues
const credsQueues = new Map(); // authDir -> Promise chain

function enqueueSaveCreds(authDir, saveFn) {
  const existing = credsQueues.get(authDir) || Promise.resolve();
  const queued = existing.then(() => saveFn()).catch(err => {
    console.error(`[baileys] Failed to save creds for ${authDir}:`, err);
  });
  credsQueues.set(authDir, queued);
  return queued;
}

// In connect(), replace:
// this.socket.ev.on('creds.update', saveCreds);
// With:
this.socket.ev.on('creds.update', () => {
  enqueueSaveCreds(this.config.authDir, saveCreds);
});
```

**Benefit**: Prevents write conflicts in multi-agent setups

### Priority 4: Message Grace Period

**Problem**: On reconnect, historical messages may be reprocessed
**Solution**: Track connection timestamp, filter old "append" messages

```javascript
// Add to BaileysBackend
_connectedAtMs = null;
const APPEND_GRACE_MS = 60_000; // 60 seconds

// In connection === 'open' handler:
this._connectedAtMs = Date.now();

// In messages.upsert handler:
if (m.type === 'append') {
  // Check if message is from before we connected
  const msgTime = msg.messageTimestamp * 1000; // Convert to ms
  if (msgTime < this._connectedAtMs - APPEND_GRACE_MS) {
    // Message is >60s before connection - skip (historical)
    continue;
  }
}
```

**Benefit**: Prevents duplicate processing of old messages on reconnect

### Priority 5: Group Metadata Cache

**Problem**: Group name lookups may hit API repeatedly
**Solution**: Cache group metadata with TTL

```javascript
// Add to BaileysBackend
_groupMetadataCache = new Map(); // jid -> { data, expires }
const GROUP_CACHE_TTL = 5 * 60 * 1000; // 5 minutes

async getGroupMetadata(jid) {
  const cached = this._groupMetadataCache.get(jid);
  if (cached && Date.now() < cached.expires) {
    return cached.data;
  }

  const metadata = await this.socket?.groupMetadata(jid);
  this._groupMetadataCache.set(jid, {
    data: metadata,
    expires: Date.now() + GROUP_CACHE_TTL
  });

  return metadata;
}
```

**Benefit**: Reduces API calls, improves performance

## Implementation Priority

| Feature | Impact | Effort | Priority |
|---------|--------|--------|----------|
| Credential backup | High - prevents data loss | Low | ⭐⭐⭐ |
| Message grace period | Medium - prevents duplicates | Low | ⭐⭐⭐ |
| Session freshness | Medium - better UX | Low | ⭐⭐ |
| Group metadata cache | Low - performance | Low | ⭐ |
| Per-account queues | Low - multi-agent only | Medium | ⭐ |

## Testing Strategy

Before implementing improvements:

1. **Baseline testing** - Document current failure modes
2. **Incremental changes** - One improvement at a time
3. **Regression testing** - Ensure existing auth still works
4. **Edge case testing** - Interrupted pairing, network drops, etc.

## Current Instar Status (from MEMORY.md)

**Known Issues:**
- WhatsApp connection requires periodic re-authentication via QR code
- Machine sleep/wake cycles cause connection drops
- Quick tunnel URLs regenerate frequently

**Observations:**
- Server restarts cleanly
- Auto-start working
- Jobs running successfully
- No major stability issues beyond re-auth

## Conclusion

**Instar's WhatsApp implementation is solid** with strong reconnection logic and error handling. The main gaps are:

1. **Session persistence** - Could be more resilient to machine sleep/wake
2. **Credential protection** - No backup mechanism
3. **Multi-account readiness** - Not designed for it (but not needed currently)

**OpenClaw's patterns worth adopting:**
- Credential backup with validation
- Message grace period on reconnect
- Session freshness TTL
- Group metadata caching

All are **low-effort, high-value** improvements that align with BDD testing practices.
