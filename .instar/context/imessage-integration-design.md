# iMessage Integration Design

**Date**: 2026-03-28
**Status**: Design Phase
**Goal**: Add iMessage messaging support to instar agent

## Overview

Enable the Roland agent to send and receive iMessages using the `imsg` CLI tool's JSON-RPC interface. This will allow interaction via iMessage on macOS, leveraging the existing Apple ID/iMessage account.

## Architecture

### Components

```
┌─────────────────────────────────────────────┐
│           Instar Server/Agent                │
├─────────────────────────────────────────────┤
│                                              │
│  ┌───────────────────────────────────────┐  │
│  │     iMessageAdapter                    │  │
│  │  - Connection state management         │  │
│  │  - Message routing                     │  │
│  │  - Error handling                      │  │
│  └──────────┬─────────────────────────────┘  │
│             │                                 │
│  ┌──────────▼─────────────────────────────┐  │
│  │     iMessageRpcClient                  │  │
│  │  - JSON-RPC over stdio                │  │
│  │  - Request/response matching          │  │
│  │  - Notification handling               │  │
│  │  - Process lifecycle                   │  │
│  └──────────┬─────────────────────────────┘  │
│             │ spawn('imsg rpc')              │
└─────────────┼─────────────────────────────────┘
              │
    ┌─────────▼──────────┐
    │   imsg rpc         │
    │  - Messages.app DB │
    │  - AppleScript     │
    └────────────────────┘
```

### Layer Responsibilities

**1. iMessageAdapter** (`.instar/integrations/imessage-adapter.js`)
- High-level messaging interface
- Connection state tracking (disconnected, connecting, connected, error)
- Message queue during disconnection
- Deduplication (prevent processing own outbound messages)
- Error recovery and reconnection

**2. iMessageRpcClient** (`.instar/integrations/imessage-rpc-client.js`)
- JSON-RPC protocol implementation
- Process management (spawn, restart, cleanup)
- Request tracking with timeouts
- Notification event emission
- Line-buffered stdin/stdout handling

**3. imsg CLI** (external)
- Database access to ~/Library/Messages/chat.db
- AppleScript for sending messages
- File watching for new messages
- JSON-RPC server over stdio

## JSON-RPC Protocol

### Request Format
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "send",
  "params": {
    "to": "+14081234567",
    "text": "Hello from Roland!",
    "service": "imessage"
  }
}
```

### Response Format
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "messageId": "p:0/12345"
  }
}
```

### Notification Format (Incoming Messages)
```json
{
  "jsonrpc": "2.0",
  "method": "message",
  "params": {
    "chatId": "iMessage;-;+14081234567",
    "messageId": "p:0/12346",
    "sender": "+14081234567",
    "senderName": "Adrian",
    "text": "How are things going?",
    "timestamp": 1711584000,
    "isFromMe": false,
    "attachments": []
  }
}
```

## RPC Methods

### Core Methods

| Method | Params | Returns | Purpose |
|--------|--------|---------|---------|
| `watch.subscribe` | `{attachments: boolean}` | `{success: true}` | Start watching for new messages |
| `send` | `{to, text, service?, file?, reply_to?}` | `{messageId}` | Send a message/attachment |
| `chats.list` | `{limit?: number}` | `{chats: [...]}` | List recent conversations |
| `history.get` | `{chatId, limit?}` | `{messages: [...]}` | Get message history |

### Future Methods
- `message.react` - Add reaction to message
- `message.delete` - Delete/unsend message
- `typing.send` - Send typing indicator

## Message Flow

### Inbound Messages

```
1. imsg detects new message in Messages.app DB
2. imsg emits notification via stdout
3. RpcClient parses JSON notification
4. RpcClient emits 'message' event
5. Adapter receives event
6. Adapter checks deduplication (skip if own message)
7. Adapter routes to handler (job, skill, or direct reply)
8. Handler processes and generates response
9. Response sent via adapter.sendMessage()
```

### Outbound Messages

```
1. Agent calls adapter.sendMessage({to, text})
2. Adapter tracks message ID for deduplication
3. Adapter calls client.request('send', params)
4. Client sends JSON-RPC request over stdin
5. imsg receives request
6. imsg uses AppleScript to send via Messages.app
7. imsg responds with messageId
8. Client resolves promise
9. Adapter returns messageId to caller
```

## State Management

### Connection States

- `disconnected` - imsg process not running
- `connecting` - Process starting, waiting for ready signal
- `connected` - Process running and subscribed to messages
- `error` - Process crashed or failed to start

### State Transitions

```
disconnected --[connect()]--> connecting
connecting --[ready event]--> connected
connecting --[error]--> error
connected --[process exit]--> disconnected
error --[retry timer]--> disconnected
```

## Configuration

Add to `.instar/config.json`:

```json
{
  "messaging": [
    {
      "type": "imessage",
      "enabled": true,
      "config": {
        "cliPath": "/Users/rolandcanyon/homebrew/bin/imsg",
        "dbPath": "/Users/rolandcanyon/Library/Messages/chat.db",
        "includeAttachments": true,
        "region": "US",
        "autoReconnect": true,
        "maxReconnectAttempts": 10
      }
    }
  ]
}
```

## Permissions Required

### Full Disk Access
The terminal/process running instar needs Full Disk Access to read Messages database:
```
System Settings > Privacy & Security > Full Disk Access
```
Add: Terminal.app or iTerm.app

