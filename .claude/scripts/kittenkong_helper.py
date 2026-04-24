#!/usr/bin/env python3
"""
kittenkong_helper.py — Thin Python client for the FunkyGibbon REST API.

Never touches SQLite directly. All reads/writes go through the HTTP API.
Caches the admin token in /tmp/.funkygibbon-admin-token (7-day TTL).

Mirrors the parts of the kittenkong TypeScript client that the room-walk
and room-edit skills need.

Usage:
    from kittenkong_helper import FunkyGibbon

    fg = FunkyGibbon()
    home = fg.get_home()
    rooms = fg.list_entities("room")
    living = fg.find_entity_by_name("room", "Living Room")
    devices = fg.list_devices_in_room(living["id"])
    new_device = fg.create_entity("device", "Entry Fountain", {...}, source_type="imported")
    fg.create_relationship(new_device["id"], living["id"], "located_in")
    blob_id = fg.upload_blob(new_device["id"], jpeg_bytes, "keypad.jpg", "image/jpeg")
"""
from __future__ import annotations

import base64
import json
import os
import sys
import time
import uuid
import urllib.request
import urllib.parse
import urllib.error
from typing import Any, Dict, List, Optional

DEFAULT_HOST = os.environ.get("FUNKYGIBBON_HOST", "http://localhost:8000")
DEFAULT_ADMIN_PASSWORD = os.environ.get("FUNKYGIBBON_ADMIN_PASSWORD", "admin")
TOKEN_CACHE_PATH = "/tmp/.funkygibbon-admin-token"


class FunkyGibbonError(Exception):
    pass


