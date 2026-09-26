---
name: project-ambient-weather-login-blocked
description: RESOLVED 2026-07-08 — Ambient Weather API keys now in the encrypted vault; use the REST API, never the browser login
metadata: 
  node_type: memory
  type: project
  originSessionId: dff0018a-e17d-4f36-b5d8-4fe9c62ad212
---

**RESOLVED 2026-07-08.** The Ambient Weather credentials now live in the agent's encrypted vault as `ambient_api_key` and `ambient_app_key` (64 chars each), collected once via Secret Drop and verified live against the API — HTTP 200, 2 devices: **Roland Canyon** and **Roland Canyon PM2.5**.

**How to use (never re-ask the user):**
```
node .instar/scripts/secret-get.mjs ambient_api_key   # value → stdout, pipe it, never echo
node .instar/scripts/secret-get.mjs ambient_app_key
```
Endpoint that works: `https://rt.ambientweather.net/v1/devices?applicationKey=<app>&apiKey=<api>` (note the `rt.` host). Each device carries `info.name` and `lastData` (temps, humidity, PM2.5).

**Do NOT** retry the browser-login path (`ambientweather.net/dashboard` via Playwright). It failed at least three times (2026-06-18, 2026-07-06, 2026-07-08) because the isolated Playwright profile has no saved login and the macOS password manager isn't reachable from it. That path is closed by design; the REST API needs no login and no browser.

**Related history:** the earlier 2026-07-06 attempt failed because there was no vault at all, so a one-off Secret Drop retrieval evaporated. A vault now exists (`.instar/secrets/config.secrets.enc`, gitignored) and `secret-set.mjs` was written to store named secrets from stdin. See [[known-macos-passwords-app-unreadable]].

**Two stations — sensor slot map (operator-confirmed 2026-07-08):**
- **"Roland Canyon"** — the real station. Slots:
  - indoor console → `tempinf` / `humidityin` / `feelsLikein`
  - **slot 1 (`temp1f`) = OUTDOOR air** (69°F on 2026-07-08). NOT the pool.
  - **slot 2 (`temp2f`) = THE POOL** — matches the dashboard's "Pool" widget labelled 2. ONLINE as of 2026-07-08 20:24 (85.6°F) after a battery change; it had been offline earlier that day. A dead battery makes the slot vanish from `lastData` entirely rather than report null.
  - **Corroborating physics:** slot 2 reports temperature ONLY (water probe). Slot 1 reports humidity + dew point (air sensor). If a temp slot carries humidity, it is NOT the pool.
  - Ambient's API does NOT return the dashboard's custom sensor labels; the slot→name map is hardcoded in `SENSOR_LABELS` in the script.
- **"Roland Canyon PM2.5"** — **emits bad data** (Adrian, 2026-07-08: ~135 µg/m³, 24h avg ~157; later that evening it read **914 µg/m³**, off the EPA scale — confirming the fault). Listed in `SUSPECT_DEVICES`; raw value still surfaces as `pm25Suspect` so the fault stays visible, but it can never populate `pm25Category` (the alarm field). **Do not report air quality** until fixed.

**The trap I fell into (don't repeat):** I saw only one non-indoor sensor (`temp1f`), assumed it was the pool, and labelled it `poolTempF` — which would have reported outdoor air as the pool temperature every morning. The pool sensor being OFFLINE is exactly why slot 2 was missing. When a sensor is absent, say "offline"; **never** fill the gap with a neighbouring sensor. The script now emits `poolSensorOffline: true` explicitly.

**Use the script, not raw curl:** `node .claude/scripts/ambient-weather.mjs [--json]` — reads the vault, retries the API's ~1-req/sec 429 rate limit with backoff, scrubs credentials from error bodies. The morning-weather skill was rewritten to use it (commit `da841a0`).
