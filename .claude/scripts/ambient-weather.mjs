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
 * Field notes (verified live 2026-07-08, operator-confirmed):
 *   tempinf / humidityin / feelsLikein  — INDOOR (console unit)
 *   temp1f  / humidity1  / feelsLike1   — slot 1 = OUTDOOR air
 *   temp2f                              — slot 2 = THE POOL (water probe: temperature
 *       only, no humidity). Absent from lastData entirely when its battery dies.
 *   pm25 / pm25_24h                     — PM2.5 air quality device
 *   batt* / battout                     — 1 = OK, 0 = LOW
 *
 * Ambient's custom sensor LABELS (what the dashboard shows as "Pool") are NOT
 * returned by the API, so the slot→name mapping lives in SENSOR_LABELS below.
 * NEVER report slot 1 as the pool to fill a gap — that emits outdoor air as a
 * fabricated pool temperature. Sanity check: a temp reading carrying humidity is
 * an AIR sensor, never the pool.
 *
 * SUSPECT_DEVICES: devices whose readings are not trustworthy. Their values are
 * still surfaced (as `pm25Suspect`) so the fault stays visible, but they can never
 * populate the alarm field (`pm25Category`). Remove an entry only after validating
 * against an independent reference — see the recorded evidence in the map.
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

// Ambient does not expose the dashboard's custom sensor names via the API, so the
// numbered-slot → real-world mapping is recorded here. Operator-confirmed 2026-07-08:
//
//   slot 1 (temp1f) = OUTDOOR air
//   slot 2 (temp2f) = THE POOL   ← matches the dashboard's "Pool" widget labelled 2
//
// When the pool probe's battery dies, slot 2 vanishes from lastData entirely. Never
// report slot 1 as the pool to fill that gap: it would emit outdoor air as a
// fabricated pool temperature. When slot 2 is missing we say so explicitly.
const SENSOR_LABELS = {
  temp1f: 'outdoorTempF',
  humidity1: 'outdoorHumidity',
  feelsLike1: 'outdoorFeelsLikeF',
  dewPoint1: 'outdoorDewPointF',
  temp2f: 'poolTempF',
  humidity2: 'poolHumidity',
};

// Devices whose readings are known-untrustworthy. Values are still surfaced (never
// silently dropped) but marked suspect and excluded from alarms.
const SUSPECT_DEVICES = new Map([
  [
    'Roland Canyon PM2.5',
    'faulty: reads ~11x the regional reference. 2026-07-08 evening it read 914 then 75 ug/m3 after the operator cleaned the fan/intake, while Open-Meteo for these coords reported 6.6 (24h range 4.2-6.6, AQI 30 Good). Cleaning helped but the laser module has lost calibration. Re-validate against a reference before removing.',
  ],
]);

const out = { fetchedAt: new Date().toISOString(), devices: [], lowBatteries: [] };

for (const d of devices) {
  const ld = d?.lastData ?? {};
  const name = d?.info?.name ?? '(unnamed)';
  const suspectReason = SUSPECT_DEVICES.get(name);
  const dev = { name, lastReading: ld.date ?? null, readings: {} };
  const c = d?.info?.coords?.coords;
  if (c?.lat != null && c?.lon != null) dev.coords = { lat: c.lat, lon: c.lon };
  if (suspectReason) {
    dev.suspect = true;
    dev.suspectReason = suspectReason;
  }

  if (ld.tempinf != null) dev.readings.indoorTempF = ld.tempinf;
  if (ld.humidityin != null) dev.readings.indoorHumidity = ld.humidityin;
  if (ld.feelsLikein != null) dev.readings.indoorFeelsLikeF = ld.feelsLikein;
  for (const [apiField, label] of Object.entries(SENSOR_LABELS)) {
    if (ld[apiField] != null) dev.readings[label] = ld[apiField];
  }
  if (ld.pm25 != null) dev.readings.pm25 = ld.pm25;
  if (ld.pm25_24h != null) dev.readings.pm25_24hAvg = ld.pm25_24h;

  for (const [k, v] of Object.entries(ld)) {
    if (/^batt/.test(k) && v === 0) {
      out.lowBatteries.push(`${name}:${k}${suspectReason ? ' (suspect device)' : ''}`);
    }
  }
  out.devices.push(dev);
}