### Automation Permission
To send messages via AppleScript:
```
System Settings > Privacy & Security > Automation
```
Allow Terminal to control Messages.app

## Error Handling

### Process Crashes
- Detect via `exit` event on child process
- Log exit code and signal
- Schedule reconnection with exponential backoff
- Circuit breaker after max attempts

### Permission Errors
- Detect via error messages containing "permission" or "access denied"
- Emit clear error with instructions for user
- Do not auto-reconnect (requires manual fix)

### Database Lock
- Retry read operations with backoff
- Messages.app may lock database temporarily
- Usually resolves within seconds

### JSON Parse Errors
- Log malformed lines from stdout/stderr
- Continue processing other messages
- Don't crash the adapter

## Message Deduplication

### Outbound Echo Prevention
```javascript
class iMessageAdapter {
  sentMessageIds = new Set();
  SENT_IDS_MAX_SIZE = 1000;

  async sendMessage({to, text}) {
    const {messageId} = await this.client.request('send', {to, text});

    // Track this message ID
    this.sentMessageIds.add(messageId);

    // Prevent unbounded growth
    if (this.sentMessageIds.size > this.SENT_IDS_MAX_SIZE) {
      const oldest = this.sentMessageIds.values().next().value;
      this.sentMessageIds.delete(oldest);
    }

    return messageId;
  }

  handleIncomingMessage(msg) {
    // Skip if this is our own outbound message
    if (this.sentMessageIds.has(msg.messageId)) {
      return;
    }

    // Process the message...
  }
}
```

### Duplicate Notification Prevention
- Track last N message IDs received
- Skip if already processed
- Use LRU cache or Set with size limit

## Security Considerations

### Access Control
- iMessage has no built-in authentication
- Anyone who knows the agent's phone number can message it
- Implement allowlist in adapter config:
  ```json
  {
    "allowedSenders": [
      "+14084424360",  // Adrian
      "user@icloud.com"
    ]
  }
  ```

### Sensitive Data
- Never log full message content (PII concerns)
- Mask phone numbers in logs: `+1408***4360`
- Don't expose database path in error messages

### Rate Limiting
- Prevent spam/abuse from unknown senders
- Max messages per sender per hour
- Global rate limit for all inbound messages

## Testing Strategy

### Unit Tests
- iMessageRpcClient - JSON-RPC protocol handling
- Request/response matching
- Notification parsing
- Process lifecycle

### Integration Tests
- Full flow with mock `imsg` process
- Send messages
- Receive notifications
- Reconnection handling
- Error scenarios

### Manual Testing
- Send test message to agent's iMessage account
- Verify agent receives and responds
- Test with attachments
- Test group chats (future)

## Implementation Phases

### Phase 1: Core RPC Client ✅
- [x] Spawn and manage imsg process
- [x] JSON-RPC request/response
- [x] Notification handling
- [x] Process lifecycle
- [x] Error handling

### Phase 2: Adapter Layer
- [ ] Connection state management
- [ ] Message deduplication
- [ ] Send message API
- [ ] Receive message handling
- [ ] Reconnection logic

### Phase 3: Integration
- [ ] Add to instar messaging subsystem
- [ ] Configuration support
- [ ] Permission validation
- [ ] API endpoints

### Phase 4: Features
- [ ] Attachment support
- [ ] Message history queries
- [ ] Chat list
- [ ] Typing indicators
- [ ] Reactions

## API Endpoints (Future)

```
GET  /imessage/status           - Connection status
GET  /imessage/chats            - List conversations
GET  /imessage/chats/:id        - Get chat details
GET  /imessage/chats/:id/history - Message history
POST /imessage/send             - Send message
POST /imessage/subscribe        - Subscribe to message events (WebSocket)
```

## Integration with Existing Messaging

Instar already has a messaging abstraction (`WhatsAppAdapter`). The `iMessageAdapter` should implement the same interface for consistency:

```javascript
// Shared messaging interface
interface MessagingAdapter {
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  sendMessage(to: string, text: string, options?: any): Promise<string>;
  onMessage(handler: (msg: IncomingMessage) => void): void;
  getConnectionState(): ConnectionState;
}
```

This allows:
- Unified message routing
- Consistent error handling
- Cross-platform bridges (iMessage ↔ WhatsApp)
- Shared rate limiting and spam detection

## Comparison to WhatsApp Integration

| Feature | WhatsApp (Baileys) | iMessage (imsg) |
|---------|-------------------|-----------------|
| Protocol | WebSocket | JSON-RPC over stdio |
| Auth | QR code / pairing code | System-level (logged in) |
| Attachments | Native support | Via file paths |
| Groups | Full support | Read-only initially |
| Typing indicators | Yes | Possible |
| Read receipts | Yes | Possible |
| Reactions | Yes | Possible |
| Reconnection | Built-in | Manual implementation |

## Next Steps

1. ✅ Install and verify imsg
2. 🔄 Design architecture (this document)
3. ⏳ Write tests for RPC client
4. ⏳ Implement RPC client
5. ⏳ Write tests for adapter
6. ⏳ Implement adapter
7. ⏳ Integration testing
8. ⏳ Documentation

## Resources

- imsg GitHub: https://github.com/steipete/imsg
- OpenClaw iMessage docs: https://docs.openclaw.ai/channels/imessage
- OpenClaw source: https://github.com/openclaw/openclaw/tree/main/extensions/imessage
- JSON-RPC spec: https://www.jsonrpc.org/specification
