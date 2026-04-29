#!/usr/bin/env python3
"""
fg_client.py — Synchronous FunkyGibbon client backed by blowing-off.

Replaces kittenkong_helper.py. All Python scripts that talk to FunkyGibbon
should import FGClient from here, not FunkyGibbon from kittenkong_helper.

Architecture:
  - blowing-off maintains a local SQLite cache at .instar/state/blowingoff.db
  - Reads come from the local cache (fast, offline-capable)
  - Writes go to local cache then sync to FunkyGibbon server
  - One shared database per machine — do not instantiate multiple clients

Usage:
    from fg_client import FGClient
    fg = FGClient()
    entity = fg.create_entity("device", "Pool Pump", {"location": "pool"})
    entity_id = entity["id"]
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import uuid
from typing import Any, Dict, List, Optional

# Ensure blowing-off and inbetweenies are importable from the submodule
_SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
_PROJECT_DIR = os.environ.get(
    "CLAUDE_PROJECT_DIR",
    os.path.dirname(os.path.dirname(_SCRIPTS_DIR)),
)
_GOODIES_DIR = os.path.join(_PROJECT_DIR, "the-goodies-python")
if os.path.isdir(_GOODIES_DIR) and _GOODIES_DIR not in sys.path:
    sys.path.insert(0, _GOODIES_DIR)

DB_PATH = os.path.join(_PROJECT_DIR, ".instar", "state", "blowingoff.db")
SERVER_URL = os.environ.get("FUNKYGIBBON_URL", "http://localhost:8000")
ADMIN_PASSWORD = os.environ.get("FUNKYGIBBON_ADMIN_PASSWORD", "admin")


class FGError(Exception):
    pass


class FGClient:
    """
    Synchronous wrapper around blowing-off for FunkyGibbon access.

    Use a single instance per script — it holds an open async event loop
    and a connected blowing-off client.
    """

    def __init__(self, db_path: str = DB_PATH, server_url: str = SERVER_URL):
        self._db_path = db_path
        self._server_url = server_url
        self._loop = asyncio.new_event_loop()
        self._client = None
        self._ops = None
        self._run(self._connect())

    # ── Internal async helpers ─────────────────────────────────────────────

    def _run(self, coro):
        return self._loop.run_until_complete(coro)

    async def _connect(self):
        import httpx
        from blowingoff.client import BlowingOffClient

        os.makedirs(os.path.dirname(self._db_path), exist_ok=True)

        # Get admin token
        try:
            resp = httpx.post(
                f"{self._server_url}/api/v1/auth/admin/login",
                json={"password": ADMIN_PASSWORD},
                timeout=10.0,
            )
            resp.raise_for_status()
            token = resp.json()["access_token"]
        except Exception as e:
            raise FGError(f"FunkyGibbon auth failed: {e}") from e

        self._client = BlowingOffClient(db_path=self._db_path)
        await self._client.connect(server_url=self._server_url, auth_token=token)
        self._ops = self._client.graph_operations

        # Initial sync to pull current server state
        try:
            await self._client.sync()
        except Exception:
            pass  # Offline start is fine — local cache still usable

    def _sync(self):
        """Push local changes to FunkyGibbon server."""
        try:
            self._run(self._client.sync())
        except Exception:
            pass  # Best-effort; don't fail writes over a transient sync error

    # ── Entity extraction helpers ──────────────────────────────────────────

    @staticmethod
    def _entity_to_dict(e: Any) -> Dict[str, Any]:
        """Convert a blowing-off Entity (or ToolResult) to a plain dict."""
        if e is None:
            return {}
        if hasattr(e, "success"):           # ToolResult
            if not e.success:
                raise FGError(e.error or "FunkyGibbon operation failed")
            inner = e.result
            if isinstance(inner, dict) and "entity" in inner:
                return inner["entity"]
            return inner or {}
        if hasattr(e, "to_dict"):            # Entity model
            return e.to_dict()
        if isinstance(e, dict):
            return e
        return vars(e)

    # ── Public API — mirrors kittenkong_helper.FunkyGibbon ────────────────

    def create_entity(
        self,
        entity_type: str,
        name: str,
        content: Optional[Dict[str, Any]] = None,
        source_type: str = "manual",
        user_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        result = self._run(
            self._ops.create_entity_tool(
                entity_type=entity_type,
                name=name,
                content=content or {},
                user_id=user_id or "agent",
            )
        )
        entity = self._entity_to_dict(result)
        self._sync()
        return entity

    def get_entity(self, entity_id: str) -> Dict[str, Any]:
        e = self._run(self._ops.get_entity(entity_id))
        return self._entity_to_dict(e)

    def update_entity(
        self,
        entity_id: str,
        content: Optional[Dict[str, Any]] = None,
        **_kwargs,
    ) -> Dict[str, Any]:
        changes = content or {}
        e = self._run(self._ops.update_entity(entity_id, changes, user_id="agent"))
        self._sync()
        return self._entity_to_dict(e)

    def list_entities(self, entity_type: str) -> List[Dict[str, Any]]:
        entities = self._run(self._ops.get_entities_by_type(entity_type))
        return [self._entity_to_dict(e) for e in (entities or [])]

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
        from inbetweenies.models import EntityType as ET
        entity_types = None
        if entity_type:
            try:
                entity_types = [ET(entity_type)]
            except ValueError:
                entity_types = None
        results = self._run(
            self._ops.search_entities(
                query=query,
                entity_types=entity_types,
                limit=limit,
            )
        )
        out = []
        for r in results or []:
            if hasattr(r, "entity"):
                out.append(self._entity_to_dict(r.entity))
            else:
                out.append(self._entity_to_dict(r))
        return out

    def create_relationship(
        self,
        from_id: str,
        to_id: str,
        relationship_type: str,
    ) -> Dict[str, Any]:
        result = self._run(
            self._ops.create_relationship_tool(
                from_entity_id=from_id,
                to_entity_id=to_id,
                relationship_type=relationship_type,
                user_id="agent",
            )
        )
        self._sync()
        return self._entity_to_dict(result)

    def upload_blob(
        self,
        parent_entity_id: str,
        data: bytes,
        filename: str,
        mime_type: str = "application/octet-stream",
        description: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Store a binary blob linked to a parent entity."""
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
            try:
                self.create_relationship(parent_entity_id, blob_id, "has_blob")
            except Exception:
                pass
        return blob_entity

    def get_home(self) -> Optional[Dict[str, Any]]:
        homes = self.list_entities("home")
        return homes[0] if homes else None

    def close(self):
        """Disconnect and cleanup."""
        try:
            self._run(self._client.disconnect())
        except Exception:
            pass
        self._loop.close()
