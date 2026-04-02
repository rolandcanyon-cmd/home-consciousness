# Knowledge Graph Integration Plan
## Roland Canyon Home Management System

**Created**: 2026-04-02
**Status**: Planning
**Goal**: Integrate the-goodies knowledge graph system as the backend for Roland Canyon home management

---

## Executive Summary

Replace the current flat-file inventory system (MEMORY.md) with a structured knowledge graph backend using the-goodies (FunkyGibbon server + MCP protocol). This will enable:

- **Queryable device inventory** via MCP tools instead of grep/search
- **Versioned history** of all changes (devices added, configs modified, relationships changed)
- **Structured relationships** between devices, rooms, documentation, and procedures
- **Multi-device sync** capability for future expansion
- **Rich metadata** including manuals, photos, notes, and procedures per device

---

## Current State Analysis

### What We Have Today

**Data Storage:**
- `.instar/MEMORY.md` - flat markdown file with device inventory
- Prose-based descriptions of devices, rooms, and systems
- Manual searches via grep/read operations
- No versioning beyond git commits
- No structured relationships

**Device Categories:**
- 11 rooms across the property
- 5+ device ecosystems (HomeKit, Lutron, Schlage, LIFX, ecobee, etc.)
- 2 weather stations (Tempest, Ambient Weather)
- Pool/spa system (Hayward OmniLogic)
- Whole-house audio (Yamaha)
- 20+ individual devices

**Current Capabilities:**
- Device discovery via HomeKit, web scraping, API calls
- Weather monitoring and reporting
- Basic device inventory maintenance
- iMessage interaction for queries and reports

### Pain Points

1. **Search limitations** - grep-based search is brittle and requires exact text matches
2. **No relationships** - can't easily answer "what controls this device?" or "what's in this room?"
3. **No history** - can't track when devices were added, moved, or reconfigured
4. **No documentation storage** - manuals, photos, wiring diagrams stored elsewhere
5. **Scaling issues** - adding devices means manual MEMORY.md edits
6. **No procedures** - common tasks (reset device, pair new device) exist only in conversation history

---

## Proposed Architecture

### Components

**FunkyGibbon Server**
- Run locally at `http://localhost:8001` (avoiding port conflicts with Instar on 4040)
- SQLite database at `.instar/knowledge-graph.db`
- JWT authentication with token stored in `.instar/config.json`
- REST API + 12 MCP tools

**Integration Layer**
- New module in Instar: `src/knowledge-graph/`
- MCP client wrapper for the 12 tools
- Migration utilities to convert MEMORY.md → graph entities
- Query interface for common operations

**Data Model**
- **HOME entity**: "Roland Canyon" (top-level)
- **ROOM entities**: 11 rooms (Bedroom, Dining Room, Family Room, etc.)
- **DEVICE entities**: Each smart device with manufacturer, model, serial number
- **ZONE entities**: Logical groupings (e.g., "Wine Storage" spanning Garage Storage + Kitchen)
- **APP entities**: Control applications (HomeKit, Lutron app, Hayward app, etc.)
- **MANUAL entities**: Device documentation stored as BLOBs
- **PROCEDURE entities**: Step-by-step instructions for common tasks
- **NOTE entities**: Observations, maintenance logs, troubleshooting notes
- **AUTOMATION entities**: Event-driven rules (separate from scheduled jobs)

### Relationship Types

```
HOME
 ├─ HAS_ROOM → ROOM
 │   ├─ CONTAINS → DEVICE
 │   │   ├─ CONTROLLED_BY_APP → APP
 │   │   ├─ DOCUMENTED_BY → MANUAL (BLOB)
 │   │   ├─ HAS_PROCEDURE → PROCEDURE
 │   │   └─ HAS_NOTE → NOTE
 │   └─ CONNECTED_TO → ROOM (via DOOR/WINDOW)
 └─ HAS_ZONE → ZONE
     └─ SPANS_ROOMS → ROOM
```

---

## Migration Plan

