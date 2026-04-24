---
name: morning-weather
description: Fetch today's weather from Tempest and Ambient Weather stations and send it via iMessage
metadata:
  user_invocable: "false"
---

# Morning Weather Report

Fetch current weather and forecast from Tempest station, plus indoor and pool temperatures from Ambient Weather dashboard. Send a formatted morning greeting via iMessage.

## Steps

1. **Navigate to the Tempest station page**: https://tempestwx.com/station/125865/
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
4. **Navigate to Ambient Weather dashboard**: https://ambientweather.net/dashboard
   - The browser should already be logged in (credentials saved in Chrome)
5. **Extract indoor temperature** from Ambient Weather dashboard:
   - Look for the "Indoor" widget
   - Temperature (e.g., "72.3°F")
6. **Extract pool temperature** from the Pool widget:
   - Look for the "Pool" widget (labeled "2")
   - Temperature (e.g., "74.6°F")
7. **Check battery status** from the Batteries widget:
   - Look for "All Batteries OK" or any low battery warnings
   - Only include in message if batteries need attention
8. **Format a friendly morning message** with the weather data
9. **Send via iMessage** to +14084424360 using: `imsg send --to "+14084424360" --text "MESSAGE"`

## Output Format

```
🌤️ Roland Canyon Weather - [Day, Mon DD]

🏠 Indoor: [Indoor Temperature]°
🌡️ Outdoor: [Outdoor Temperature]° (Feels like [Feels Like]°)
💧 Humidity: [Outdoor Humidity]

Today's Forecast:
High [High]° / Low [Low]°
[Precipitation]% chance of rain

🏊 Pool: [Pool Temperature]°

[⚠️ Battery warning if needed]

Good morning!
```

## Notes

- The Tempest page is JavaScript-rendered, so you need to wait for it to load
- The Ambient Weather dashboard requires login (credentials saved in Chrome password manager)
- Use the Playwright MCP browser tools (browser_navigate, browser_snapshot)
- Keep the message concise and friendly
- This is called by the morning-weather-report job at 7am daily
- Data sources:
  - Tempest: outdoor weather, forecast, wind, conditions
  - Ambient Weather: indoor temp, pool temp, battery status
