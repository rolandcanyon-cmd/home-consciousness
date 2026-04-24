#!/usr/bin/env python3
"""
unifi_probe.py — UniFi Dream Machine client/device enumeration.

Used during /room-walk to identify network-connected devices (Alexa, Tuya,
HomeKit-native, etc.) and correlate them with their physical location via
the AP/switch they're connected to.

Uses the UniFi Network Integration API v1 (local, not cloud):
    GET https://<host>/proxy/network/integration/v1/sites/<site-id>/...

Auth: X-API-KEY header (generated in UniFi OS → Settings → Control Plane →
Integrations). The key is stored at `.instar/context/ui.key` by convention.

Usage:
    from unifi_probe import UniFi

    u = UniFi()  # auto-reads key and resolves site
    clients = u.list_clients()
    aps = u.list_access_points()

    # Find clients connected to a specific AP (useful: "which clients are on
    # the AP in the Family Room?")
    family_ap = u.find_device_by_name("Family Room")
    family_clients = u.clients_on_device(family_ap["id"])

    # Find a client by MAC or name
    echo = u.find_client("echo")

    # Cache the full inventory (refresh every 10 min)
    u.load_inventory()

CLI:
    python3 unifi_probe.py list-aps
    python3 unifi_probe.py list-clients [--ap "Family Room"]
    python3 unifi_probe.py find <query>         # by name, MAC, or IP
    python3 unifi_probe.py dump > /tmp/unifi.json
"""
from __future__ import annotations

import json
import os
import ssl
import sys
import time
import urllib.request
import urllib.error
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional

PROJECT_DIR = os.environ.get(
    "CLAUDE_PROJECT_DIR",
    "/Users/rolandcanyon/.instar/agents/Roland",
)
DEFAULT_KEY_PATH = os.path.join(PROJECT_DIR, ".instar", "context", "ui.key")
DEFAULT_HOST = os.environ.get("UNIFI_HOST", "10.0.0.1")
INVENTORY_CACHE = os.environ.get(
    "UNIFI_INVENTORY_CACHE", "/tmp/.unifi-inventory.json"
)
INVENTORY_TTL_SEC = 600  # 10 min


class UniFiError(Exception):
    pass


@dataclass
class UniFiDevice:
    """An AP, switch, or gateway — i.e., a UniFi-managed appliance."""
    id: str
    name: str
    model: Optional[str] = None
    mac_address: Optional[str] = None
    ip_address: Optional[str] = None
    features: Dict[str, Any] = field(default_factory=dict)


@dataclass
class UniFiClient:
    """A device connected to the network (not managed by UniFi — just seen)."""
    id: str
    name: str
    kind: str                  # 'WIRED' | 'WIRELESS' | other
    mac_address: Optional[str] = None
    ip_address: Optional[str] = None
    uplink_device_id: Optional[str] = None  # id of the AP/switch it's on
    connected_at: Optional[str] = None


