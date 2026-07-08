#!/usr/bin/env node
/**
 * ambient-weather.mjs — fetch current Ambient Weather readings via the REST API.
 *
 * Replaces the old browser-scraping path (ambientweather.net/dashboard via
 * Playwright), which could never work: the isolated browser profile has no saved
 * login and the macOS Passwords app is unreadable by any CLI.
 *
 * Credentials come from the encrypted vault (`ambient_api_key`, `ambient_app_key`).
 * They are never printed, never passed as arguments, and are scrubbed out of any
 * error body before it is shown.
 *
 * Usage:
 *   node .claude/scripts/ambient-weather.mjs            # human-readable summary
 *   node .claude/scripts/ambient-weather.mjs --json      # machine-readable
 *
 * Exit codes: 0 ok · 1 auth/network/vault failure
 *
 * Field notes (verified live 2026-07-08):
 *   tempinf / humidityin / feelsLikein  — INDOOR (console unit)
 *   temp1f  / humidity1  / feelsLike1   — remote sensor 1 (an AIR sensor: it
 *       reports humidity + dew point, so it is NOT a pool water probe)
 *   pm25 / pm25_24h                     — PM2.5 air quality device
 *   batt* / battout                     — 1 = OK, 0 = LOW
 *   There is no temp2f; the old skill's "Pool widget (2)" does not exist in the
 *   API response. If a pool probe is added later it will appear as its own field.
 */

import * as path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const AGENT_HOME = process.env.INSTAR_AGENT_HOME || path.resolve(process.cwd());

let SecretStore;
try {
  ({ SecretStore } = require(path.join(AGENT_HOME, '.instar/shadow-install/node_modules/instar/dist/core/SecretStore.js')));
} catch {
  console.error('ambient-weather: cannot resolve SecretStore (run from the agent home)');
  process.exit(1);
}

let apiKey, appKey;
try {
  const store = new SecretStore({ stateDir: path.join(AGENT_HOME, '.instar') });
  apiKey = store.get('ambient_api_key');
  appKey = store.get('ambient_app_key');
} catch {
  console.error('ambient-weather: vault unreadable — do NOT repair/rotate; surface to the operator');
  process.exit(1);
}
if (!apiKey || !appKey) {
  console.error('ambient-weather: ambient_api_key / ambient_app_key missing from the vault');
  process.exit(1);
}

const scrub = (s) =>
  String(s).split(apiKey).join('<apiKey>').split(appKey).join('<appKey>');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Ambient Weather rate-limits to ~1 request/second per API key and answers 429
// {"error":"above-user-rate-limit"}. Retry with backoff rather than fail the
// morning job just because another caller touched the API in the same second.
async function fetchDevices() {
  const url = `https://rt.ambientweather.net/v1/devices?applicationKey=${encodeURIComponent(appKey)}&apiKey=${encodeURIComponent(apiKey)}`;
  const delays = [1200, 2500, 5000];
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, { signal: AbortSignal.timeout(20000) });
    const body = await res.text();
    if (res.status === 200) return JSON.parse(body);
    if (res.status === 429 && attempt < delays.length) {
      await sleep(delays[attempt]);
      continue;
    }
    const hint = res.status === 429 ? ' (rate limited — ~1 req/sec per key)' : '';
    throw new Error(`HTTP ${res.status}${hint} — ${scrub(body).slice(0, 160)}`);
  }
}

let devices;
try {
  devices = await fetchDevices();
} catch (e) {
  console.error(`ambient-weather: ${scrub(e.message ?? e.name ?? 'request failed').slice(0, 200)}`);
  process.exit(1);
}

const out = { fetchedAt: new Date().toISOString(), devices: [], lowBatteries: [] };

for (const d of devices) {
  const ld = d?.lastData ?? {};
  const dev = {
    name: d?.info?.name ?? '(unnamed)',
    lastReading: ld.date ?? null,
    readings: {},
  };
  if (ld.tempinf != null) dev.readings.indoorTempF = ld.tempinf;
  if (ld.humidityin != null) dev.readings.indoorHumidity = ld.humidityin;
  if (ld.feelsLikein != null) dev.readings.indoorFeelsLikeF = ld.feelsLikein;
  if (ld.temp1f != null) dev.readings.sensor1TempF = ld.temp1f;
  if (ld.humidity1 != null) dev.readings.sensor1Humidity = ld.humidity1;
  if (ld.pm25 != null) dev.readings.pm25 = ld.pm25;
  if (ld.pm25_24h != null) dev.readings.pm25_24hAvg = ld.pm25_24h;

  for (const [k, v] of Object.entries(ld)) {
    if (/^batt/.test(k) && v === 0) out.lowBatteries.push(`${dev.name}:${k}`);
  }
  out.devices.push(dev);
}

// PM2.5 → EPA AQI category (breakpoints, µg/m³)
function pm25Category(v) {
  if (v == null) return null;
  if (v <= 12) return 'Good';
  if (v <= 35.4) return 'Moderate';
  if (v <= 55.4) return 'Unhealthy for Sensitive Groups';
  if (v <= 150.4) return 'Unhealthy';
  if (v <= 250.4) return 'Very Unhealthy';
  return 'Hazardous';
}
const pm = out.devices.flatMap((d) => (d.readings.pm25 != null ? [d.readings.pm25] : []))[0];
if (pm != null) out.pm25Category = pm25Category(pm);

if (process.argv.includes('--json')) {
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  process.exit(0);
}

for (const d of out.devices) {
  console.log(`${d.name}  (last reading ${d.lastReading ?? 'n/a'})`);
  for (const [k, v] of Object.entries(d.readings)) console.log(`   ${k}: ${v}`);
}
if (out.pm25Category) console.log(`\nPM2.5 air quality: ${pm} µg/m³ — ${out.pm25Category}`);
console.log(out.lowBatteries.length ? `\n⚠️  LOW batteries: ${out.lowBatteries.join(', ')}` : '\nAll batteries OK');
