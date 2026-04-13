# Vantage InFusion Integration Spec
## for the-goodies / c11s-house

**Status:** Draft  
**Author:** Adrian Cockcroft  
**Scope:** System architecture, UI replacement strategy, knowledge graph ingestion

---

## 1. System Architecture

### 1.1 Physical Layer

The house automation system is built around a **Vantage InFusion Controller** (IC or IC-II). This is the "brain" — it runs the programmed logic, manages all connected devices, and exposes network APIs. It sits on the local LAN with a static IP.

All physical devices (dimmers, keypads, relays, thermostats, shade motors, dry contacts, sensors) communicate with the controller over a proprietary WireLink or RadioLink bus. The controller is the single integration point — nothing talks peer-to-peer.

### 1.2 Configuration Tool: Design Center (VDC)

**Version in use:** 3.9.x (Windows, runs in Parallels)

VDC is the authoring environment for two distinct outputs:

| Output | Format | Destination |
|--------|--------|-------------|
| System config | `.dc` binary | Uploaded to InFusion controller |
| UI config | `LcdConfig.xml` + images (zipped) | Sideloaded into Home Control app |

These are independent files with independent lifecycles. Changing one does not require changing the other, **except** that VIDs (Vantage IDs) embedded in the UI config must match the system config.

### 1.3 The .dc File

The `.dc` file is a proprietary compiled format produced by VDC. Its internal structure is not publicly documented by Vantage/Legrand. However, the controller exposes its full runtime representation of this file as XML over the network (see §1.5), so direct manipulation of the `.dc` file is rarely necessary.

VDC uploads the `.dc` to the controller via TCP port **2001** during a "Program" or "Update" operation. The controller stores and executes it. Remote programming requires ports **2001** and **3001** to be accessible.

### 1.4 The UI Config (LcdConfig.xml)

Produced by VDC's **Touchscreen Designer** via Design → Export. The export creates:

```
export/
  LcdConfig.xml       ← entire UI definition in XML
  Images/             ← all graphic assets referenced by the XML
    background.png
    button_on.png
    ...
  Fonts/              ← optional, custom .ttf files
```

This ZIP is loaded into the **Home Control** iOS/iPad app via iTunes File Sharing (or cloud upload depending on app version). The app renders the UI by parsing `LcdConfig.xml` and resolving image references at runtime.

**Key insight:** `LcdConfig.xml` is plain XML. It can be read, modified, and regenerated entirely outside of VDC once the schema is understood. The app is just a renderer.

### 1.5 Controller Network APIs

The InFusion controller exposes two TCP interfaces simultaneously:

#### Port 2001 — XML Introspection API
Used by VDC for programming and by integration libraries for config discovery.

- **Authentication:** Username/password (set in VDC under Settings → Project Security). User must be in Admin group with Read State, Write State, and Read Config permissions.
- **Protocol:** XML over raw TCP socket
- **Primary use:** Fetch the complete object database as base64-encoded XML

Key request to retrieve the full config XML:
```xml
<IIntrospection><GetFile><call></call></GetFile></IIntrospection>\n
```

The response contains the entire system configuration as a base64 blob, decoded to XML with all objects and their VIDs.

Object types present in the XML database include:
- `Load` — dimmable lights, switched loads
- `Vantage.DDGColorLoad` — color/RGBW loads via DMX/DALI gateway
- `LoadGroup` — grouped loads (scenes)
- `Keypad` / `DualRelayStation` / `Dimmer` — station types
- `EqCtrl` / `EqUX` — Equinox touchscreen objects
- `Task` — programmed automation tasks
- `GMem` — variables (boolean, numeric, text)
- `Thermostat` / `VirtualThermostat` / `HVAC-IU` — climate objects
- `Blind` / `BlindGroup` / `QISBlind` / `RelayBlind` — shade/cover objects
- `DryContact` — binary sensors (motion, door contacts, etc.)
- `AnemoSensor` / `LightSensor` / `Temperature` / `OmniSensor` — environmental sensors
- `Area` — room/zone hierarchy

Every object has a **VID** (Vantage ID) — a unique integer that is the stable identifier for that object across all APIs.

#### Port 3001 — Host Commands (plain text)
Used for real-time control and monitoring. Telnet-compatible.

- **Authentication:** None by default (or same credentials as port 2001 depending on config)
- **Protocol:** Plain ASCII, newline-terminated commands

