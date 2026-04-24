#!/bin/bash
# Fetch weather data from Tempest weather station
# Station ID: 125865 (Roland Canyon Rd)

set -e

# Navigate to the station and extract weather data using Playwright evaluate
weather_data=$(cat <<'EOF' | node -
const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

async function getWeather() {
  try {
    // Use Playwright evaluate to extract weather data
    const code = `
      async () => {
        // Wait a bit for data to load
        await new Promise(r => setTimeout(r, 1000));

        // Extract current conditions from the page structure
        const getText = (selector) => {
          const el = document.querySelector(selector);
          return el ? el.textContent.trim() : 'N/A';
        };

        // Get all paragraph elements in the weather card area
        const paragraphs = Array.from(document.querySelectorAll('p'));

        // Find specific data points
        let temp = 'N/A', feelsLike = 'N/A', condition = 'N/A';
        let humidity = 'N/A', pressure = 'N/A', wind = 'N/A', uv = 'N/A';

        paragraphs.forEach(p => {
          const text = p.textContent.trim();
          if (text.match(/^\\d+°$/)) temp = text;
          if (text.startsWith('Feels Like')) feelsLike = text.replace('Feels Like ', '');
          if (text.match(/^(Partly Cloudy|Clear|Rain|Thunderstorms|Cloudy)/)) condition = text;
          if (text.includes('% Humidity')) humidity = text;
        });

        // Get group labels
        const groups = Array.from(document.querySelectorAll('[role="group"]'));
        groups.forEach(g => {
          const label = g.getAttribute('aria-label') || '';
          const text = g.textContent.trim();
          if (label.includes('Pressure')) pressure = text;
          if (label.includes('Wind')) wind = text;
          if (label.includes('UV')) uv = text;
        });

        return JSON.stringify({
          temp, feelsLike, condition, humidity, pressure, wind, uv,
          timestamp: new Date().toISOString()
        });
      }
    `;

    // Call Playwright MCP via imsg rpc
    const result = await execPromise(\`imsg rpc <<'JSONRPC'
{"jsonrpc":"2.0","id":1,"method":"mcp__playwright__browser_evaluate","params":{"function":\${JSON.stringify(code)}}}
JSONRPC\`);

    const response = JSON.parse(result.stdout);
    if (response.result) {
      console.log(response.result);
    } else {
      throw new Error('No result from browser evaluate');
    }
  } catch (error) {
    console.error(JSON.stringify({ error: error.message }));
    process.exit(1);
  }
}

getWeather();
EOF
)

# Check if we got valid data
if echo "$weather_data" | jq -e . >/dev/null 2>&1; then
  # Parse and format the weather data
  temp=$(echo "$weather_data" | jq -r '.temp')
  feels_like=$(echo "$weather_data" | jq -r '.feelsLike')
  condition=$(echo "$weather_data" | jq -r '.condition')
  humidity=$(echo "$weather_data" | jq -r '.humidity')
  pressure=$(echo "$weather_data" | jq -r '.pressure')
  wind=$(echo "$weather_data" | jq -r '.wind')
  uv=$(echo "$weather_data" | jq -r '.uv')

  # Get current date
  date_str=$(date '+%a, %b %d')

  # Format the message
  cat <<MESSAGE
🌤️ Roland Canyon Weather - $date_str

$temp
$condition
Feels like $feels_like

💧 $humidity
🌡️ $pressure
💨 $wind
☀️ $uv

Good morning!
MESSAGE
else
  echo "⚠️ Couldn't fetch weather data from Tempest station"
  exit 1
fi
