# HomeKit Integration Guide

**Status**: Phase 1 Complete (Foundation)
**Last Updated**: 2026-03-27

## What We Built

A complete HomeKit integration system that allows programmatic control of all HomeKit devices in the house. This is the foundation for multi-ecosystem device management.

## Components

### 1. HomeKit Adapter (`homekit-adapter.js`)
Core library that handles all HomeKit communication:
- Device discovery (both Wi-Fi and Bluetooth)
- Secure pairing with PIN codes
- Reading device capabilities and state
- Controlling devices
- Real-time event subscriptions

### 2. Device Registry (`device-registry.js`)
Centralized database of all house devices:
- Persistent storage in `.instar/state/devices/registry.json`
- Tracks device metadata (name, location, type, last seen)
- Filtering and statistics
- Cross-ecosystem support (ready for Lutron, LIFX native, etc.)

### 3. CLI Tool (`homekit-cli.js`)
Interactive command-line interface:
```bash
node .claude/scripts/homekit-cli.js
```

Commands:
- `discover` - Scan for HomeKit devices
- `list` - Show registered devices
- `pair <id>` - Pair with a device (prompts for PIN)
- `info <id>` - Get device capabilities
- `state <id>` - Get current device state
- `set <id>` - Control a device
- `stats` - Show registry statistics

### 4. REST API (`device-api.js`)
HTTP API for device control (ready for Instar server integration):

**Discovery & Listing**
- `GET /devices/discover?duration=10000` - Scan for devices
- `GET /devices` - List all devices
- `GET /devices?paired=true` - Filter by pairing status
- `GET /devices?type=lightbulb` - Filter by type
- `GET /devices/:deviceId` - Get specific device

**Device Control**
- `POST /devices/:deviceId/pair` - Pair with device (body: `{pin: "123-45-678"}`)
- `GET /devices/:deviceId/capabilities` - Get what device can do
- `GET /devices/:deviceId/state` - Read current state
- `POST /devices/:deviceId/control` - Control device (body: `{characteristics: {"1.10": true}}`)
- `PATCH /devices/:deviceId` - Update metadata (name, location, etc.)

**Monitoring**
- `GET /devices/stats/summary` - Registry statistics
- `GET /devices/stats/stale?hours=24` - Devices not seen recently
- `GET /devices/export` - Full registry export

## Current Device Inventory

### Discovered Devices (2026-03-27)

1. **HomePod** (ID: `homekit:F9:17:9C:9A:B7:0A`)
   - Type: Sensor
   - Address: 10.0.0.10:62095
   - Capabilities: Temperature, humidity, motion (likely)
   - Status: Unpaired

2. **Smart Bridge Pro 2** (ID: `homekit:bf:c3:0f:b1:f0:56`)
   - Type: Bridge (Lutron)
   - Address: 10.0.0.167:4548
   - Capabilities: Controls Lutron switches/dimmers
   - Status: Unpaired
   - Note: This bridges to Lutron devices - we should also integrate Lutron's native API

3. **ecobee3 lite - Wine Closet** (ID: `homekit:E8:0A:59:EB:9E:51`)
   - Type: Thermostat
   - Address: 10.0.0.165:53964
   - Capabilities: Temperature control, sensors
   - Status: Unpaired
   - Note: ecobee has a native API with more features than HomeKit exposes

4. **LIFX Mini W (3784C7)** (ID: `homekit:32:2E:3B:28:5B:E5`)
   - Type: Lightbulb
   - Address: 10.0.0.137:59158
   - Capabilities: On/off, brightness
   - Status: Unpaired
   - Note: LIFX has a native API with color, effects, etc.

5. **LIFX Mini W (3750A1)** (ID: `homekit:DD:89:45:7C:AB:30`)
   - Type: Lightbulb
   - Address: 10.0.0.251:65316
   - Capabilities: On/off, brightness
   - Status: Unpaired

## How to Use

### Quick Start (CLI)

1. **Discover devices:**
   ```bash
   node .claude/scripts/homekit-cli.js
   > discover
   ```

2. **Pair with a device:**
   ```bash
   > pair homekit:32:2E:3B:28:5B:E5
   Enter PIN: 123-45-678
   ```

3. **Get device info:**
   ```bash
   > info homekit:32:2E:3B:28:5B:E5
   ```

4. **Control a device:**
   ```bash
   > set homekit:32:2E:3B:28:5B:E5
   Set: 1.10 true    # Turn on
   ```

### Programmatic Usage (Node.js)

```javascript
const HomeKitAdapter = require('./.instar/integrations/homekit-adapter');
const DeviceRegistry = require('./.instar/integrations/device-registry');

const adapter = new HomeKitAdapter();
const registry = new DeviceRegistry();

await adapter.initialize();
await registry.initialize();

// Discover devices
const devices = await adapter.discover(10000);
await registry.registerBatch(devices);

// Pair with a device
await adapter.pair('homekit:32:2E:3B:28:5B:E5', '123-45-678');

// Control a device (turn on light)
await adapter.setState('homekit:32:2E:3B:28:5B:E5', {
  '1.10': true  // characteristic ID: value
});

// Read state
const state = await adapter.getState('homekit:32:2E:3B:28:5B:E5');
console.log(state);
```