**⚠️ IMPORTANT PREREQUISITE**: The-goodies code was written by Claude ~6 months ago and requires thorough validation before proceeding with integration.

### Phase 0: Code Review & Validation (Week 0 - REQUIRED)

**0.1 Repository Setup**
- Clone the-goodies repository: `git clone https://github.com/adrianco/the-goodies.git ~/the-goodies`
- Review project structure and dependencies
- Check for any security vulnerabilities in dependencies
- Verify Python version requirements

**0.2 Test Suite Validation**
- Install all dependencies (FunkyGibbon, Blowing-off, Inbetweenies, Oook)
- Run full test suite: verify 225 tests actually pass
- Check test coverage and identify untested code paths
- Review test quality (unit vs integration, mocking strategies)
- Document any test failures or warnings

**0.3 Code Quality Review**
- Review FunkyGibbon server implementation
  - FastAPI route handlers and error handling
  - SQLite schema and migration handling
  - JWT authentication implementation
  - Rate limiting and security measures
  - MCP tool implementations
- Review Blowing-off client
  - Sync protocol correctness
  - Conflict resolution logic
  - Offline queuing and recovery
- Review Inbetweenies protocol
  - Entity and relationship models
  - Validation and constraints
  - Versioning strategy

**0.4 Security Audit**
- Review authentication and authorization
- Check for SQL injection vulnerabilities
- Verify input validation and sanitization
- Review BLOB storage security
- Check for sensitive data exposure
- Audit logging completeness

**0.5 Deployment Testing**
- Test FunkyGibbon server startup and configuration
- Verify database initialization and migrations
- Test all 12 MCP tools with sample data
- Test client-server sync with Blowing-off
- Measure performance with realistic data volumes
- Test error handling and recovery scenarios

**0.6 Gap Analysis**
- Identify missing features needed for Roland Canyon
- Document any bugs or issues discovered
- Assess code maintainability and documentation quality
- Determine if fork/modifications will be needed
- Estimate effort to address any issues

**Deliverables:**
- [ ] Full test suite run report (pass/fail status)
- [ ] Code quality assessment document
- [ ] Security audit findings
- [ ] Deployment test results
- [ ] Gap analysis and risk assessment
- [ ] GO/NO-GO decision for proceeding with integration

**Decision Point**: Only proceed to Phase 1 if code review shows the-goodies is production-ready or issues are addressable with reasonable effort.

---

### Phase 1: Setup & Initial Migration (Week 1)

**1.1 Environment Setup**
- Clone the-goodies repository: `git clone https://github.com/adrianco/the-goodies.git ~/the-goodies`
- Install FunkyGibbon server dependencies
- Configure server to run on port 8001
- Generate admin credentials and JWT token
- Test server health and MCP tool availability

**1.2 Core Entity Migration**
- Create HOME entity: "Roland Canyon" at 14450 Roland Canyon Rd
- Create 11 ROOM entities from MEMORY.md:
  - Bedroom, Dining Room, Family Room, Front Bedroom
  - Garage Storage, Guest House, Kitchen, Living Room
  - Pool House, Studio, Workshop
- Create ZONE entity: "Wine Storage" (spans Garage Storage + Kitchen rooms)

**1.3 Device Migration Script**
- Parse MEMORY.md structured inventory
- Convert each device to DEVICE entity with properties:
  - `name`: Device name
  - `type`: Device category (lock, bulb, thermostat, etc.)
  - `manufacturer`: Brand (Schlage, LIFX, ecobee, etc.)
  - `model`: Model number
  - `serial_number`: Serial/MAC if available
  - `ip_address`: IP for networked devices
  - `location`: Room relationship
- Create relationships:
  - `DEVICE --LOCATED_IN--> ROOM`
  - `DEVICE --CONTROLLED_BY_APP--> APP` (HomeKit, Lutron, etc.)

**Deliverables:**
- [ ] FunkyGibbon server running and authenticated
- [ ] HOME + ROOM + ZONE entities created
- [ ] All devices from MEMORY.md migrated to graph
- [ ] Basic relationships established
- [ ] Migration validation report

