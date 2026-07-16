#!/usr/bin/env python3
"""
fg_client.py — Synchronous FunkyGibbon client using the server's REST API
directly (http://<server>/api/v1/graph/...).

This is the canonical Python client for FunkyGibbon. All Python scripts that
talk to FunkyGibbon should import FGClient from here.

Architecture note (2026-07-15 rewrite): this used to be a wrapper around the
blowing-off library's `BlowingOffClient.graph_operations`, which is a fully
local, offline JSON-file-backed graph (`LocalGraphOperations` /
`LocalGraphStorage`, default dir `~/.blowing-off/graph` or a db_path-derived
sibling). That local graph has NO working push-to-server sync — writes and
even reads only ever touched the local JSON cache, never the real FunkyGibbon
database, even though calls appeared to succeed. This was discovered when a
/room-edit session's device/room updates silently never reached the real
house data. The direct REST API (verified against the live server db) is the
only confirmed-working write path, so this client now uses it exclusively.

Usage:
    from fg_client import FGClient
    fg = FGClient()
    entity = fg.create_entity("device", "Pool Pump", {"location": "pool"})
    entity_id = entity["id"]
"""
from __future__ import annotations

import json
import os
from typing import Any, Dict, List, Optional

_SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
_PROJECT_DIR = os.environ.get(
    "CLAUDE_PROJECT_DIR",
    os.path.dirname(os.path.dirname(_SCRIPTS_DIR)),
)

SERVER_URL = os.environ.get("FUNKYGIBBON_URL", "http://localhost:8000")
API_BASE = f"{SERVER_URL}/api/v1/graph"
ADMIN_PASSWORD = os.environ.get("FUNKYGIBBON_ADMIN_PASSWORD", "admin")


class FGError(Exception):
    pass


