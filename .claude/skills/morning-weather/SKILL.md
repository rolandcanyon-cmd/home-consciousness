---
name: morning-weather
description: Fetch today's weather from Tempest and Ambient Weather stations and send it via iMessage
metadata:
  user_invocable: "false"
---

# Morning Weather Report

Fetch current weather and forecast from Tempest station, plus indoor/outdoor temperature, pool temperature and battery status from the Ambient Weather REST API. Send a formatted morning greeting via iMessage.

## Steps

1. **Look up the Tempest station URL from FunkyGibbon** (source of truth — never hardcode it):
   - If the `kittenkong` MCP tools are available, call `search_entities` with query "tempest" and read `station_url` from the matching device's content.
   - Otherwise, query the API directly: `curl -s -X POST http://localhost:8000/api/v1/graph/search -H "Authorization: Bearer $FUNKYGIBBON_TOKEN" -H 'Content-Type: application/json' -d '{"query":"tempest weather station"}'` (the entity is named "Tempest Weather Station"; `FUNKYGIBBON_TOKEN` is set in the `kittenkong` MCP server's env in `.claude/settings.json` — reuse that value, don't hardcode a second copy).
   - Navigate to the `station_url` from that entity's content (currently https://tempestwx.com/station/125865/, but always resolve it live — the station can change).
2. **Extract current outdoor weather data** from Tempest using browser_snapshot:
   - Current temperature (e.g., "56°")
   - Feels like temperature (e.g., "Feels Like 56°")
   - Condition (Partly Cloudy, Clear, etc.)
   - Humidity percentage (e.g., "87% Humidity")
   - Wind speed and direction (e.g., "W 2 mph")
3. **Extract today's forecast** from Tempest:
   - Look for "Today" in the forecast cards
   - Today's high and low temperatures
   - Condition forecast (e.g., "Partly Cloudy")
   - Precipitation chance (percentage)
4. **Get Ambient Weather readings via the REST API** (NOT the browser):
   ```
   node .claude/scripts/ambient-weather.mjs --json
   ```
   The script reads `ambient_api_key` / `ambient_app_key` from the encrypted vault, retries the API's ~1-req/sec rate limit, and never prints credentials. It returns:
   - `devices[].readings.indoorTempF`, `.indoorHumidity`, `.indoorFeelsLikeF` — indoor console
   - `devices[].readings.outdoorTempF`, `.outdoorHumidity`, `.outdoorFeelsLikeF` — **outdoor air** (API slot `temp1f`)
   - `devices[].readings.poolTempF` — **the pool** (API slot `temp2f`)
   - top-level `poolTempF` and `poolSensorOffline` — see step 5
   - `lowBatteries[]` — only non-empty when a battery is actually LOW
   - `pm25Category` — air-quality alarm field. **Currently always `null`**, see step 6.

   Ambient does not return the dashboard's custom sensor labels, so the slot→name mapping lives in `SENSOR_LABELS` in the script.

   **NEVER** navigate to ambientweather.net/dashboard with Playwright. That path is permanently broken: the isolated browser profile has no saved login, and the macOS Passwords app is unreadable by any CLI. See `[[known-macos-passwords-app-unreadable]]`.

5. **Pool: the sensor is currently OFFLINE.** When `poolSensorOffline` is true there is no pool reading. Say so plainly ("pool sensor offline") or omit the line — but **never substitute the outdoor sensor.** Slot 1 is outdoor air (69°F today); reporting it as the pool would be a fabricated reading. When the sensor comes back, `poolTempF` populates and the line works automatically.

6. **Air quality: do NOT report it.** The "Roland Canyon PM2.5" station is emitting bad data (operator-confirmed 2026-07-08 — ~135 µg/m³, 24h average ~157, implausible). The script marks that device `suspect: true`, leaves `pm25Category` null, and exposes the raw value as `pm25Suspect` so the fault stays visible rather than hidden.

   Report air quality **only** when `pm25Category` is non-null and not "Good". Once the sensor is repaired, remove that station from `SUSPECT_DEVICES` in the script and this becomes automatic.

7. **Battery status**: mention ONLY if `lowBatteries[]` is non-empty. Do not say "all batteries OK" in the message. Entries tagged `(suspect device)` come from the faulty PM2.5 station — don't alarm on those.

   Note: the Ambient station also reports **outdoor** temp/humidity, so it can cross-check or stand in for Tempest if the Tempest page fails to load.
8. **Format a friendly morning message** with the weather data
9. **Send via iMessage** to $USER_PHONE using: `imsg send --to "$(python3 -c "import json; d=json.load(open(.instar/config.json)); print(d.get(imessage,{}).get(userPhone,))")" --text "MESSAGE"`

## Output Format

```
🌤️ House Weather - [Day, Mon DD]

🏠 Indoor: [indoorTempF]°
🌡️ Outdoor: [Outdoor Temperature]° (Feels like [Feels Like]°)
💧 Humidity: [Outdoor Humidity]

Today's Forecast:
High [High]° / Low [Low]°
[Precipitation]% chance of rain

[🏊 Pool: [poolTempF]°   ← ONLY when poolSensorOffline is false. NEVER use outdoorTempF here.]

[😷 Air quality: PM2.5 [pm25] — [pm25Category]   ← ONLY when pm25Category is non-null and not "Good"]

[⚠️ Low battery: [lowBatteries]   ← ONLY when lowBatteries is non-empty]

Good morning!
```

Lines in `[brackets]` are conditional — omit the whole line when the condition isn't met. Right now BOTH the pool line and the air-quality line are suppressed: the pool sensor is offline and the PM2.5 station is faulty. Never fill either gap with another sensor's reading.

## Notes

- The Tempest page is JavaScript-rendered, so you need to wait for it to load
- **Ambient Weather: use `node .claude/scripts/ambient-weather.mjs --json`, never the browser.** Credentials live in the encrypted vault; the dashboard login cannot be automated (see step 4).
- Use the Playwright MCP browser tools (browser_navigate, browser_snapshot) for the **Tempest** page only
- Keep the message concise and friendly
- This is called by the morning-weather-report job at 7am daily
- If the Ambient script fails, send the report anyway with the Tempest data and say plainly which readings are missing — do not silently drop them
- Data sources:
  - Tempest (browser): outdoor weather, forecast, wind, conditions
  - Ambient Weather (REST API): indoor temp/humidity, OUTDOOR temp/humidity (slot 1), pool temp (slot 2, currently OFFLINE), low-battery alerts. (PM2.5 station is faulty — air quality suppressed.)