### Phase 2: Documentation & Enrichment (Week 2)

**2.1 APP Entity Creation**
- Create APP entities for each control ecosystem:
  - Apple Home (HomeKit)
  - Lutron app
  - Schlage Home app
  - LIFX app
  - ecobee app
  - Hayward OmniLogic
  - Ambient Weather Network
  - Yamaha MusicCast
- Link devices to their control apps

**2.2 Documentation Storage**
- Create MANUAL entities for device documentation:
  - Lutron Smart Bridge Pro 2 manual
  - Schlage lock installation guides
  - ecobee thermostat manual
  - Hayward OmniLogic user guide
  - Yamaha RX-A1070 manual
- Store as BLOB entities with PDF/image data
- Create `DOCUMENTED_BY` relationships

**2.3 Procedure Documentation**
- Create PROCEDURE entities for common tasks:
  - "Reset Lutron Bridge"
  - "Pair new Schlage lock to HomeKit"
  - "Replace LIFX bulb"
  - "Calibrate ecobee sensor"
  - "Add new Ambient Weather device"
- Each procedure includes step-by-step markdown content

**Deliverables:**
- [ ] APP entities for all control systems
- [ ] Device-to-app relationships established
- [ ] Key device manuals stored as BLOBs
- [ ] 10+ common procedures documented
- [ ] Documentation accessibility tested

### Phase 3: Integration with Instar (Week 3)

**3.1 MCP Client Integration**
- Create `src/knowledge-graph/mcp-client.js` wrapper
- Implement convenience methods for common queries:
  - `getDevicesInRoom(roomName)`
  - `getDeviceDetails(deviceName)`
  - `findDeviceManual(deviceName)`
  - `getProceduresForDevice(deviceName)`
  - `searchDevices(query)`
- Add authentication and error handling

**3.2 API Endpoints**
- Add Instar REST endpoints:
  - `GET /knowledge-graph/devices` - list all devices
  - `GET /knowledge-graph/rooms` - list all rooms
  - `GET /knowledge-graph/devices/:id` - device details
  - `GET /knowledge-graph/search?q=...` - search entities
  - `GET /knowledge-graph/room/:room/devices` - devices in room
  - `POST /knowledge-graph/note` - add note to device

**3.3 Update Existing Features**
- Modify device query commands to use graph instead of MEMORY.md
- Update morning weather job to log temperature readings as NOTE entities
- Create graph query skill for conversational device lookup

**Deliverables:**
- [ ] MCP client wrapper module
- [ ] Instar API endpoints for graph access
- [ ] Device queries migrated from MEMORY.md to graph
- [ ] Integration tests passing

### Phase 4: Enhanced Features (Week 4)

**4.1 Visual Browsing**
- Create dashboard page for graph visualization
- Show rooms with device counts
- Click through to device details with manuals/procedures
- Search interface with autocomplete

**4.2 Note Taking**
- Enable adding notes to devices via iMessage
  - "Note for pool heater: making clicking noise"
  - "Remind me about wine closet door sensor low battery"
- Notes stored with timestamp and source

**4.3 History & Audit Trail**
- Leverage immutable versioning for:
  - Device addition/removal tracking
  - Configuration change history
  - Relationship modifications
  - Note and procedure updates

**4.4 Maintenance Tracking**
- Create SCHEDULE entities for maintenance tasks:
  - Replace HVAC filters (quarterly)
  - Test smoke detectors (monthly)
  - Check Schlage lock batteries (annually)
- Link schedules to devices
- Job to check upcoming maintenance

**Deliverables:**
- [ ] Dashboard UI for graph browsing
- [ ] Note-taking via iMessage working
- [ ] History/audit queries functional
- [ ] Maintenance schedule system deployed

---

## Technical Implementation Details

### Data Migration Script

**Location**: `.instar/scripts/migrate-to-knowledge-graph.js`