**Send to controller:**
```
LOAD <VID> <level 0-100>           # set load level
RAMPLOAD <VID> <level> <seconds>   # ramp to level over time
GETLOAD <VID>                      # query current level
INVOKE <task VID>                  # execute a task
TASK <task VID> PRESS              # trigger task with PRESS trigger
TASK <task VID> HOLD               # trigger task with HOLD trigger
TASK <task VID> RELEASE            # trigger task with RELEASE trigger
BTNPRESS <button VID>              # simulate button press
BTNRELEASE <button VID>            # simulate button release
LED <btn VID> <r1> <g1> <b1> <r2> # set button LED colors
STATUS <VID>                       # get object status
GETTHERMSTAT <VID>                 # get thermostat state
THERMFAN <VID> <ON|AUTO>           # set fan mode
THERMOP <VID> <HEAT|COOL|AUTO|OFF> # set operating mode
THERMSETPOINT <VID> <temp>         # set temperature setpoint
help                               # list all available commands
```

**Received from controller (push events):**
```
LOAD <VID> <level>                 # load level changed
BTN <VID>                          # button toggled
BTNPRESS <VID>                     # button pressed
BTNRELEASE <VID>                   # button released
STATUS <VID> <value>               # object status update
THERMTEMP <VID> <temp>             # temperature reading
```

The controller pushes state changes in real time, making port 3001 suitable for event-driven integrations without polling.

---

## 2. UI Replacement Strategy

### 2.1 Current Situation

The current UI is authored in VDC's Touchscreen Designer, exported as `LcdConfig.xml` + images, and loaded into the Home Control iOS app. The app is described as "crappy" — it is a thin renderer that faithfully executes whatever the XML describes, but the authoring workflow (Windows → Parallels → VDC → export → zip → iTunes) is painful.

### 2.2 Option A: Edit LcdConfig.xml Directly

**Approach:** Export the current UI zip from VDC (or extract from the device via iTunes File Sharing), edit `LcdConfig.xml` in a text editor or programmatically, re-zip, re-sideload.

**Pros:**
- No VDC required for UI changes after initial export
- XML is fully readable once schema is understood
- Can be scripted/templated
- Works within the existing app — no new iOS development needed

**Steps:**
1. In VDC Touchscreen Designer: Design → Export Files → choose output directory
2. Inspect and document the `LcdConfig.xml` schema (page elements, button types, VID bindings, navigation links)
3. Build a Python script that reads the controller's XML DB (port 2001) and generates or patches `LcdConfig.xml` entries
4. Re-zip and sideload via iTunes or app's cloud upload

**Cons:**
- Still dependent on the Home Control app as renderer
- App limitations remain (layout constraints, no custom logic)
- Must re-sideload after every UI change

### 2.3 Option B: Build a Custom iOS App

**Approach:** Use `aiovantage` or direct TCP socket communication from the `c11s-house-iOS` app to talk to the controller at port 3001, and port 2001 for config discovery. Bypass the Home Control app entirely.

**Pros:**
- Full control over UX, layout, animations
- Can integrate with WeatherKit, HomeKit, and other the-goodies data sources in the same app
- Native Swift/SwiftUI — fits the existing `c11s-house-iOS` rebuild project
- No Windows/Parallels/VDC needed at runtime
- Real-time push updates from port 3001 rather than polling

**Architecture:**

```
c11s-house-iOS
    └── VantageClient (Swift actor)
            ├── TCP socket → port 2001 (config discovery, one-time on startup)
            └── TCP socket → port 3001 (real-time control + events, persistent)
```

**Protocol layer (Swift):**
```swift
actor VantageClient {
    // Connect to port 2001, fetch XML DB, parse VIDs
    func loadObjectDatabase() async throws -> VantageObjectDB
    
    // Connect to port 3001, maintain persistent connection
    func connect() async throws
    
    // Send host commands
    func setLoad(_ vid: Int, level: Double) async throws
    func rampLoad(_ vid: Int, level: Double, over seconds: Double) async throws
    func invokeTask(_ vid: Int) async throws
    
    // Receive push events (AsyncStream)
    var events: AsyncStream<VantageEvent> { get }
}
```

**Cons:**
- More upfront development work
- Must handle TCP reconnection, error recovery
- Duplicates some functionality already in aiovantage (Python), though Swift rewrite is clean

### 2.4 Option C: Home Assistant as Middleware

**Approach:** Use the `loopj/home-assistant-vantage` integration (built on `aiovantage`) to bridge Vantage into Home Assistant. Then build a minimal iOS app or use the HA app/Lovelace as the UI.

