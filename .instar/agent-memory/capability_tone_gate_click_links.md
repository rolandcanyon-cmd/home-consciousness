---
name: tone-gate-click-link-carve-out
description: Tone gate now allows legitimate clickable links to pass through even during LLM backend degradation
metadata: 
  node_type: memory
  type: capability
  originSessionId: 92b7025a-1cbf-45f4-b118-2ea64508f563
---

# Tone Gate Click-Link Carve-Out (vNEXT)

## What Changed

When the LLM backend is rate-limited or slow, the tone gate falls back to a fast "deterministic floor" pattern-check to avoid silencing you. That floor used to block **every** URL an agent tried to share — private views, dashboards, Secret-Drop one-time URLs, Telegraph pages, file downloads — because it couldn't distinguish a clickable link from a callable endpoint.

Now it **allows legitimate clickable links through** while still blocking actual command instructions.

## How It Works

Before the floor's signal scan, scheme'd `http(s)://…` URLs that are intended as click destinations are neutralized so their host/port/path/token don't trip the floor's "looks like an endpoint" detectors — **unless** the text carries a real call instruction (`curl`/`wget`, an uppercase HTTP method against a URL, or "hit/call/invoke … the endpoint"), in which case nothing is scrubbed and the floor blocks as before.

This mirrors the LLM path's existing intent-based (open-vs-call) carve-out, now at the degraded floor too.

## Safe Direction

- ✅ Links to dashboards / private views / reports / one-time Secret-Drop URLs now reach you even when the LLM is degraded
- ✅ Callable endpoints (e.g. "curl this endpoint") are still blocked fail-closed
- ✅ Command leaks (file paths, config keys, secrets, internal IDs) are unaffected

## When to Use

You'll notice this only as the ABSENCE of a bug: when my LLM backend is rate-limited or slow, a link I send you (a report, a dashboard, a one-time link) now actually reaches you instead of being silently held. Nothing to configure — it's always on.