**Process:**
1. Read `.instar/MEMORY.md`
2. Parse structured sections (Rooms, Devices, etc.)
3. Create entities via MCP tools:
   - `create_entity({type: "ROOM", name: "Bedroom", content: {...}})`
   - `create_entity({type: "DEVICE", name: "Schlage Lock - Kitchen Garage", content: {...}})`
4. Create relationships:
   - `create_relationship({source: deviceId, target: roomId, type: "LOCATED_IN"})`
5. Generate migration report with entity counts and validation

**Validation:**
- Count entities created vs. expected
- Verify all devices have room relationships
- Check for orphaned entities
- Test sample queries

### Query Examples

**Before (grep-based):**
```javascript
const memory = await fs.readFile('.instar/MEMORY.md', 'utf8');
const schlageMatch = memory.match(/Schlage.*Kitchen Garage/);
```

**After (MCP-based):**
```javascript
const devices = await mcpClient.searchEntities({
  query: 'Kitchen Garage',
  entity_types: ['DEVICE']
});
const schlage = devices.find(d => d.name.includes('Schlage'));
const details = await mcpClient.getEntityDetails(schlage.id);
```

### Configuration

**`.instar/config.json` additions:**
```json
{
  "knowledgeGraph": {
    "enabled": true,
    "serverUrl": "http://localhost:8001",
    "authToken": "jwt-token-here",
    "database": ".instar/knowledge-graph.db"
  }
}
```

---

## Benefits Analysis

### Immediate Benefits

1. **Queryable Inventory**
   - Natural language searches: "Schlage locks" → all lock entities
   - Room-based queries: "What's in the Pool House?" → device list
   - Relationship traversal: "What controls the bedroom lights?" → LIFX app

2. **Structured Documentation**
   - Device manuals accessible by device name
   - Procedures attached to relevant devices
   - Notes timestamped and searchable

3. **Version History**
   - Track when devices were added
   - See configuration changes over time
   - Audit trail for troubleshooting

### Long-term Benefits

4. **Multi-Device Sync**
   - Access graph from phone, tablet, laptop
   - Blowing-off client for offline access
   - Real-time updates across devices

5. **Automation Intelligence**
   - Store automation rules as entities
   - Query dependencies: "What automations use this sensor?"
   - Test automation impact before deployment

6. **Maintenance Tracking**
   - Schedule-based maintenance reminders
   - History of service performed
   - Warranty and lifecycle tracking

7. **Extensibility**
   - Add new entity types as needs evolve
   - Custom relationship types for specific use cases
   - Integration with other systems via MCP protocol

---

## Risks & Mitigations

### Risk 1: Server Availability
**Risk**: FunkyGibbon server down → graph queries fail
**Mitigation**:
- Keep MEMORY.md as read-only backup
- Health monitoring with auto-restart
- Client-side caching via Blowing-off

### Risk 2: Migration Accuracy
**Risk**: Data loss or corruption during migration
**Mitigation**:
- Test migration on copy of MEMORY.md first
- Validate entity counts and relationships
- Keep MEMORY.md untouched until validation complete
- Rollback plan: disable graph integration, use MEMORY.md

### Risk 3: Performance
**Risk**: Graph queries slower than flat file reads
**Mitigation**:
- SQLite is fast for this data size (<1000 entities)
- Add caching layer if needed
- Benchmark queries during testing phase

### Risk 4: Complexity
**Risk**: System becomes harder to understand/maintain
**Mitigation**:
- Comprehensive documentation
- Dashboard UI for visual exploration
- Keep simple text export option (graph → markdown)

---

## Success Criteria

### Must Have (MVP)
- [ ] All devices from MEMORY.md migrated to graph
- [ ] Room-based device queries working
- [ ] Device search functional via MCP tools
- [ ] Integration with existing Instar features (no regressions)
- [ ] Documentation for graph usage

### Should Have (V1)
- [ ] Device manuals stored and retrievable
- [ ] Common procedures documented
- [ ] Note-taking via iMessage enabled
- [ ] Dashboard UI for browsing
- [ ] History/audit queries functional

