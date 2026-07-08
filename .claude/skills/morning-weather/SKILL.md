---
name: morning-weather
description: Fetch today's weather from Tempest and Ambient Weather stations and send it via iMessage
metadata:
  user_invocable: "false"
---

# Morning Weather Report

Fetch current weather and forecast from Tempest station, plus indoor temperature, air quality and battery status from the Ambient Weather REST API. Send a formatted morning greeting via iMessage.

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
   - `devices[].readings.sensor1TempF`, `.sensor1Humidity` — remote sensor 1
   - `devices[].readings.pm25`, `.pm25_24hAvg` and top-level `pm25Category` — air quality
   - `lowBatteries[]` — only non-empty when a battery is actually LOW

   **NEVER** navigate to ambientweather.net/dashboard with Playwright. That path is permanently broken: the isolated browser profile has no saved login, and the macOS Passwords app is unreadable by any CLI. See `[[known-macos-passwords-app-unreadable]]`.

5. **Include PM2.5 when it is not "Good"** — report the value and category (e.g. "PM2.5 134 — Unhealthy"). Air quality matters more than pool temp on a smoky day.

6. **Battery status**: mention ONLY if `lowBatteries[]` is non-empty. Do not say "all batteries OK" in the message.

   ⚠️ **Pool temperature is NOT currently available.** The API returns no `temp2f`; the old "Pool widget (2)" does not exist in the response. Sensor 1 reports humidity and dew point, so it is an AIR sensor, not a water probe — do NOT label it "Pool". Omit the pool line until a real pool probe is confirmed.
7. **Format a friendly morning message** with the weather data
8. **Send via iMessage** to $USER_PHONE using: `imsg send --to "$(python3 -c "import json; d=json.load(open(.instar/config.json)); print(d.get(imessage,{}).get(userPhone,))")" --text "MESSAGE"`

## Output Format

```
🌤️ House Weather - [Day, Mon DD]

🏠 Indoor: [indoorTempF]°
🌡️ Outdoor: [Outdoor Temperature]° (Feels like [Feels Like]°)
💧 Humidity: [Outdoor Humidity]

Today's Forecast:
High [High]° / Low [Low]°
[Precipitation]% chance of rain

[😷 Air quality: PM2.5 [pm25] — [pm25Category]   ← include ONLY when not "Good"]

[⚠️ Low battery: [lowBatteries]   ← include ONLY when lowBatteries is non-empty]

Good morning!
```

Lines in `[brackets]` are conditional — omit the whole line when the condition isn't met. There is deliberately **no pool line**: the pool probe is not present in the API (see step 4). Never invent a pool temperature from `sensor1TempF`.

## Notes

- The Tempest page is JavaScript-rendered, so you need to wait for it to load
- **Ambient Weather: use `node .claude/scripts/ambient-weather.mjs --json`, never the browser.** Credentials live in the encrypted vault; the dashboard login cannot be automated (see step 4).
- Use the Playwright MCP browser tools (browser_navigate, browser_snapshot) for the **Tempest** page only
- Keep the message concise and friendly
- This is called by the morning-weather-report job at 7am daily
- If the Ambient script fails, send the report anyway with the Tempest data and say plainly which readings are missing — do not silently drop them
- Data sources:
  - Tempest (browser): outdoor weather, forecast, wind, conditions
  - Ambient Weather (REST API): indoor temp/humidity, remote sensor 1, PM2.5 air quality, low-battery alerts