## Security Model

### Pairing Data
- Stored in `.instar/state/devices/pairing/homekit-pairing.json`
- Contains long-term cryptographic keys
- **Must be kept secure** - this allows full control of devices
- Should be in `.gitignore`

### Control Operations
- All device control requires prior pairing
- Pairing requires physical access to device (PIN code)
- Follows HomeKit security model

### API Security (when integrated with Instar)
- All API endpoints should require Instar auth token
- Pairing endpoints need extra confirmation
- State changes trigger audit logs

## Next Steps

### Phase 2: Native Integrations

The HomeKit layer works, but some devices have richer native APIs:

1. **Lutron Integration**
   - Smart Bridge Pro 2 has a local API
   - Can control all Lutron devices directly
   - Better performance than HomeKit proxy
   - Get device names, scenes, etc.

2. **LIFX Native API**
   - HTTP API on each bulb
   - Color control, effects, themes
   - No pairing needed, just HTTP
   - More responsive than HomeKit

3. **ecobee Native API**
   - Cloud API (requires developer account)
   - Remote sensor data
   - Advanced scheduling
   - Weather integration

### Phase 3: Knowledge Graph

Build relationships between devices:
- Zones/rooms (Wine Closet, Living Room, etc.)
- Device dependencies (Bridge → controlled devices)
- Usage patterns
- Automation suggestions

### Phase 4: Automation

Once we have device control + knowledge graph:
- Time-based automations
- Sensor-triggered actions
- Presence detection
- Energy optimization

## Integration with Instar Server

The `device-api.js` module is designed to integrate with Instar's server. To enable:

1. **Register the service** in `.instar/config.json`:
   ```json
   {
     "externalOperations": {
       "services": {
         "devices": {
           "enabled": true,
           "module": "./.instar/integrations/device-api.js",
           "mountPath": "/devices"
         }
       }
     }
   }
   ```

2. **Restart the server**:
   ```bash
   instar server restart
   ```

3. **Use the API**:
   ```bash
   curl -H "Authorization: Bearer $AUTH" \
     http://localhost:4040/devices/discover
   ```

(Note: This integration method may need adjustment based on Instar's actual externalOperations implementation)

## Architecture Diagram

```
┌─────────────────────────────────────────────┐
│         User Interfaces                      │
│  CLI Tool │ API │ Telegram │ Jobs           │
└─────────────┬───────────────────────────────┘
              │
┌─────────────▼───────────────────────────────┐
│         Device API Layer                     │
│  Unified REST interface                      │
└─────────────┬───────────────────────────────┘
              │
┌─────────────▼───────────────────────────────┐
│      Ecosystem Adapters                      │
│  ┌──────────┐ ┌─────────┐ ┌──────────┐     │
│  │ HomeKit  │ │ Lutron  │ │  LIFX    │ ... │
│  │ Adapter  │ │ Adapter │ │ Adapter  │     │
│  └──────────┘ └─────────┘ └──────────┘     │
└─────────────┬───────────────────────────────┘
              │
┌─────────────▼───────────────────────────────┐
│       Device Registry                        │
│  Single source of truth for all devices      │
│  .instar/state/devices/registry.json        │
└──────────────────────────────────────────────┘
```

## Files Created

### Core Components
- `.instar/integrations/homekit-adapter.js` - HomeKit communication layer
- `.instar/integrations/device-registry.js` - Device database
- `.instar/integrations/device-api.js` - REST API service

### Tools
- `.claude/scripts/homekit-discover.js` - Standalone discovery scanner
- `.claude/scripts/homekit-cli.js` - Interactive CLI tool

### Documentation
- `.instar/context/device-integration-architecture.md` - System design
- `.instar/context/homekit-integration-guide.md` - This file

### State (created at runtime)
- `.instar/state/devices/registry.json` - Device database
- `.instar/state/devices/pairing/homekit-pairing.json` - Pairing keys

## Troubleshooting

### "No devices found"
- Ensure devices are powered on
- Check network connectivity
- HomeKit devices use mDNS (Bonjour) - firewall may block
- BLE devices won't show up (we're scanning Wi-Fi only)

### "Pairing failed"
- Verify PIN is correct (8 digits, format: XXX-XX-XXX)
- Device may already be paired to maximum controllers
- Try resetting the device
- Check device is on same network

### "Device not found"
- Run `discover` first to populate the registry
- Device may have changed IP address
- Check device is online

### "Failed to get state"
- Ensure device is paired
- Device may be offline
- Network connectivity issue

## Security Notes

**IMPORTANT**: Never modify device configurations without explicit confirmation from Adrian.

**Allowed without confirmation:**
- Discovery
- Reading state
- Querying capabilities

**Requires confirmation:**
- Pairing
- Changing device settings
- Sending control commands
- Modifying automations

This follows the core principle: I understand the context of the house, but Adrian controls it.