### Nice to Have (Future)
- [ ] Multi-device sync with Blowing-off client
- [ ] Maintenance schedule tracking
- [ ] Photo storage for devices (wiring diagrams, install pics)
- [ ] Automation rule modeling
- [ ] Graph export/backup utilities

---

## Timeline Estimate

**Total Duration**: 4 weeks (assuming ~10 hours/week)

- **Week 1**: Setup + core migration (10 hours)
- **Week 2**: Documentation enrichment (8 hours)
- **Week 3**: Instar integration (12 hours)
- **Week 4**: Enhanced features + testing (10 hours)

**Total Effort**: ~40 hours

**Critical Path**:
1. FunkyGibbon setup → Migration script → Validation
2. MCP client → API endpoints → Feature integration
3. Testing → Documentation → Deployment

---

## Next Steps

### Immediate Actions
1. Review this plan with Adrian for approval
2. Clone the-goodies repository
3. Set up FunkyGibbon development environment
4. Create migration script skeleton
5. Test migration with sample data (5 devices, 2 rooms)

### Decision Points
- [ ] Confirm port 8001 for FunkyGibbon (or select alternative)
- [ ] Decide on database location (`.instar/knowledge-graph.db` or separate?)
- [ ] Choose authentication approach (JWT vs. other)
- [ ] Determine MEMORY.md deprecation timeline (keep as backup? how long?)

### Questions for Adrian
1. Are there specific device documentation files you already have that should be migrated?
2. Any existing procedures/workflows that should become PROCEDURE entities?
3. Priority order for the 4 phases - can any be reordered or combined?
4. Should we run FunkyGibbon as a persistent service or on-demand?

---

## Appendix

### Entity Type Mapping

| Current (MEMORY.md) | Target (Graph Entity) | Notes |
|---------------------|----------------------|-------|
| Room sections | ROOM entities | 11 rooms |
| Device listings | DEVICE entities | ~20+ devices |
| Wine storage note | ZONE entity | Spans multiple rooms |
| Ecosystem descriptions | APP entities | HomeKit, Lutron, etc. |
| N/A | MANUAL entities | New capability |
| N/A | PROCEDURE entities | New capability |
| Operational patterns | NOTE entities | Convert learnings to notes |

### Sample Entity Structures

**DEVICE Entity (Schlage Lock):**
```json
{
  "id": "device-001",
  "type": "DEVICE",
  "name": "Schlage Lock - Kitchen Garage",
  "content": {
    "manufacturer": "Schlage",
    "model": "BE479CAM716",
    "serial_number": "0000000000097562",
    "device_type": "lock",
    "purchase_date": "2024-01-15",
    "warranty_expires": "2029-01-15"
  },
  "created_at": "2026-04-02T00:00:00Z",
  "version": 1
}
```

**ROOM Entity:**
```json
{
  "id": "room-001",
  "type": "ROOM",
  "name": "Kitchen",
  "content": {
    "floor": "main",
    "square_feet": 450,
    "notes": "Central hub of the house"
  },
  "created_at": "2026-04-02T00:00:00Z",
  "version": 1
}
```

**PROCEDURE Entity:**
```json
{
  "id": "proc-001",
  "type": "PROCEDURE",
  "name": "Reset Lutron Smart Bridge Pro 2",
  "content": {
    "steps": [
      "Unplug the Smart Bridge from power",
      "Wait 10 seconds",
      "Plug back in and wait for solid white light",
      "If blinking, factory reset: hold reset button 10 seconds",
      "Re-pair devices via Lutron app"
    ],
    "duration_minutes": 5,
    "difficulty": "easy"
  },
  "created_at": "2026-04-02T00:00:00Z",
  "version": 1
}
```

### Reference Links

- **the-goodies repository**: https://github.com/adrianco/the-goodies
- **Model Context Protocol**: https://modelcontextprotocol.io/
- **Current MEMORY.md**: `.instar/MEMORY.md`
- **This plan**: `.instar/plans/knowledge-graph-integration.md`

---

**Document Control**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-04-02 | Roland (Agent) | Initial planning document |
