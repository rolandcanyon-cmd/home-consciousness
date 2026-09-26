---
name: known-purpleair-node-fetch-ehostunreach
description: "ambient-weather.mjs reports PM2.5 \"fetch failed\" every day even though the PurpleAir Flex device is healthy and reachable"
metadata: 
  node_type: memory
  type: project
  originSessionId: 716df541-e8b0-49e7-9037-9fc7c4bf2f8e
  modified: 2026-08-19T16:16:51.915Z
---

Discovered 2026-08-19: the morning weather report's air-quality line has been silently omitted (via the documented `pm25Unavailable` fallback) because `.claude/scripts/ambient-weather.mjs`'s `fetchPurpleAirLocalOnce()` gets `EHOSTUNREACH` from Node's `fetch()` connecting to `http://10.0.0.140/json` — every single time, on retry too.

**The device itself is fine.** `curl --max-time 20 http://10.0.0.140/json` from the same shell, same machine, succeeds instantly and consistently (`pm2_5_atm≈10.6`, `pm2_5_atm_b≈10.5` → Good). A raw Node repro (`fetch("http://10.0.0.140/json", {signal: AbortSignal.timeout(15000)})`) reproduces the EHOSTUNREACH deterministically, binding from local `10.0.0.111:xxxxx` (the machine's only en0 interface — no VPN/multi-homing to blame).

**Why:** unconfirmed — looks like a Node/undici-specific networking quirk (possibly IPv4/IPv6 dual-stack handling, or something about how Node's fetch resolves a literal IP differently than curl/libcurl) on this machine, not a code bug in the retry/parsing logic itself.

**Not yet fixed.** Options not yet tried: forcing IPv4 explicitly in the fetch (e.g. via `family: 4` on a manual `http.get` instead of `fetch`), or shelling out to `curl` from the script as a workaround. Re-check this before assuming PM2.5 unavailability is a device problem — it almost certainly isn't.

See [[project_purpleair_flex]] for the device's normal behavior (15s timeout, ~8.5s cold start).
