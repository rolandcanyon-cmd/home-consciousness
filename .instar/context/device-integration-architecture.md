# House Device Integration Architecture

**Created**: 2026-03-27
**Status**: Design Phase

## Overview

This house has devices from multiple vendors and ecosystems. The integration architecture provides a unified interface to discover, monitor, and control all devices while maintaining their native capabilities and relationships.

## Design Principles

1. **Vendor Agnostic** - Each ecosystem (HomeKit, Lutron, LIFX, ecobee, etc.) gets its own adapter
2. **Centralized Knowledge** - Single source of truth for device state, relationships, and capabilities
3. **Real-time Awareness** - Subscribe to device updates for live state tracking
4. **Secure by Default** - Pairing data and credentials stored encrypted, never modified without confirmation
5. **Resilient** - Graceful degradation when individual devices or ecosystems are offline

## Architecture Layers

### 1. Adapter Layer
Individual modules for each ecosystem:
- `homekit-adapter.js` - HomeKit devices (via hap-controller)
- `lutron-adapter.js` - Lutron Caseta/RA2 (via Smart Bridge)
- Future: Ring, Sonos, etc.

Each adapter implements:
```javascript
{
  discover(),           // Find devices
  pair(device, auth),   // Authenticate with device/service
  getState(deviceId),   // Read current state
  setState(deviceId, value), // Control device
  subscribe(deviceId, callback), // Real-time updates
  getCapabilities(deviceId) // What can this device do?
}
```

### 2. Device Registry
**Location**: `.instar/state/devices/registry.json`

Canonical list of all known devices:
```json
{
  "devices": {
    "homekit:F9:17:9C:9A:B7:0A": {
      "id": "homekit:F9:17:9C:9A:B7:0A",
      "ecosystem": "homekit",
      "name": "HomePod Sensor",
      "type": "sensor",
      "model": "HomePod",
      "location": "unknown",
      "capabilities": ["temperature", "humidity", "motion"],
      "address": "10.0.0.10:62095",
      "lastSeen": "2026-03-27T...",
      "paired": false,
      "metadata": {}
    }
  }
}
```

### 3. Knowledge Graph
**Location**: `.instar/state/devices/knowledge-graph.json`

Relationships between devices:
```json
{
  "nodes": [
    {"id": "homekit:bf:c3:0f:b1:f0:56", "type": "bridge"},
    {"id": "lutron:switch-1", "type": "switch"}
  ],
  "edges": [
    {
      "from": "homekit:bf:c3:0f:b1:f0:56",
      "to": "lutron:switch-1",
      "relationship": "controls"
    }
  ],
  "zones": {
    "wine-closet": {
      "devices": ["homekit:E8:0A:59:EB:9E:51"],
      "type": "climate-zone"
    }
  }
}
```

### 4. Pairing Storage
**Location**: `.instar/state/devices/pairing/`

Encrypted pairing data per ecosystem:
- `homekit-pairing.json` - Long-term pairing keys
- `lutron-auth.json` - API credentials
- etc.

**Security**: Encrypted at rest, never logged, never in git

### 5. State Cache
**Location**: In-memory with periodic persistence

Live device states for quick queries without hitting devices:
```javascript
{
  "homekit:32:2E:3B:28:5B:E5": {
    "on": true,
    "brightness": 75,
    "lastUpdate": "2026-03-27T12:34:56Z"
  }
}
```

### 6. API Layer
Unified HTTP API endpoints (exposed via Instar server):

```
GET  /devices                    - List all known devices
GET  /devices/:id                - Get device details & state
POST /devices/:id/command        - Control a device
GET  /devices/:id/capabilities   - What can this device do?
GET  /devices/discover/:ecosystem - Scan for devices
POST /devices/:id/pair           - Pair with a device
GET  /devices/zones              - List zones/rooms
GET  /devices/graph              - Get knowledge graph
```

## Implementation Plan

### Phase 1: HomeKit Foundation
1. ✅ Install hap-controller
2. ✅ Create discovery script
3. 🔄 Build HomeKit adapter
4. Create device registry
5. Implement pairing workflow
6. Test with LIFX bulbs (simple on/off/brightness)

### Phase 2: Knowledge Graph
1. Graph data structure
2. Auto-discovery of relationships (bridges → devices)
3. Zone/room mapping
4. Query API

### Phase 3: Additional Ecosystems
1. Lutron adapter (via Smart Bridge API)
2. Native ecobee integration
3. LIFX native API (higher fidelity than HomeKit)

### Phase 4: Intelligence
1. Pattern recognition (device usage)
2. Anomaly detection (devices offline, unexpected states)
3. Automation suggestions

## Current Inventory

### Discovered HomeKit Devices
- HomePod (10.0.0.10) - Sensor
- Smart Bridge Pro 2 (10.0.0.167) - Bridge → Lutron devices
- ecobee3 lite (10.0.0.165) - Thermostat (Wine Closet)
- LIFX Mini W (10.0.0.137) - Lightbulb
- LIFX Mini W (10.0.0.251) - Lightbulb

### Integration Status
- HomeKit: Discovery working, pairing needed
- Lutron: Via Smart Bridge (need credentials)
- LIFX: Can use HomeKit OR native API
- ecobee: Can use HomeKit OR native API

## Security Constraints

**CRITICAL**: Never modify device configurations without explicit human confirmation.

Allowed without confirmation:
- Discovery
- Reading state
- Querying capabilities

Requires confirmation:
- Pairing
- Changing device settings
- Sending control commands
- Modifying automations

## Next Steps

1. Build HomeKit adapter class
2. Create pairing workflow with PIN input
3. Implement basic control (turn lights on/off)
4. Build device registry persistence
5. Expose via API endpoints