class FGClient:
    """
    Synchronous REST client for FunkyGibbon's /api/v1/graph endpoints.
    """

    def __init__(self, server_url: str = SERVER_URL, user_id: str = "agent"):
        import httpx

        self._server_url = server_url
        self._api_base = f"{server_url}/api/v1/graph"
        self._user_id = user_id
        self._token = self._get_token()
        self._http = httpx.Client(
            headers={
                "Authorization": f"Bearer {self._token}",
                "Content-Type": "application/json",
            },
            timeout=15.0,
        )

    # ── Auth ────────────────────────────────────────────────────────────────

    def _get_token(self) -> str:
        import httpx

        # Try password login first (works when FUNKYGIBBON_ADMIN_PASSWORD
        # matches the server's real admin password); fall back to a cached
        # long-lived client token (written by funkygibbon/setup_auth.py) if
        # password auth fails. This survives shells where the
        # interactively-set admin password isn't exported.
        try:
            resp = httpx.post(
                f"{self._server_url}/api/v1/auth/admin/login",
                json={"password": ADMIN_PASSWORD},
                timeout=10.0,
            )
            resp.raise_for_status()
            return resp.json()["access_token"]
        except Exception as primary_err:
            cached_cfg_path = os.environ.get(
                "FUNKYGIBBON_CLIENT_CONFIG",
                os.path.expanduser("~/the-goodies/.blowingoff.json"),
            )
            if os.path.isfile(cached_cfg_path):
                try:
                    with open(cached_cfg_path) as f:
                        cached = json.load(f)
                    token = cached.get("auth_token")
                    if token:
                        return token
                except Exception:
                    pass
            raise FGError(f"FunkyGibbon auth failed: {primary_err}") from primary_err

    # ── Internal helpers ────────────────────────────────────────────────────

    def _req(self, method: str, path: str, **kwargs) -> Dict[str, Any]:
        resp = self._http.request(method, f"{self._api_base}{path}", **kwargs)
        if resp.status_code == 404:
            return {}
        try:
            resp.raise_for_status()
        except Exception as e:
            raise FGError(f"{method} {path} failed ({resp.status_code}): {resp.text[:300]}") from e
        if not resp.content:
            return {}
        return resp.json()

    # ── Public API ────────────────────────────────────────────────────────

    def create_entity(
        self,
        entity_type: str,
        name: str,
        content: Optional[Dict[str, Any]] = None,
        source_type: str = "manual",
        user_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        body = self._req("POST", "/entities", json={
            "entity_type": entity_type,
            "name": name,
            "content": content or {},
            "source_type": source_type,
            "user_id": user_id or self._user_id,
        })
        return body.get("entity", {})

    def get_entity(self, entity_id: str) -> Dict[str, Any]:
        body = self._req("GET", f"/entities/{entity_id}", params={"include_relationships": "false"})
        return body.get("entity", {})

    def update_entity(
        self,
        entity_id: str,
        content: Optional[Dict[str, Any]] = None,
        name: Optional[str] = None,
        user_id: Optional[str] = None,
        **_kwargs,
    ) -> Dict[str, Any]:
        payload: Dict[str, Any] = {"user_id": user_id or self._user_id}
        if content is not None:
            payload["content"] = content
        if name is not None:
            payload["name"] = name
        body = self._req("PUT", f"/entities/{entity_id}", json=payload)
        return body.get("entity", {})

    def list_entities(self, entity_type: str, limit: int = 500) -> List[Dict[str, Any]]:
        """Fetch all entities of a type, paginating past the server's 100-per-page cap."""
        out: List[Dict[str, Any]] = []
        offset = 0
        page_size = 100
        while len(out) < limit:
            body = self._req("GET", "/entities", params={
                "entity_type": entity_type, "limit": page_size, "offset": offset,
            })
            page = body.get("entities", [])
            out.extend(page)
            total = body.get("total", len(out))
            offset += page_size
            if len(page) < page_size or offset >= total:
                break
        return out[:limit]

    def find_entity_by_name(
        self,
        entity_type: str,
        name: str,
        strict: bool = False,
    ) -> Optional[Dict[str, Any]]:
        candidates = self.list_entities(entity_type)
        norm = name.strip().lower()
        for e in candidates:
            if e.get("name", "").strip().lower() == norm:
                return e
        if strict:
            return None
        matches = [e for e in candidates if norm in e.get("name", "").lower()]
        if len(matches) == 1:
            return matches[0]
        return None

    def search_entities(
        self,
        query: str,
        entity_type: Optional[str] = None,
        limit: int = 20,
    ) -> List[Dict[str, Any]]:
        payload: Dict[str, Any] = {"query": query, "limit": min(limit, 100)}
        if entity_type:
            payload["entity_types"] = [entity_type]
        body = self._req("POST", "/search", json=payload)
        return [r.get("entity", {}) for r in body.get("results", [])]

    def create_relationship(
        self,
        from_id: str,
        to_id: str,
        relationship_type: str,
        user_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        body = self._req("POST", "/relationships", json={
            "source_id": from_id,
            "target_id": to_id,
            "relationship_type": relationship_type,
            "properties": {},
            "user_id": user_id or self._user_id,
        })
        return body.get("relationship", {})

    def list_relationships(
        self,
        from_id: Optional[str] = None,
        to_id: Optional[str] = None,
        rel_type: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """List relationship edges matching the given filters.

        Note: the underlying graph has no delete-relationship primitive (it's
        an append-only/versioned store — see delete_entity below), so this is
        for inspection only, not a precursor to removal.
        """
        params: Dict[str, Any] = {}
        if from_id:
            params["from_entity_id"] = from_id
        if to_id:
            params["to_entity_id"] = to_id
        if rel_type:
            params["relationship_type"] = rel_type
        body = self._req("GET", "/relationships", params=params)
        return body.get("relationships", [])

    def upsert_alias(self, entity_id: str, alias: str) -> Dict[str, Any]:
        """Add an alias to a device/room's content.aliases list (idempotent)."""
        ent = self.get_entity(entity_id)
        aliases = list((ent.get("content") or {}).get("aliases") or [])
        if alias not in aliases:
            aliases.append(alias)
            return self.update_entity(entity_id, content={"aliases": aliases})
        return ent

    def remove_alias(self, entity_id: str, alias: str) -> Dict[str, Any]:
        ent = self.get_entity(entity_id)
        aliases = list((ent.get("content") or {}).get("aliases") or [])
        if alias in aliases:
            aliases.remove(alias)
            return self.update_entity(entity_id, content={"aliases": aliases})
        return ent

    def set_status(self, entity_id: str, status: str, reason: Optional[str] = None) -> Dict[str, Any]:
        content = {"status": status}
        if reason:
            content["status_reason"] = reason
        return self.update_entity(entity_id, content=content)

    def delete_entity(self, entity_id: str, reason: Optional[str] = None) -> Dict[str, Any]:
        """Soft-tombstone only — this graph has no hard-delete API (no DELETE
        route on /entities or /relationships; append-only, versioned by
        design). 'Deleting' means marking the entity retired/duplicate while
        preserving its history, matching the existing convention already used
        elsewhere in this graph (status: 'decommissioned')."""
        return self.set_status(entity_id, "duplicate", reason or "marked duplicate/retired")

    def upload_blob(
        self,
        parent_entity_id: str,
        data: bytes,
        filename: str,
        mime_type: str = "application/octet-stream",
        description: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Store a binary blob (as a base64-encoded note entity) linked to a parent entity."""
        import base64
        b64 = base64.b64encode(data).decode("ascii")
        blob_entity = self.create_entity(
            entity_type="note",
            name=filename,
            content={
                "is_blob": True,
                "mime_type": mime_type,
                "data_b64": b64,
                "description": description or "",
            },
        )
        blob_id = blob_entity.get("id", "")
        if blob_id and parent_entity_id:
            self.create_relationship(parent_entity_id, blob_id, "has_blob")
        return blob_entity

    def get_home(self) -> Optional[Dict[str, Any]]:
        homes = self.list_entities("home")
        return homes[0] if homes else None

    def close(self):
        try:
            self._http.close()
        except Exception:
            pass
