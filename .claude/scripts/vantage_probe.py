#!/usr/bin/env python3
"""
vantage_probe.py — Vantage InFusion controller helper for room walks.

Controller: 10.0.0.50 (no auth on this system's ports 2001/3001).

Three responsibilities:
1. Inventory — cache the full object list (loads, areas, stations, tasks, etc.)
2. Probing — flash a load, query current level, invoke a task
3. Lookup — find loads/stations by VID, area name fuzzy match, etc.

Built on aiovantage, but exposes a synchronous API because the callers
(skills running inside Claude Code sessions) are synchronous.

Usage (from Python):
    from vantage_probe import VantageProbe

    v = VantageProbe()
    v.load_inventory()

    loads = v.find_loads_in_area("living room")
    level = v.get_load_level(1781)
    v.flash_load(1781, duration=3.0)       # full flash 0→100→0→restore
    v.set_load(1781, 75)
    v.invoke_task(9812)

Usage (from CLI):
    python3 vantage_probe.py list-areas
    python3 vantage_probe.py list-loads --area "living"
    python3 vantage_probe.py flash <vid>
    python3 vantage_probe.py get <vid>
    python3 vantage_probe.py set <vid> <level>
    python3 vantage_probe.py dump > /tmp/vantage.json
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import time
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional

VANTAGE_HOST = os.environ.get("VANTAGE_HOST", "10.0.0.50")
INVENTORY_CACHE = os.environ.get(
    "VANTAGE_INVENTORY_CACHE",
    "/tmp/.vantage-inventory.json",
)
INVENTORY_TTL_SEC = 3600  # refresh hourly at most; "dump" forces refresh


@dataclass
class VantageObject:
    vid: int
    kind: str  # 'area' | 'load' | 'station' | 'button' | 'task' | 'thermostat' | 'dry_contact' | 'temperature' | 'omni_sensor' | 'gmem'
    name: str
    area_vid: Optional[int] = None  # for loads, stations, thermostats
    extra: Dict[str, Any] = field(default_factory=dict)


class VantageProbe:
    def __init__(self, host: str = VANTAGE_HOST):
        self.host = host
        self.inventory: Dict[str, List[VantageObject]] = {}
        self._by_vid: Dict[int, VantageObject] = {}

    # ── Inventory ────────────────────────────────────────────────────────────

    def load_inventory(self, force_refresh: bool = False) -> None:
        """Load inventory from cache if fresh, else fetch from controller.

        Also merges in area names from the .dc project file if present at
        .instar/context/project.dc. The runtime controller only exposes 15
        Area objects, but the .dc project file has all 51 (including LIVING
        ROOM, KITCHEN, POOL AREA, etc.). Without this merge, loads reference
        "dangling" area VIDs that can't be resolved to names.
        """
        if not force_refresh and self._load_from_cache():
            self._merge_dc_areas()
            return
        self._fetch_from_controller()
        self._save_to_cache()
        self._merge_dc_areas()

    def _merge_dc_areas(self) -> None:
        """Pull additional Area objects from the .dc project file, if available.
        Fills in the 'dangling' area VIDs that runtime controller can't resolve."""
        dc_path = os.path.join(
            os.environ.get("CLAUDE_PROJECT_DIR", os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
            ".instar", "context", "project.dc",
        )
        if not os.path.exists(dc_path):
            return

        try:
            # Import here so vantage_probe is usable without the dc parser
            import importlib.util
            spec = importlib.util.spec_from_file_location(
                "vantage_dc_parser",
                os.path.join(os.path.dirname(os.path.abspath(__file__)), "vantage_dc_parser.py"),
            )
            if spec is None or spec.loader is None:
                return
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            inv = mod.parse_dc_file(dc_path)
        except Exception as e:
            print(f"[vantage_probe] Could not load .dc project file: {e}", file=sys.stderr)
            return

        # --- Areas: merge DC areas the controller doesn't expose ---
        known_area_vids = {a.vid for a in self.inventory.get("area", [])}
        added_areas = 0
        for dc_area in inv["areas"]:
            vid = dc_area["vid"]
            if vid in known_area_vids:
                continue
            self.inventory.setdefault("area", []).append(VantageObject(
                vid=vid,
                kind="area",
                name=dc_area["name"],
                extra={
                    "parent_area_vid": dc_area.get("parent_area_vid"),
                    "area_type": dc_area.get("area_type"),
                    "source": "dc_file",
                },
            ))
            added_areas += 1

        # --- Loads: merge .dc loads not present at runtime, annotate with source ---
        known_load_vids = {l.vid for l in self.inventory.get("load", [])}
        added_loads = 0
        # Also mark runtime-known loads with source=controller so the combined
        # inventory is unambiguous about which are "live".
        for l in self.inventory.get("load", []):
            if "source" not in l.extra:
                l.extra["source"] = "controller"
        for dc_load in inv["loads"]:
            vid = dc_load["vid"]
            if vid in known_load_vids:
                continue
            self.inventory.setdefault("load", []).append(VantageObject(
                vid=vid,
                kind="load",
                name=dc_load["name"],
                area_vid=dc_load.get("area_vid"),
                extra={
                    "load_type": dc_load.get("load_type"),
                    "contractor_number": dc_load.get("contractor_number"),
                    "source": "dc_file_only",  # in .dc but not on controller — may be decommissioned
                },
            ))
            added_loads += 1

        # --- Stations: merge .dc stations not present at runtime ---
        known_station_vids = {s.vid for s in self.inventory.get("station", [])}
        added_stations = 0
        for s in self.inventory.get("station", []):
            if "source" not in s.extra:
                s.extra["source"] = "controller"
        for dc_station in inv["stations"]:
            vid = dc_station["vid"]
            if vid in known_station_vids:
                continue
            self.inventory.setdefault("station", []).append(VantageObject(
                vid=vid,
                kind="station",
                name=dc_station["name"],
                area_vid=dc_station.get("area_vid"),
                extra={
                    "station_type": dc_station.get("station_type") or dc_station.get("type"),
                    "source": "dc_file_only",
                },
            ))
            added_stations += 1

        # --- Buttons: merge .dc buttons, linking each to its station ---
        known_button_vids = {b.vid for b in self.inventory.get("button", [])}
        added_buttons = 0
        for b in self.inventory.get("button", []):
            if "source" not in b.extra:
                b.extra["source"] = "controller"
        for dc_button in inv["buttons"]:
            vid = dc_button["vid"]
            if vid in known_button_vids:
                continue
            self.inventory.setdefault("button", []).append(VantageObject(
                vid=vid,
                kind="button",
                name=dc_button["name"],
                extra={
                    "station_vid": dc_button.get("station_vid") or dc_button.get("parent_vid"),
                    "text1": dc_button.get("text1"),
                    "text2": dc_button.get("text2"),
                    "button_number": dc_button.get("button_number"),
                    "position": dc_button.get("button_position"),
                    "source": "dc_file_only",
                },
            ))
            added_buttons += 1

        # --- Tasks: merge (.dc has 1046, runtime has 360) ---
        known_task_vids = {t.vid for t in self.inventory.get("task", [])}
        added_tasks = 0
        for t in self.inventory.get("task", []):
            if "source" not in t.extra:
                t.extra["source"] = "controller"
        for dc_task in inv["tasks"]:
            vid = dc_task["vid"]
            if vid in known_task_vids:
                continue
            self.inventory.setdefault("task", []).append(VantageObject(
                vid=vid,
                kind="task",
                name=dc_task["name"],
                extra={"source": "dc_file_only"},
            ))
            added_tasks += 1

        self._rebuild_index()

        if added_areas or added_loads or added_stations or added_buttons or added_tasks:
            print(
                f"[vantage_probe] Merged from .dc: "
                f"{added_areas} areas, {added_loads} loads, {added_stations} stations, "
                f"{added_buttons} buttons, {added_tasks} tasks "
                f"(runtime controller has partial coverage)",
                file=sys.stderr,
            )

    def _load_from_cache(self) -> bool:
        try:
            st = os.stat(INVENTORY_CACHE)
            if time.time() - st.st_mtime > INVENTORY_TTL_SEC:
                return False
            with open(INVENTORY_CACHE, "r") as f:
                raw = json.load(f)
            if raw.get("host") != self.host:
                return False
            self.inventory = {
                kind: [VantageObject(**o) for o in lst]
                for kind, lst in raw.get("objects", {}).items()
            }
            self._rebuild_index()
            return True
        except (OSError, json.JSONDecodeError, TypeError):
            return False

    def _save_to_cache(self) -> None:
        try:
            out = {
                "host": self.host,
                "fetched_at": time.time(),
                "objects": {
                    kind: [asdict(o) for o in lst] for kind, lst in self.inventory.items()
                },
            }
            with open(INVENTORY_CACHE, "w") as f:
                json.dump(out, f)
        except OSError:
            pass

    def _rebuild_index(self) -> None:
        self._by_vid = {}
        for lst in self.inventory.values():
            for o in lst:
                self._by_vid[o.vid] = o

    def _fetch_from_controller(self) -> None:
        """Connect to controller and pull the full object database."""
        asyncio.run(self._async_fetch())
        self._rebuild_index()

    async def _async_fetch(self) -> None:
        try:
            from aiovantage import Vantage
        except ImportError as e:
            raise RuntimeError("aiovantage required: pip install aiovantage") from e

        inv: Dict[str, List[VantageObject]] = {
            "area": [], "load": [], "station": [], "button": [],
            "task": [], "thermostat": [], "dry_contact": [],
            "temperature": [], "omni_sensor": [], "gmem": [],
        }

        async with Vantage(
            self.host, ssl=False, config_port=2001, command_port=3001
        ) as v:
            await v.initialize()

            for a in v.areas:
                inv["area"].append(VantageObject(
                    vid=a.vid, kind="area", name=a.name,
                    extra={"parent_area_vid": getattr(a, "area", None)}
                ))
            for l in v.loads:
                inv["load"].append(VantageObject(
                    vid=l.vid, kind="load", name=l.name, area_vid=l.area,
                    extra={
                        "load_type": getattr(l, "load_type", None),
                        "is_light": getattr(l, "is_light", False),
                        "is_motor": getattr(l, "is_motor", False),
                        "is_relay": getattr(l, "is_relay", False),
                    }
                ))
            for s in v.stations:
                inv["station"].append(VantageObject(
                    vid=s.vid, kind="station", name=s.name, area_vid=getattr(s, "area", None),
                    extra={
                        "station_type": type(s).__name__,
                    }
                ))
            for b in v.buttons:
                inv["button"].append(VantageObject(
                    vid=b.vid, kind="button", name=b.name,
                    extra={
                        "station_vid": getattr(b, "parent", None),
                    }
                ))
            for t in v.tasks:
                inv["task"].append(VantageObject(vid=t.vid, kind="task", name=t.name))
            for t in v.thermostats:
                inv["thermostat"].append(VantageObject(
                    vid=t.vid, kind="thermostat", name=t.name,
                    area_vid=getattr(t, "area", None),
                ))
            for d in v.dry_contacts:
                inv["dry_contact"].append(VantageObject(
                    vid=d.vid, kind="dry_contact", name=d.name,
                    area_vid=getattr(d, "area", None),
                ))
            for t in getattr(v, "temperatures", []):
                inv["temperature"].append(VantageObject(
                    vid=t.vid, kind="temperature", name=t.name,
                    area_vid=getattr(t, "area", None),
                ))
            for s in getattr(v, "omni_sensors", []):
                inv["omni_sensor"].append(VantageObject(
                    vid=s.vid, kind="omni_sensor", name=s.name,
                    area_vid=getattr(s, "area", None),
                ))
            for g in getattr(v, "gmem", []):
                inv["gmem"].append(VantageObject(vid=g.vid, kind="gmem", name=g.name))

        self.inventory = inv

    # ── Lookups ───────────────────────────────────────────────────────────────

    def by_vid(self, vid: int) -> Optional[VantageObject]:
        return self._by_vid.get(int(vid))

    def area_by_vid(self, vid: Optional[int]) -> Optional[VantageObject]:
        if vid is None:
            return None
        o = self._by_vid.get(int(vid))
        return o if o and o.kind == "area" else None

    def find_area(self, name_pattern: str) -> List[VantageObject]:
        """Case-insensitive substring match on area names."""
        q = name_pattern.lower().strip()
        return [a for a in self.inventory.get("area", []) if q in a.name.lower()]

    def find_loads_in_area(self, area_name_pattern: str) -> List[VantageObject]:
        """All loads whose area name matches (or whose area has a parent that matches)."""
        areas = self.find_area(area_name_pattern)
        area_vids = {a.vid for a in areas}
        # Include child areas that roll up under these
        for a in self.inventory.get("area", []):
            parent = a.extra.get("parent_area_vid")
            if parent in area_vids:
                area_vids.add(a.vid)
        return [l for l in self.inventory.get("load", []) if l.area_vid in area_vids]

    def find_stations_in_area(self, area_name_pattern: str) -> List[VantageObject]:
        areas = self.find_area(area_name_pattern)
        area_vids = {a.vid for a in areas}
        for a in self.inventory.get("area", []):
            parent = a.extra.get("parent_area_vid")
            if parent in area_vids:
                area_vids.add(a.vid)
        return [s for s in self.inventory.get("station", []) if s.area_vid in area_vids]

    def buttons_of_station(self, station_vid: int) -> List[VantageObject]:
        return [b for b in self.inventory.get("button", []) if b.extra.get("station_vid") == station_vid]

    def find_task(self, name_pattern: str) -> List[VantageObject]:
        q = name_pattern.lower().strip()
        return [t for t in self.inventory.get("task", []) if q in t.name.lower()]

    # ── Live control (port 3001 host commands) ───────────────────────────────

    async def _send_commands(self, commands: List[str]) -> List[str]:
        """Open TCP connection to port 3001, send commands, return each response line."""
        reader, writer = await asyncio.open_connection(self.host, 3001)
        responses: List[str] = []
        try:
            for cmd in commands:
                writer.write((cmd + "\n").encode("ascii"))
                await writer.drain()
                try:
                    line = await asyncio.wait_for(reader.readline(), timeout=3.0)
                    responses.append(line.decode("ascii", errors="replace").strip())
                except asyncio.TimeoutError:
                    responses.append("")
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
        return responses

    def send_commands(self, commands: List[str]) -> List[str]:
        return asyncio.run(self._send_commands(commands))

    def get_load_level(self, vid: int) -> Optional[float]:
        """Returns current level 0-100, or None on parse failure."""
        resp = self.send_commands([f"GETLOAD {int(vid)}"])
        # Response looks like: "GETLOAD <vid> <level>" or just "<level>"
        if not resp:
            return None
        line = resp[-1]
        parts = line.split()
        # Accept either 1 or 3+ token forms
        try:
            return float(parts[-1])
        except (ValueError, IndexError):
            return None

    def set_load(self, vid: int, level: float) -> None:
        level = max(0.0, min(100.0, float(level)))
        self.send_commands([f"LOAD {int(vid)} {level}"])

    def invoke_task(self, vid: int) -> None:
        """Trigger a task as if its PRESS event fired."""
        self.send_commands([f"TASK {int(vid)} PRESS"])

    def flash_load(
        self,
        vid: int,
        duration: float = 3.0,
        peak_level: float = 100.0,
        restore: bool = True,
    ) -> Dict[str, Any]:
        """
        Identification flash: capture current level, go to peak, wait, then
        restore original (or 0 if restore=False).

        Returns a dict with 'original_level' so the caller can narrate:
          "Living Room Overhead was at 45%, flashing full on…"
        """
        original = self.get_load_level(vid)
        self.set_load(vid, peak_level)
        time.sleep(duration)
        if restore and original is not None:
            self.set_load(vid, original)
        elif not restore:
            self.set_load(vid, 0.0)
        return {"vid": int(vid), "original_level": original, "peak_level": peak_level}


# ── CLI ──────────────────────────────────────────────────────────────────────


def _format_area_map(v: VantageProbe) -> Dict[int, str]:
    return {a.vid: a.name for a in v.inventory.get("area", [])}


def _cli() -> int:
    import argparse

    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list-areas")

    ll = sub.add_parser("list-loads")
    ll.add_argument("--area")
    ll.add_argument("--match")

    lt = sub.add_parser("list-tasks")
    lt.add_argument("--match")

    ls = sub.add_parser("list-stations")
    ls.add_argument("--area")

    lb = sub.add_parser("list-buttons")
    lb.add_argument("station_vid", type=int)

    sub.add_parser("dump")

    gt = sub.add_parser("get")
    gt.add_argument("vid", type=int)

    st = sub.add_parser("set")
    st.add_argument("vid", type=int)
    st.add_argument("level", type=float)

    fl = sub.add_parser("flash")
    fl.add_argument("vid", type=int)
    fl.add_argument("--duration", type=float, default=3.0)

    tk = sub.add_parser("task")
    tk.add_argument("vid", type=int)

    args = p.parse_args()
    v = VantageProbe()
    if args.cmd == "dump":
        v.load_inventory(force_refresh=True)
        areas = _format_area_map(v)
        out = {
            "host": v.host,
            "areas": [asdict(a) for a in v.inventory["area"]],
            "loads": [
                {**asdict(l), "area_name": areas.get(l.area_vid)}
                for l in v.inventory["load"]
            ],
            "stations": [
                {**asdict(s), "area_name": areas.get(s.area_vid)}
                for s in v.inventory["station"]
            ],
            "buttons": [asdict(b) for b in v.inventory["button"]],
            "tasks": [asdict(t) for t in v.inventory["task"]],
            "thermostats": [asdict(t) for t in v.inventory["thermostat"]],
            "dry_contacts": [asdict(d) for d in v.inventory["dry_contact"]],
            "temperatures": [asdict(t) for t in v.inventory["temperature"]],
            "omni_sensors": [asdict(s) for s in v.inventory["omni_sensor"]],
        }
        print(json.dumps(out, indent=2))
        return 0

    v.load_inventory()
    areas = _format_area_map(v)

    if args.cmd == "list-areas":
        for a in sorted(v.inventory["area"], key=lambda x: x.name):
            count = sum(1 for l in v.inventory["load"] if l.area_vid == a.vid)
            print(f"  [{a.vid:>6}] {a.name:<30} {count} loads")
    elif args.cmd == "list-loads":
        pool = v.find_loads_in_area(args.area) if args.area else v.inventory["load"]
        if args.match:
            q = args.match.lower()
            pool = [l for l in pool if q in l.name.lower()]
        for l in sorted(pool, key=lambda x: (areas.get(x.area_vid) or "", x.name)):
            area_name = areas.get(l.area_vid, f"?{l.area_vid}")
            print(f"  [{l.vid:>6}] {area_name:<25} {l.name}")
    elif args.cmd == "list-tasks":
        pool = v.find_task(args.match) if args.match else v.inventory["task"]
        for t in sorted(pool, key=lambda x: x.name):
            print(f"  [{t.vid:>6}] {t.name}")
    elif args.cmd == "list-stations":
        pool = v.find_stations_in_area(args.area) if args.area else v.inventory["station"]
        for s in sorted(pool, key=lambda x: (areas.get(x.area_vid) or "", x.name)):
            area_name = areas.get(s.area_vid, f"?{s.area_vid}")
            btn_count = len(v.buttons_of_station(s.vid))
            print(f"  [{s.vid:>6}] {area_name:<25} {s.name:<30} ({btn_count} buttons, {s.extra.get('station_type','?')})")
    elif args.cmd == "list-buttons":
        pool = v.buttons_of_station(args.station_vid)
        for b in sorted(pool, key=lambda x: x.vid):
            print(f"  [{b.vid:>6}] {b.name}")
    elif args.cmd == "get":
        level = v.get_load_level(args.vid)
        o = v.by_vid(args.vid)
        print(f"[{args.vid}] {o.name if o else '?'}: level={level}")
    elif args.cmd == "set":
        v.set_load(args.vid, args.level)
        print(f"Set [{args.vid}] → {args.level}%")
    elif args.cmd == "flash":
        result = v.flash_load(args.vid, duration=args.duration)
        print(json.dumps(result, indent=2))
    elif args.cmd == "task":
        v.invoke_task(args.vid)
        print(f"Invoked task [{args.vid}]")

    return 0


if __name__ == "__main__":
    sys.exit(_cli())