class UniFi:
    """Thin HTTP client for the local Network Integration API."""

    def __init__(
        self,
        host: str = DEFAULT_HOST,
        api_key: Optional[str] = None,
        key_path: str = DEFAULT_KEY_PATH,
        timeout: float = 10.0,
    ):
        self.host = host.rstrip("/")
        self.timeout = timeout
        if api_key is None:
            try:
                with open(key_path, "r") as f:
                    api_key = f.read().strip()
            except FileNotFoundError:
                raise UniFiError(
                    f"No API key at {key_path}. Generate one in UniFi OS "
                    "(Settings → Control Plane → Integrations) and save it there."
                )
        self.api_key = api_key
        self._site_id: Optional[str] = None
        self.inventory: Dict[str, Any] = {}

    # ── HTTP ──────────────────────────────────────────────────────────────────

    def _get(self, path: str, query: Optional[Dict[str, Any]] = None) -> Any:
        url = f"https://{self.host}{path}"
        if query:
            import urllib.parse
            url += "?" + urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})

        req = urllib.request.Request(
            url,
            headers={"X-API-KEY": self.api_key, "Accept": "application/json"},
        )
        # UniFi uses self-signed certs by default; accept them
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        try:
            with urllib.request.urlopen(req, timeout=self.timeout, context=ctx) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            try:
                body = e.read().decode("utf-8", errors="replace")
            except Exception:
                body = ""
            raise UniFiError(f"GET {path} → {e.code} {e.reason}: {body[:300]}") from e
        except urllib.error.URLError as e:
            raise UniFiError(f"GET {path} → connection error: {e.reason}") from e

    # ── Site resolution ───────────────────────────────────────────────────────

    def _ensure_site_id(self) -> str:
        if self._site_id:
            return self._site_id
        resp = self._get("/proxy/network/integration/v1/sites", query={"limit": 50})
        data = resp.get("data") or []
        if not data:
            raise UniFiError("No UniFi sites returned")
        # Prefer the 'default' site if multiple exist
        default = next((s for s in data if s.get("internalReference") == "default"), None)
        self._site_id = (default or data[0])["id"]
        return self._site_id

    # ── Fetchers ──────────────────────────────────────────────────────────────

    def _paginate(self, path: str, page_size: int = 200) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        offset = 0
        while True:
            resp = self._get(path, query={"limit": page_size, "offset": offset})
            batch = resp.get("data") or []
            out.extend(batch)
            total = resp.get("totalCount", len(out))
            offset += len(batch)
            if not batch or offset >= total:
                break
        return out

    def fetch_devices(self) -> List[UniFiDevice]:
        site = self._ensure_site_id()
        raw = self._paginate(f"/proxy/network/integration/v1/sites/{site}/devices")
        return [
            UniFiDevice(
                id=d.get("id"),
                name=d.get("name", ""),
                model=d.get("model"),
                mac_address=d.get("macAddress"),
                ip_address=d.get("ipAddress"),
                features={k: v for k, v in d.items() if k not in ("id", "name", "model", "macAddress", "ipAddress")},
            )
            for d in raw
        ]

    def fetch_clients(self) -> List[UniFiClient]:
        site = self._ensure_site_id()
        raw = self._paginate(f"/proxy/network/integration/v1/sites/{site}/clients")
        return [
            UniFiClient(
                id=c.get("id"),
                name=c.get("name") or c.get("hostname") or c.get("macAddress", "?"),
                kind=c.get("type", "UNKNOWN"),
                mac_address=c.get("macAddress"),
                ip_address=c.get("ipAddress"),
                uplink_device_id=c.get("uplinkDeviceId"),
                connected_at=c.get("connectedAt"),
            )
            for c in raw
        ]

    # ── Inventory caching ─────────────────────────────────────────────────────

    def load_inventory(self, force_refresh: bool = False) -> None:
        if not force_refresh and self._load_cache():
            return
        devices = self.fetch_devices()
        clients = self.fetch_clients()
        self.inventory = {
            "host": self.host,
            "fetched_at": time.time(),
            "devices": [asdict(d) for d in devices],
            "clients": [asdict(c) for c in clients],
        }
        self._save_cache()

    def _load_cache(self) -> bool:
        try:
            st = os.stat(INVENTORY_CACHE)
            if time.time() - st.st_mtime > INVENTORY_TTL_SEC:
                return False
            with open(INVENTORY_CACHE, "r") as f:
                raw = json.load(f)
            if raw.get("host") != self.host:
                return False
            self.inventory = raw
            return True
        except (OSError, json.JSONDecodeError):
            return False

    def _save_cache(self) -> None:
        try:
            with open(INVENTORY_CACHE, "w") as f:
                json.dump(self.inventory, f)
        except OSError:
            pass

    # ── Lookups ───────────────────────────────────────────────────────────────

    @property
    def devices(self) -> List[UniFiDevice]:
        return [UniFiDevice(**d) for d in self.inventory.get("devices", [])]

    @property
    def clients(self) -> List[UniFiClient]:
        return [UniFiClient(**c) for c in self.inventory.get("clients", [])]

    def find_device_by_name(self, query: str) -> Optional[UniFiDevice]:
        q = query.lower().strip()
        exact = [d for d in self.devices if d.name.lower() == q]
        if exact:
            return exact[0]
        substr = [d for d in self.devices if q in d.name.lower()]
        if len(substr) == 1:
            return substr[0]
        return None

    def find_devices_by_name(self, query: str) -> List[UniFiDevice]:
        q = query.lower().strip()
        return [d for d in self.devices if q in d.name.lower()]

    def device_by_id(self, device_id: str) -> Optional[UniFiDevice]:
        for d in self.devices:
            if d.id == device_id:
                return d
        return None

    def clients_on_device(self, device_id: str) -> List[UniFiClient]:
        return [c for c in self.clients if c.uplink_device_id == device_id]

    def clients_near(self, area_hint: str) -> List[Dict[str, Any]]:
        """Return clients whose uplink AP/switch name matches `area_hint`.
        Each result is annotated with the AP name for user display."""
        matching_aps = self.find_devices_by_name(area_hint)
        out = []
        ap_by_id = {ap.id: ap for ap in matching_aps}
        for c in self.clients:
            if c.uplink_device_id in ap_by_id:
                out.append({
                    "client": asdict(c),
                    "ap_name": ap_by_id[c.uplink_device_id].name,
                    "ap_mac": ap_by_id[c.uplink_device_id].mac_address,
                })
        return out

    def find_client(self, query: str) -> Optional[UniFiClient]:
        """Look up a client by MAC, IP, or name substring."""
        q = query.lower().strip()
        # MAC exact
        for c in self.clients:
            if c.mac_address and c.mac_address.lower() == q:
                return c
        # IP exact
        for c in self.clients:
            if c.ip_address == q:
                return c
        # Name substring
        matches = [c for c in self.clients if q in (c.name or "").lower()]
        if len(matches) == 1:
            return matches[0]
        return None

    def find_clients(self, query: str) -> List[UniFiClient]:
        q = query.lower().strip()
        out = []
        for c in self.clients:
            if (
                (c.mac_address and c.mac_address.lower() == q)
                or c.ip_address == q
                or q in (c.name or "").lower()
            ):
                out.append(c)
        return out


