#!/usr/bin/env python3
"""
vantage_dc_parser.py — Parse a VDC-exported .dc project file into structured data.

The runtime Vantage controller only exposes a subset of its configured objects
via the port 2001 API. The full hierarchy (rooms organizing rooms, keypad
layouts, detailed metadata) lives in VDC's `.dc` project file, which is plain
XML despite the proprietary-looking name.

This parser extracts everything useful and writes it to a JSON inventory that
the room-walk skill can use as the source of truth for area hierarchy.

Usage:
    from vantage_dc_parser import parse_dc_file

    inv = parse_dc_file('/Users/rolandcanyon/.instar/agents/Roland/.instar/context/project.dc')
    # inv has: areas, area_fragments, loads, stations, buttons, tasks, thermostats, ...

CLI:
    python3 vantage_dc_parser.py <file.dc>                   # print summary
    python3 vantage_dc_parser.py <file.dc> --save <out.json> # write inventory to JSON
    python3 vantage_dc_parser.py <file.dc> --tree            # show area hierarchy
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional

PROJECT_DIR = os.environ.get(
    "CLAUDE_PROJECT_DIR",
    "/Users/rolandcanyon/.instar/agents/Roland",
)
DEFAULT_DC_PATH = os.path.join(PROJECT_DIR, ".instar", "context", "project.dc")


def _text(elem: Optional[ET.Element], default: Any = None) -> Any:
    """Return stripped text or default."""
    if elem is None or elem.text is None:
        return default
    return elem.text.strip()


def _int(elem: Optional[ET.Element], default: Optional[int] = None) -> Optional[int]:
    v = _text(elem)
    if v in (None, ""):
        return default
    try:
        return int(v)
    except ValueError:
        return default


def parse_dc_file(path: str) -> Dict[str, Any]:
    """Parse a .dc XML project file into a structured inventory dict."""
    tree = ET.parse(path)
    root = tree.getroot()

    areas: List[Dict[str, Any]] = []
    area_fragments: List[Dict[str, Any]] = []
    loads: List[Dict[str, Any]] = []
    stations: List[Dict[str, Any]] = []  # Keypad, Dimmer, ScenePointRelay, etc.
    buttons: List[Dict[str, Any]] = []
    tasks: List[Dict[str, Any]] = []
    thermostats: List[Dict[str, Any]] = []
    dry_contacts: List[Dict[str, Any]] = []
    omni_sensors: List[Dict[str, Any]] = []
    temperatures: List[Dict[str, Any]] = []
    gmems: List[Dict[str, Any]] = []
    keypads: List[Dict[str, Any]] = []
    back_boxes: List[Dict[str, Any]] = []
    others_by_type: Dict[str, int] = {}

    # Station-like object types (carry buttons)
    STATION_TYPES = {
        "Keypad", "Dimmer", "DualRelayStation", "ScenePointRelay",
        "LowVoltageRelayStation", "HighVoltageRelayStation",
        "DINHighVoltageRelayStation", "DINLowVoltageRelayStation",
        "DINStation", "DINContactInput", "ContactInput",
        "RFAccentPointDimmer", "RS232Station", "RS485Station",
    }

    for obj_node in root.iter("Object"):
        # Each <Object> wraps exactly one child whose tag is the object type.
        for child in obj_node:
            type_name = child.tag
            vid = int(child.get("VID", 0))
            name = _text(child.find("Name"), "")
            area_vid = _int(child.find("Area"))
            parent_vid = _int(child.find("Parent"))
            location = _text(child.find("Location"))

            base = {
                "vid": vid,
                "name": name,
                "type": type_name,
                "area_vid": area_vid,
                "parent_vid": parent_vid,
                "location": location,
            }

            if type_name == "Area":
                base["area_type"] = _text(child.find("AreaType"))
                base["display_name"] = _text(child.find("DName"))
                areas.append(base)

            elif type_name == "AreaFragment":
                area_fragments.append(base)

            elif type_name == "Load":
                base["load_type"] = _text(child.find("LoadType"))
                base["contractor_number"] = _text(child.find("ContractorNumber"))
                base["power"] = _text(child.find("Power"))
                base["dimming_config"] = _text(child.find("DimmingConfig"))
                loads.append(base)

            elif type_name == "Button":
                base["station_vid"] = parent_vid  # button's parent is its station
                base["text1"] = _text(child.find("Text1"))
                base["text2"] = _text(child.find("Text2"))
                base["button_number"] = _int(child.find("ButtonNumber"))
                base["button_position"] = _int(child.find("Position"))
                buttons.append(base)

            elif type_name == "Task":
                base["display_name"] = _text(child.find("DName"))
                base["state"] = _text(child.find("State"))
                tasks.append(base)

            elif type_name == "Thermostat":
                thermostats.append(base)

            elif type_name == "DryContact":
                dry_contacts.append(base)

            elif type_name == "OmniSensor":
                omni_sensors.append(base)

            elif type_name == "Temperature":
                temperatures.append(base)

            elif type_name == "GMem":
                base["data_type"] = _text(child.find("DataType"))
                gmems.append(base)

            elif type_name == "Keypad":
                base["station_type"] = type_name
                base["button_count"] = len([
                    b for b in root.iter("Button") if _int(b.find("Parent")) == vid
                ])
                keypads.append(base)
                stations.append(base)

            elif type_name in STATION_TYPES:
                base["station_type"] = type_name
                stations.append(base)

            elif type_name == "BackBox":
                back_boxes.append(base)

            else:
                others_by_type[type_name] = others_by_type.get(type_name, 0) + 1

    return {
        "source": path,
        "file_version": root.get("FileVersion"),
        "design_center_version": root.get("DesignCenterVersion"),
        "areas": areas,
        "area_fragments": area_fragments,
        "loads": loads,
        "stations": stations,
        "keypads": keypads,
        "buttons": buttons,
        "tasks": tasks,
        "thermostats": thermostats,
        "dry_contacts": dry_contacts,
        "omni_sensors": omni_sensors,
        "temperatures": temperatures,
        "gmems": gmems,
        "back_boxes": back_boxes,
        "other_type_counts": others_by_type,
    }


def build_area_lookup(inv: Dict[str, Any]) -> Dict[int, Dict[str, Any]]:
    """Build a vid→area dict that includes BOTH Area and AreaFragment objects
    since the 'Area' field on loads/stations can reference either."""
    lookup = {}
    for a in inv["areas"]:
        lookup[a["vid"]] = {**a, "_kind": "Area"}
    for a in inv["area_fragments"]:
        lookup[a["vid"]] = {**a, "_kind": "AreaFragment"}
    return lookup


def resolve_area_path(
    area_vid: Optional[int],
    area_lookup: Dict[int, Dict[str, Any]],
    max_depth: int = 10,
) -> List[str]:
    """Walk the area chain upward, returning [parent_name, ..., leaf_name]."""
    path = []
    seen = set()
    current = area_vid
    for _ in range(max_depth):
        if current is None or current in seen:
            break
        seen.add(current)
        entry = area_lookup.get(current)
        if not entry:
            break
        path.append(entry["name"])
        current = entry.get("parent_area_vid")
    return list(reversed(path))


def print_tree(inv: Dict[str, Any]) -> None:
    lookup = build_area_lookup(inv)

    # Count items per area
    loads_per = {}
    stations_per = {}
    for l in inv["loads"]:
        loads_per[l["area_vid"]] = loads_per.get(l["area_vid"], 0) + 1
    for s in inv["stations"]:
        stations_per[s["area_vid"]] = stations_per.get(s["area_vid"], 0) + 1

    # Children map
    kids = {}
    for vid, e in lookup.items():
        parent = e.get("parent_area_vid")
        kids.setdefault(parent, []).append(e)

    def walk(parent_vid, indent=0):
        nodes = sorted(kids.get(parent_vid, []), key=lambda x: x["name"])
        for n in nodes:
            if n["_kind"] == "AreaFragment":
                continue  # AreaFragments just add clutter in the tree view
            n_loads = loads_per.get(n["vid"], 0)
            n_stations = stations_per.get(n["vid"], 0)
            counts = []
            if n_loads:
                counts.append(f"{n_loads} loads")
            if n_stations:
                counts.append(f"{n_stations} stations")
            count_str = f" ({', '.join(counts)})" if counts else ""
            print(f"{'  '*indent}[{n['vid']:>5}] {n['name']}{count_str}")
            walk(n["vid"], indent + 1)

    # Roots: parent is None, 0, or points to something not in lookup
    roots = []
    for vid, e in lookup.items():
        parent = e.get("parent_area_vid")
        if parent in (None, 0) or parent not in lookup:
            if e["_kind"] == "Area":
                roots.append(e)
    for r in sorted(roots, key=lambda x: x["name"]):
        n_loads = loads_per.get(r["vid"], 0)
        count_str = f" ({n_loads} loads)" if n_loads else ""
        print(f"[{r['vid']:>5}] {r['name']}{count_str}")
        walk(r["vid"], 1)


def _cli() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("file", nargs="?", default=DEFAULT_DC_PATH)
    p.add_argument("--save", help="Write full inventory as JSON")
    p.add_argument("--tree", action="store_true", help="Show area hierarchy")
    p.add_argument("--area", type=int, help="Show contents of a specific area VID (loads, stations)")
    args = p.parse_args()

    if not os.path.exists(args.file):
        print(f"File not found: {args.file}", file=sys.stderr)
        return 1

    inv = parse_dc_file(args.file)

    if args.save:
        with open(args.save, "w") as f:
            json.dump(inv, f, indent=2, default=str)
        print(f"Wrote {args.save} ({sum(len(inv[k]) for k in ('areas','loads','stations','buttons','tasks'))}+ objects)")
        return 0

    if args.area:
        lookup = build_area_lookup(inv)
        area = lookup.get(args.area)
        if not area:
            print(f"Area VID {args.area} not found", file=sys.stderr)
            return 2
        path = resolve_area_path(args.area, lookup)
        print(f"Area: {' > '.join(path)}")
        print(f"VID: {area['vid']} Kind: {area['_kind']}")
        print()
        print("Loads:")
        for l in sorted(inv["loads"], key=lambda x: x["name"]):
            if l["area_vid"] == args.area:
                print(f"  [{l['vid']:>5}] {l['name']:<40} ({l.get('load_type','?')})")
        print("\nStations:")
        for s in sorted(inv["stations"], key=lambda x: x["name"]):
            if s["area_vid"] == args.area:
                btns = [b for b in inv["buttons"] if b.get("station_vid") == s["vid"]]
                print(f"  [{s['vid']:>5}] {s['name']:<40} ({s.get('station_type','?')}, {len(btns)} buttons)")
        return 0

    if args.tree:
        print_tree(inv)
        return 0

    # Default: summary
    print(f"=== {os.path.basename(args.file)} ===")
    print(f"File version:   {inv['file_version']}")
    print(f"DC version:     {inv['design_center_version']}")
    print(f"Areas:          {len(inv['areas'])}")
    print(f"AreaFragments:  {len(inv['area_fragments'])}")
    print(f"Loads:          {len(inv['loads'])}")
    print(f"Stations:       {len(inv['stations'])}")
    print(f"  of which Keypads: {len(inv['keypads'])}")
    print(f"Buttons:        {len(inv['buttons'])}")
    print(f"Tasks:          {len(inv['tasks'])}")
    print(f"Thermostats:    {len(inv['thermostats'])}")
    print(f"Dry contacts:   {len(inv['dry_contacts'])}")
    print(f"Omni sensors:   {len(inv['omni_sensors'])}")
    print(f"Temperatures:   {len(inv['temperatures'])}")
    print(f"GMems:          {len(inv['gmems'])}")
    print(f"Back boxes:     {len(inv['back_boxes'])}")
    if inv["other_type_counts"]:
        print(f"\nOther object types (top 10):")
        for t, n in sorted(inv["other_type_counts"].items(), key=lambda x: -x[1])[:10]:
            print(f"  {t:<30} {n:>4}")
    return 0


if __name__ == "__main__":
    sys.exit(_cli())