**Pros:**
- Zero protocol implementation — just configure HA
- Automations, history, energy tracking come for free
- Can layer on top of existing HA instance (already present in the-goodies ecosystem)
- `aiovantage` handles reconnection, SSL, entity discovery automatically

**Cons:**
- HA as a dependency for house control is a single point of failure
- Lovelace UI is generic, not house-specific
- Less integrated with c11s-house-iOS vision

### 2.5 Recommendation

Use a **hybrid approach:**

1. **Short term:** Export and document `LcdConfig.xml`, edit directly for quick fixes. Eliminates the Parallels → VDC → Touchscreen Designer → export loop for UI-only changes.

2. **Medium term:** Add `VantageClient` as a module in `c11s-house-iOS`. Implement port 3001 control and push events. This integrates Vantage into the house consciousness app natively, alongside HomeKit, WeatherKit, and the conversational interface.

3. **Parallel:** Wire Vantage into Home Assistant via `aiovantage` for automation, history, and as a fallback control surface. HA talks to the controller independently of the iOS app.

---

## 3. Knowledge Graph Ingestion

### 3.1 Data to Extract

The controller's XML DB (port 2001) contains the complete structural and semantic description of the house from Vantage's perspective. This is valuable first-class data for the-goodies knowledge graph.

**Structural data (static, extracted once or on config change):**
- Area hierarchy (rooms → zones → house)
- Load definitions (name, type, area, VID)
- Load groups / scenes
- Keypad button definitions and their VID bindings
- Task definitions
- Thermostat objects
- Sensor objects (dry contacts, light sensors, temperature)
- Variable (GMem) definitions

**Runtime state (dynamic, updated via port 3001 events):**
- Current load levels (0-100%)
- Current thermostat setpoints and actual temperatures
- Current sensor states (open/closed, motion/clear)
- Current variable values
- Task execution events

### 3.2 Extraction Script

A Python script (`vantage_extract.py`) in the FunkyGibbon component:

```python
import asyncio
import ssl
import xml.etree.ElementTree as ET
import base64
import json

CONTROLLER_IP = "..."
USERNAME = "..."
PASSWORD = "..."

async def fetch_xml_db() -> ET.Element:
    """Connect to port 2001, authenticate, fetch and decode the full object XML."""
    reader, writer = await asyncio.open_connection(
        CONTROLLER_IP, 2001,
        ssl=ssl.create_default_context()
    )
    # Send auth + GetFile request
    writer.write(
        f'<IIntrospection><Login><call><User>{USERNAME}</User>'
        f'<Password>{PASSWORD}</Password></call></Login></IIntrospection>\n'
        .encode()
    )
    writer.write(
        b'<IIntrospection><GetFile><call></call></GetFile></IIntrospection>\n'
    )
    await writer.drain()
    
    data = await reader.read(1024 * 1024)  # read full response
    writer.close()
    
    root = ET.fromstring(data)
    b64 = root.find("GetFile/return")
    xml_text = base64.b64decode(b64.text).decode("utf-8")
    return ET.fromstring(xml_text)

def extract_objects(root: ET.Element) -> list[dict]:
    """Walk the Area hierarchy, extract all objects with their context."""
    objects = []
    
    def walk(node: ET.Element, area_path: list[str]):
        vid = node.get("VID")
        name = node.get("Name", node.get("DName", ""))
        tag = node.tag
        
        if tag == "Area":
            area_path = area_path + [name]
        
        if vid and tag not in ("Area", "Design", "Object"):
            objects.append({
                "vid": int(vid),
                "type": tag,
                "name": name,
                "area_path": list(area_path),
                "area": area_path[-1] if area_path else None,
                "attributes": {k: v for k, v in node.attrib.items() 
                               if k not in ("VID", "Name", "DName")},
            })
        
        for child in node:
            walk(child, area_path)
    
    walk(root, [])
    return objects

def to_graph_nodes(objects: list[dict]) -> list[dict]:
    """Convert extracted objects to knowledge graph node format."""
    nodes = []
    for obj in objects:
        node = {
            "id": f"vantage:vid:{obj['vid']}",
            "labels": ["VantageObject", obj["type"]],
            "properties": {
                "vid": obj["vid"],
                "name": obj["name"],
                "type": obj["type"],
                "area": obj["area"],
                "area_path": " > ".join(obj["area_path"]),
                **obj["attributes"],
            }
        }
        # Add area relationship
        if obj["area"]:
            node["relationships"] = [{
                "type": "IN_AREA",
                "target": f"vantage:area:{obj['area']}",
            }]
        nodes.append(node)
    return nodes
```