# ── CLI ──────────────────────────────────────────────────────────────────────


def _cli() -> int:
    import argparse

    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list-aps")
    lc = sub.add_parser("list-clients")
    lc.add_argument("--ap", help="Filter to clients near an AP/switch matching this substring")
    fc = sub.add_parser("find")
    fc.add_argument("query")
    sub.add_parser("dump")

    args = p.parse_args()
    u = UniFi()
    u.load_inventory()

    if args.cmd == "list-aps":
        for d in sorted(u.devices, key=lambda x: x.name):
            count = len(u.clients_on_device(d.id))
            print(f"  [{d.id[:8]}…] {d.name:<35} {d.model or '?':<10} clients={count}")
    elif args.cmd == "list-clients":
        pool = u.clients_near(args.ap) if args.ap else [
            {"client": asdict(c), "ap_name": (u.device_by_id(c.uplink_device_id).name if c.uplink_device_id and u.device_by_id(c.uplink_device_id) else "?"), "ap_mac": ""}
            for c in u.clients
        ]
        for entry in sorted(pool, key=lambda x: x["client"]["name"].lower()):
            c = entry["client"]
            ap = entry.get("ap_name", "?")
            print(f"  {c['kind']:<8} {c['name'][:35]:<35} {c.get('ip_address','?'):<15} {c.get('mac_address','?'):<17}  via {ap}")
    elif args.cmd == "find":
        results = u.find_clients(args.query)
        if not results:
            print(f"No clients match '{args.query}'", file=sys.stderr)
            return 2
        for c in results:
            ap = u.device_by_id(c.uplink_device_id) if c.uplink_device_id else None
            ap_name = ap.name if ap else "?"
            print(f"  {c.kind:<8} {c.name:<35} {c.ip_address or '?':<15} {c.mac_address or '?':<17}  via {ap_name}")
    elif args.cmd == "dump":
        print(json.dumps(u.inventory, indent=2, default=str))

    return 0


if __name__ == "__main__":
    sys.exit(_cli())