// --- Independent drift check -------------------------------------------------
// A particle sensor does not fail loudly: it drifts and keeps reporting confident
// nonsense (the 2026-07-08 Ambient PM2.5 read 914 while the real air was 6.6).
// Nothing on the device knows. So before ANY pm2.5 value is allowed to raise an
// alarm, compare it against a regional reference for the station's own coords.
//
// Fails OPEN: if the reference is unreachable we do not block the reading, we just
// record that it could not be corroborated. A missing check must never masquerade
// as a passed check.
const DRIFT_RATIO_THRESHOLD = 3; // sensor >3x the reference ⇒ treat as drifted

async function fetchReferencePm25(lat, lon) {
  if (lat == null || lon == null) return null;
  const url =
    `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${lat}&longitude=${lon}` +
    `&current=pm2_5,us_aqi&timezone=UTC`;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
    if (!res.ok) return null;
    const j = await res.json();
    const v = j?.current?.pm2_5;
    return typeof v === 'number' ? { pm25: v, usAqi: j?.current?.us_aqi ?? null } : null;
  } catch {
    return null; // fail open
  }
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
// The pool sensor (slot 2) drops out of lastData entirely when it is offline. Make
// that an EXPLICIT fact rather than a silently-absent field, so a consumer says
// "pool sensor offline" instead of quietly omitting the pool — or worse, reaching
// for the outdoor sensor to fill the gap.
out.poolTempF = out.devices.flatMap((d) => (d.readings.poolTempF != null ? [d.readings.poolTempF] : []))[0] ?? null;
out.poolSensorOffline = out.poolTempF == null;

// Only a TRUSTED, CORROBORATED device may set pm25Category — the field consumers
// alarm on. A suspect or drifted station's value is still reported (as pm25Suspect)
// so the fault stays visible, but it can never trigger an air-quality warning.
const pmDevice = out.devices.find((d) => d.readings.pm25 != null);
if (pmDevice) {
  const pm = pmDevice.readings.pm25;

  if (pmDevice.suspect) {
    out.pm25Suspect = { value: pm, reason: pmDevice.suspectReason };
    out.pm25Category = null;
  } else {
    // Not on the manual suspect list — corroborate against a regional reference
    // before trusting it. This catches silent drift on ANY sensor, present or future.
    const ref = await fetchReferencePm25(pmDevice.coords?.lat, pmDevice.coords?.lon);
    if (!ref) {
      out.pm25Reference = null;
      out.pm25ReferenceUnavailable = true;
      out.pm25Category = pm25Category(pm); // fail open: never let a missing check block a good sensor
    } else {
      out.pm25Reference = ref;
      const ratio = ref.pm25 > 0 ? pm / ref.pm25 : null;
      out.pm25DriftRatio = ratio == null ? null : Number(ratio.toFixed(1));
      if (ratio != null && ratio > DRIFT_RATIO_THRESHOLD && pm > 20) {
        out.pm25DriftSuspected = true;
        out.pm25Suspect = {
          value: pm,
          reason: `reads ${ratio.toFixed(1)}x the regional reference (${ref.pm25} µg/m³) — sensor drift suspected`,
        };
        out.pm25Category = null;
      } else {
        out.pm25Category = pm25Category(pm);
      }
    }
  }
}

if (process.argv.includes('--json')) {
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  process.exit(0);
}

for (const d of out.devices) {
  console.log(`${d.name}${d.suspect ? '  [SUSPECT — readings not trusted]' : ''}  (last reading ${d.lastReading ?? 'n/a'})`);
  for (const [k, v] of Object.entries(d.readings)) console.log(`   ${k}: ${v}`);
}
console.log(
  out.poolSensorOffline
    ? '\n🏊 Pool: sensor OFFLINE — no reading (do NOT substitute the outdoor sensor)'
    : `\n🏊 Pool: ${out.poolTempF}°F`,
);
if (out.pm25Category) {
  const ref = out.pm25Reference ? ` (reference ${out.pm25Reference.pm25} µg/m³ — corroborated)` : ' (reference unavailable — uncorroborated)';
  console.log(`\nPM2.5 air quality: ${pmDevice.readings.pm25} µg/m³ — ${out.pm25Category}${ref}`);
} else if (out.pm25Suspect) {
  console.log(`\nPM2.5: ${out.pm25Suspect.value} µg/m³ — NOT REPORTED as air quality (${out.pm25Suspect.reason})`);
}
console.log(out.lowBatteries.length ? `\n⚠️  LOW batteries: ${out.lowBatteries.join(', ')}` : '\nAll batteries OK');