class FunkyGibbon:
    """Thin HTTP client wrapper."""

    def __init__(
        self,
        host: str = DEFAULT_HOST,
        admin_password: str = DEFAULT_ADMIN_PASSWORD,
        timeout: float = 10.0,
    ):
        self.host = host.rstrip("/")
        self.admin_password = admin_password
        self.timeout = timeout
        self._token: Optional[str] = None
        self._token_expires_at: float = 0.0
        self._user_id: Optional[str] = None  # filled after first /auth/me call
        self._load_cached_token()

    # ── Auth ──────────────────────────────────────────────────────────────────

    def _load_cached_token(self) -> None:
        try:
            with open(TOKEN_CACHE_PATH, "r") as f:
                cache = json.load(f)
            if cache.get("host") == self.host and cache.get("expires_at", 0) > time.time() + 60:
                self._token = cache["token"]
                self._token_expires_at = cache["expires_at"]
        except (FileNotFoundError, json.JSONDecodeError, KeyError):
            pass

    def _save_cached_token(self) -> None:
        try:
            with open(TOKEN_CACHE_PATH, "w") as f:
                json.dump(
                    {"host": self.host, "token": self._token, "expires_at": self._token_expires_at},
                    f,
                )
            os.chmod(TOKEN_CACHE_PATH, 0o600)
        except OSError:
            pass

    def _ensure_token(self) -> str:
        if self._token and self._token_expires_at > time.time() + 60:
            return self._token
        resp = self._raw_request(
            "POST",
            "/api/v1/auth/admin/login",
            body={"password": self.admin_password},
            auth=False,
        )
        self._token = resp["access_token"]
        self._token_expires_at = time.time() + int(resp.get("expires_in", 604800))
        self._save_cached_token()
        return self._token

    def _ensure_user_id(self) -> str:
        if self._user_id:
            return self._user_id
        resp = self._raw_request("GET", "/api/v1/auth/me")
        # Could be 'user_id', 'sub', or 'id' depending on schema
        self._user_id = resp.get("user_id") or resp.get("id") or resp.get("sub") or "admin"
        return self._user_id

    # ── Response normalisation ────────────────────────────────────────────────

    @staticmethod
    def _unwrap(resp: Any) -> Any:
        """Unwrap entity responses.

        FunkyGibbon wraps single-entity responses as {'entity': {...}} or
        {'entity': {...}, 'relationships': [...]} etc.  Callers expect the
        inner entity dict so they can do ent['id'], ent['content'], etc.
        """
        if isinstance(resp, dict) and "entity" in resp:
            return resp["entity"]
        return resp

    # ── HTTP plumbing ─────────────────────────────────────────────────────────

    def _raw_request(
        self,
        method: str,
        path: str,
        body: Optional[Dict[str, Any]] = None,
        query: Optional[Dict[str, Any]] = None,
        auth: bool = True,
    ) -> Any:
        url = self.host + path
        if query:
            url += "?" + urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})

        headers = {"Accept": "application/json"}
        data: Optional[bytes] = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if auth:
            headers["Authorization"] = f"Bearer {self._ensure_token()}"

        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read()
                if not raw:
                    return None
                return json.loads(raw)
        except urllib.error.HTTPError as e:
            body_text = ""
            try:
                body_text = e.read().decode("utf-8", errors="replace")
            except Exception:
                pass
            raise FunkyGibbonError(f"{method} {path} → {e.code} {e.reason}: {body_text[:500]}") from e
        except urllib.error.URLError as e:
            raise FunkyGibbonError(f"{method} {path} → connection error: {e.reason}") from e

    # ── Entities ──────────────────────────────────────────────────────────────

    def list_entities(
        self,
        entity_type: Optional[str] = None,
        page_size: int = 100,
        include_decommissioned: bool = False,
    ) -> List[Dict[str, Any]]:
        """List ALL entities of a type (auto-paginates). The server's default page
        size is ~25, so without this loop we'd miss rooms/devices past that.

        By default, entities with content.status == 'decommissioned' are filtered
        out — they're kept in the DB for audit/version history but shouldn't
        appear in "what's in this house" listings.
        """
        out: List[Dict[str, Any]] = []
        offset = 0
        while True:
            query: Dict[str, Any] = {"limit": page_size, "offset": offset}
            if entity_type:
                query["entity_type"] = entity_type
            resp = self._raw_request("GET", "/api/v1/graph/entities", query=query)
            if isinstance(resp, dict):
                batch = resp.get("items") or resp.get("entities") or resp.get("data") or []
                total = resp.get("totalCount") or resp.get("total") or resp.get("count")
            else:
                batch = resp or []
                total = None
            if not batch:
                break
            out.extend(batch)
            offset += len(batch)
            # Stop if we got a full page-sized batch but server reports we're past total,
            # or if the batch is smaller than page_size (no more results)
            if total is not None and offset >= total:
                break
            if len(batch) < page_size:
                break
            # Safety cap to prevent runaway loops on misbehaving servers
            if offset > 50_000:
                break
        if not include_decommissioned:
            out = [e for e in out if (e.get("content") or {}).get("status") != "decommissioned"]
        return out

    def get_entity(self, entity_id: str) -> Dict[str, Any]:
        return self._unwrap(self._raw_request("GET", f"/api/v1/graph/entities/{entity_id}"))

    def search_entities(self, query: str, entity_type: Optional[str] = None) -> List[Dict[str, Any]]:
        q = {"q": query}
        if entity_type:
            q["entity_type"] = entity_type
        resp = self._raw_request("GET", "/api/v1/graph/search", query=q)
        if isinstance(resp, dict):
            return resp.get("items") or resp.get("results") or resp.get("entities") or []
        return resp or []

    def find_entity_by_name(
        self, entity_type: str, name: str, strict: bool = False
    ) -> Optional[Dict[str, Any]]:
        """Case-insensitive exact or substring match on entity name."""
        candidates = self.list_entities(entity_type)
        norm = name.strip().lower()
        # Exact (case-insensitive) first
        for e in candidates:
            if e.get("name", "").strip().lower() == norm:
                return e
        if strict:
            return None
        # Substring fallback
        matches = [e for e in candidates if norm in e.get("name", "").lower()]
        if len(matches) == 1:
            return matches[0]
        return None  # ambiguous or no match

    def find_entities_by_name(
        self, entity_type: str, name: str
    ) -> List[Dict[str, Any]]:
        """Return all entities whose names contain `name` (case-insensitive)."""
        candidates = self.list_entities(entity_type)
        norm = name.strip().lower()
        return [e for e in candidates if norm in e.get("name", "").lower()]

    def create_entity(
        self,
        entity_type: str,
        name: str,
        content: Optional[Dict[str, Any]] = None,
        source_type: str = "manual",
        user_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        body = {
            "entity_type": entity_type,
            "name": name,
            "content": content or {},
            "source_type": source_type,
            "user_id": user_id or self._ensure_user_id(),
        }
        return self._unwrap(self._raw_request("POST", "/api/v1/graph/entities", body=body))

    def update_entity(
        self,
        entity_id: str,
        name: Optional[str] = None,
        content: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Update an entity. FunkyGibbon uses PUT (versioned write, not PATCH).
        A new version row is created; the old one remains for audit."""
        body: Dict[str, Any] = {"user_id": self._ensure_user_id()}
        if name is not None:
            body["name"] = name
        if content is not None:
            body["content"] = content
        return self._unwrap(self._raw_request("PUT", f"/api/v1/graph/entities/{entity_id}", body=body))

    def delete_entity(self, entity_id: str, reason: Optional[str] = None) -> Dict[str, Any]:
        """Soft-delete: the API has no DELETE, so we flag the entity with
        content.status = 'decommissioned' and a timestamp. Queries should
        filter these out when listing 'live' entities.
        """
        ent = self.get_entity(entity_id)
        content = dict(ent.get("content") or {})
        content["status"] = "decommissioned"
        content["decommissioned_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        if reason:
            content["decommissioned_reason"] = reason
        return self.update_entity(entity_id, content=content)

    # ── Relationships ─────────────────────────────────────────────────────────

    def list_relationships(
        self,
        from_id: Optional[str] = None,
        to_id: Optional[str] = None,
        rel_type: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        q: Dict[str, Any] = {}
        if from_id:
            q["from_entity_id"] = from_id
        if to_id:
            q["to_entity_id"] = to_id
        if rel_type:
            q["relationship_type"] = rel_type
        resp = self._raw_request("GET", "/api/v1/graph/relationships", query=q or None)
        if isinstance(resp, dict):
            return resp.get("items") or resp.get("relationships") or []
        return resp or []

    def create_relationship(
        self,
        from_id: str,
        to_id: str,
        rel_type: str,
        properties: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        body: Dict[str, Any] = {
            "source_id": from_id,
            "target_id": to_id,
            "relationship_type": rel_type,
            "user_id": self._ensure_user_id(),
        }
        if properties:
            body["properties"] = properties
        return self._raw_request("POST", "/api/v1/graph/relationships", body=body)

    def delete_relationship(self, relationship_id: str) -> None:
        self._raw_request("DELETE", f"/api/v1/graph/relationships/{relationship_id}")

    def connected(self, entity_id: str) -> List[Dict[str, Any]]:
        """Entities connected to this one (via any relationship)."""
        resp = self._raw_request("GET", f"/api/v1/graph/entities/{entity_id}/connected")
        if isinstance(resp, dict):
            return resp.get("items") or resp.get("entities") or []
        return resp or []

    # ── Convenience queries ───────────────────────────────────────────────────

    def get_home(self) -> Optional[Dict[str, Any]]:
        homes = self.list_entities("home")
        return homes[0] if homes else None

    def list_rooms(self) -> List[Dict[str, Any]]:
        return self.list_entities("room")

    def list_devices_in_room(self, room_id: str) -> List[Dict[str, Any]]:
        """Devices with a located_in relationship pointing at this room."""
        rels = self.list_relationships(to_id=room_id, rel_type="located_in")
        devices = []
        for r in rels:
            from_id = r.get("from_entity_id")
            if not from_id:
                continue
            try:
                ent = self.get_entity(from_id)
                if ent.get("entity_type") == "device":
                    devices.append(ent)
            except FunkyGibbonError:
                continue
        return devices

    def list_doors_for_room(self, room_id: str) -> List[Dict[str, Any]]:
        """Doors connected to this room (via connects_to)."""
        rels = self.list_relationships(to_id=room_id, rel_type="connects_to")
        doors = []
        for r in rels:
            from_id = r.get("from_entity_id")
            if not from_id:
                continue
            try:
                ent = self.get_entity(from_id)
                if ent.get("entity_type") == "door":
                    doors.append(ent)
            except FunkyGibbonError:
                continue
        return doors

    # ── Blobs ─────────────────────────────────────────────────────────────────

    def upload_blob(
        self,
        parent_entity_id: str,
        data: bytes,
        filename: str,
        mime_type: str = "application/octet-stream",
        description: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Create a blob entity (entity_type=note with binary content) and link
        has_blob relationship from parent_entity_id → blob. Returns the blob entity.

        NOTE: FunkyGibbon's blob schema may differ. This function encapsulates the
        expected pattern: inline base64 in content. Revisit if the server offers a
        dedicated multipart blob endpoint.
        """
        b64 = base64.b64encode(data).decode("ascii")
        blob_name = filename or f"blob-{uuid.uuid4().hex[:8]}"
        # 'note' is the closest first-class type for "attached media"; the binary
        # is carried in content.data_b64. If there's a purpose-built blob endpoint
        # later, update this to use it.
        blob = self.create_entity(
            entity_type="note",
            name=blob_name,
            content={
                "is_blob": True,
                "filename": filename,
                "mime_type": mime_type,
                "size": len(data),
                "data_b64": b64,
                "description": description,
            },
            source_type="manual",
        )
        self.create_relationship(parent_entity_id, blob["id"], "has_blob")
        return blob

    # ── Helpful shortcuts ─────────────────────────────────────────────────────

    def upsert_alias(self, entity_id: str, alias: str) -> Dict[str, Any]:
        """Add an alias to an entity's content.aliases list (dedup)."""
        ent = self.get_entity(entity_id)
        content = dict(ent.get("content") or {})
        aliases = list(content.get("aliases") or [])
        if alias.strip() and alias not in aliases:
            aliases.append(alias.strip())
            content["aliases"] = aliases
            return self.update_entity(entity_id, content=content)
        return ent

    def remove_alias(self, entity_id: str, alias: str) -> Dict[str, Any]:
        ent = self.get_entity(entity_id)
        content = dict(ent.get("content") or {})
        aliases = [a for a in (content.get("aliases") or []) if a != alias]
        content["aliases"] = aliases
        return self.update_entity(entity_id, content=content)

    def set_status(
        self, entity_id: str, status: str, reason: Optional[str] = None
    ) -> Dict[str, Any]:
        """status: 'operational' | 'inoperable' | 'unknown' | 'decommissioned'."""
        ent = self.get_entity(entity_id)
        content = dict(ent.get("content") or {})
        content["status"] = status
        if status in ("inoperable", "decommissioned"):
            content.setdefault("status_since", time.strftime("%Y-%m-%d"))
            if reason:
                content["status_reason"] = reason
        return self.update_entity(entity_id, content=content)


# ── CLI for quick sanity checks ──────────────────────────────────────────────


def _cli() -> int:
    import argparse

    p = argparse.ArgumentParser(description="FunkyGibbon inspection")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ping").add_argument("--token-only", action="store_true")
    sub.add_parser("home")
    rl = sub.add_parser("rooms")
    rl.add_argument("--json", action="store_true")
    dl = sub.add_parser("devices")
    dl.add_argument("--room")
    dl.add_argument("--json", action="store_true")
    srch = sub.add_parser("search")
    srch.add_argument("query")
    srch.add_argument("--type")

    args = p.parse_args()
    fg = FunkyGibbon()

    if args.cmd == "ping":
        tok = fg._ensure_token()
        print("OK" if not args.token_only else tok[:20] + "…")
    elif args.cmd == "home":
        print(json.dumps(fg.get_home(), indent=2, default=str))
    elif args.cmd == "rooms":
        rooms = fg.list_rooms()
        if args.json:
            print(json.dumps(rooms, indent=2, default=str))
        else:
            for r in sorted(rooms, key=lambda x: x.get("name", "")):
                print(f"  {r['id'][:8]}… {r.get('name')}")
    elif args.cmd == "devices":
        if args.room:
            room = fg.find_entity_by_name("room", args.room)
            if not room:
                print(f"No room matches '{args.room}'", file=sys.stderr)
                return 2
            devices = fg.list_devices_in_room(room["id"])
        else:
            devices = fg.list_entities("device")
        if args.json:
            print(json.dumps(devices, indent=2, default=str))
        else:
            for d in sorted(devices, key=lambda x: x.get("name", "")):
                print(f"  {d['id'][:8]}… {d.get('name')}")
    elif args.cmd == "search":
        results = fg.search_entities(args.query, entity_type=args.type)
        for r in results:
            print(f"  {r.get('entity_type','?'):10s} {r['id'][:8]}… {r.get('name')}")
    return 0


if __name__ == "__main__":
    sys.exit(_cli())
