#!/usr/bin/env node
/**
 * Fetch weather data from Tempest weather station
 * Station ID configured in TEMPEST_STATION_ID env var
 * Uses Playwright MCP to scrape the JS-rendered page
 */

const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

async function fetchWeather() {
  try {
    // Navigate to the Tempest station page
    const navCmd = `claude mcp call playwright browser_navigate --url "https://tempestwx.com/station/125865/"`;
    await execPromise(navCmd);

    // Wait a moment for the page to fully render
    await new Promise(resolve => setTimeout(resolve, 2000));

    // Extract weather data using JavaScript evaluation
    const evalCmd = `claude mcp call playwright browser_evaluate --function "() => {
      const data = {};

      // Current conditions
      const tempEl = document.querySelector('p[class*=\\\"temperature\\\"]');
      const feelsLikeEl = document.querySelector('p[class*=\\\"feelsLike\\\"]');
      const conditionEl = document.querySelector('p[class*=\\\"condition\\\"]');
      const humidityEl = document.querySelector('p:contains(\\\"Humidity\\\")');
      const pressureEl = document.querySelector('group[aria-label*=\\\"Pressure\\\"]');
      const windEl = document.querySelector('group[aria-label*=\\\"Wind\\\"]');
      const uvEl = document.querySelector('group[aria-label*=\\\"UV\\\"]');

      // Today's forecast
      const forecastEls = document.querySelectorAll('div[class*=\\\"forecast\\\"]');

      return {
        current: {
          temperature: tempEl?.textContent || 'N/A',
          feelsLike: feelsLikeEl?.textContent || 'N/A',
          condition: conditionEl?.textContent || 'N/A',
          humidity: humidityEl?.textContent || 'N/A',
          pressure: pressureEl?.textContent || 'N/A',
          wind: windEl?.textContent || 'N/A',
          uv: uvEl?.textContent || 'N/A'
        }
      };
    }"`;

    const { stdout } = await execPromise(evalCmd);
    const weather = JSON.parse(stdout);

    return weather;
  } catch (error) {
    console.error('Error fetching weather:', error);
    return null;
  }
}

async function formatWeatherMessage(weather) {
  if (!weather) {
    return "⚠️ Couldn't fetch weather data from Tempest station";
  }

  const { current } = weather;

  return `🌤️ House Weather - ${new Date().toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}

${current.temperature}
${current.condition}
Feels like ${current.feelsLike}

💧 ${current.humidity}
🌡️ ${current.pressure}
💨 ${current.wind}
☀️ ${current.uv}`;
}

async function main() {
  const weather = await fetchWeather();
  const message = await formatWeatherMessage(weather);
  console.log(message);
}

if (require.main === module) {
  main();
}

module.exports = { fetchWeather, formatWeatherMessage };