### 3.3 Knowledge Graph Schema

New node types to add to the-goodies graph:

```
(:VantageArea {name, path, vid})
(:VantageLoad {vid, name, type, area, min_level, max_level})
(:VantageScene {vid, name, area})
(:VantageTask {vid, name, area})
(:VantageThermostat {vid, name, area})
(:VantageSensor {vid, name, sensor_type, area})
(:VantageVariable {vid, name, data_type})
(:VantageKeypad {vid, name, area, button_count})
(:VantageButton {vid, name, keypad_vid})
```

Relationships:

```
(:VantageLoad)-[:IN_AREA]->(:VantageArea)
(:VantageArea)-[:PART_OF]->(:VantageArea)          # room → floor → house
(:VantageButton)-[:ON_KEYPAD]->(:VantageKeypad)
(:VantageButton)-[:CONTROLS]->(:VantageLoad)        # where determinable
(:VantageButton)-[:TRIGGERS]->(:VantageTask)
(:VantageArea)-[:HAS_THERMOSTAT]->(:VantageThermostat)
(:VantageLoad)-[:SAME_AS]->(:HomeKitAccessory)      # cross-reference to HomeKit
```

### 3.4 Runtime State as Graph Properties

Rather than creating separate state nodes, maintain current state as properties on existing nodes, updated via the port 3001 event stream:

```
(:VantageLoad {
    vid: 42,
    name: "Living Room Overhead",
    area: "Living Room",
    current_level: 75.0,        ← updated on LOAD events
    last_changed: "2025-04-04T10:23:00Z"
})

(:VantageThermostat {
    vid: 88,
    name: "Living Room Thermostat",
    current_temp: 68.5,         ← updated on THERMTEMP events
    setpoint_heat: 70.0,
    setpoint_cool: 76.0,
    mode: "HEAT",
    fan: "AUTO",
})
```

### 3.5 Ingestion Pipeline

```
Controller (port 2001)
    │  XML DB (one-time fetch, or on config change)
    ▼
vantage_extract.py
    │  List of dicts
    ▼
graph_writer.py (FunkyGibbon)
    │  Upsert nodes/relationships by VID
    ▼
the-goodies knowledge graph (Neo4j / RuVector)

Controller (port 3001)
    │  Push events (persistent connection)
    ▼
vantage_listener.py
    │  VantageEvent objects
    ▼
graph_state_updater.py
    │  Update node properties by VID
    ▼
the-goodies knowledge graph
    │
    └── Inbetweenies sync → c11s-house-iOS
```

### 3.6 Cross-Referencing with HomeKit

Vantage controls the physical hardware; HomeKit (via the existing c11s-house ecosystem) may have overlapping coverage. After Vantage ingestion, a reconciliation pass should:

1. Match `VantageLoad.name` against `HomeKitAccessory.name` (fuzzy match by area + name)
2. Create `(:VantageLoad)-[:SAME_AS]->(:HomeKitAccessory)` where confident
3. Flag ambiguous matches for manual review
4. Use the graph to answer "what controls this load?" queries from the conversational interface

---

## 4. Open Questions

| # | Question | Impact |
|---|----------|--------|
| 1 | What is the exact internal format of the `.dc` file? (Upload for analysis) | Determines if config can be generated without VDC |
| 2 | Is the controller running firmware 2.3+? | Required for SSL on port 2001 |
| 3 | Does the current Home Control app use `LcdConfig.xml` or a different format? | Determines UI editability |
| 4 | What username/password is configured on the controller? | Required for port 2001 auth |
| 5 | Is the controller on a stable IP or DHCP? | mDNS discovery vs. static config |
| 6 | Which loads overlap with HomeKit coverage? | Reconciliation complexity |

---

## 5. Immediate Next Steps

1. **Upload `.dc` file** → analyze format, understand if VIDs are stable identifiers that survive VDC edits
2. **Export UI zip from VDC** → examine `LcdConfig.xml` schema, identify button→VID bindings
3. **Telnet to port 3001** (`telnet <controller-ip> 3001`) → type `help` → confirm available commands and auth requirements
4. **Run `vantage_extract.py`** against port 2001 → dump full object list as JSON → review what the graph will contain
5. **Decide on UI path** (Option A quick fix vs. Option B native iOS vs. Option C HA bridge)
