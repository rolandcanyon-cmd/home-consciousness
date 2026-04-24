#!/usr/bin/env node
/**
 * alexa-probe.js — Query Alexa for devices, rooms, and smart home state.
 *
 * Requires a valid cookie in .instar/state/alexa-cookie.json (run alexa-auth.js first).
 *
 * Usage:
 *   node alexa-probe.js devices              # List all Alexa devices
 *   node alexa-probe.js smarthome            # List smart home devices + groups
 *   node alexa-probe.js groups               # List Alexa device groups (rooms)
 *   node alexa-probe.js room <room_name>     # List devices in a specific room
 *
 * Output is always JSON to stdout.
 */

const Alexa = require('alexa-remote2');
const path = require('path');
const fs = require('fs');

const COOKIE_FILE = path.resolve(__dirname, '../../.instar/state/alexa-cookie.json');

function loadCookie() {
  try {
    return JSON.parse(fs.readFileSync(COOKIE_FILE, 'utf8'));
  } catch (e) {
    console.error(JSON.stringify({ error: 'No Alexa cookie found. Run alexa-auth.js first.' }));
    process.exit(1);
  }
}

async function run() {
  const args = process.argv.slice(2);
  const command = args[0] || 'devices';
  const filter = args[1] ? args[1].toLowerCase() : null;

  const saved = loadCookie();
  const alexa = new Alexa();

  await new Promise((resolve, reject) => {
    alexa.on('cookie', (cookie, csrf, macDms) => {
      // Refresh the cookie file on token refresh
      const state = {
        ...saved,
        cookie,
        csrf,
        macDms,
        cookieData: alexa.cookieData || saved.cookieData,
        savedAt: new Date().toISOString(),
      };
      fs.writeFileSync(COOKIE_FILE, JSON.stringify(state, null, 2));
    });

    alexa.init(
      {
        cookie: saved.cookieData || saved.cookie,
        formerRegistrationData: saved.cookieData,
        macDms: saved.macDms,
        alexaServiceHost: 'pitangui.amazon.com',
        amazonPage: 'amazon.com',
        cookieRefreshInterval: 7 * 24 * 60 * 60 * 1000,
        logger: null,
      },
      (err) => {
        if (err) return reject(err);
        resolve();
      }
    );
  });

  switch (command) {
    case 'devices': {
      const devices = await new Promise((res, rej) =>
        alexa.getDevices((err, data) => (err ? rej(err) : res(data)))
      );
      const list = (devices && devices.devices) || [];
      const out = list.map((d) => ({
        serialNumber: d.serialNumber,
        name: d.accountName,
        type: d.deviceType,
        family: d.deviceFamily,
        online: d.online,
        room: d.deviceOwnerCustomerId, // not actual room, just for reference
      }));
      console.log(JSON.stringify(out, null, 2));
      break;
    }

    case 'smarthome': {
      const devices = await new Promise((res, rej) =>
        alexa.getSmarthomeDevicesV2((err, data) => (err ? rej(err) : res(data)))
      );
      console.log(JSON.stringify(devices, null, 2));
      break;
    }

    case 'groups': {
      // Device groups = rooms in Alexa
      const groups = await new Promise((res, rej) =>
        alexa.getDeviceGroups((err, data) => (err ? rej(err) : res(data)))
      );
      console.log(JSON.stringify(groups, null, 2));
      break;
    }

    case 'room': {
      if (!filter) {
        console.error(JSON.stringify({ error: 'Usage: alexa-probe.js room <room_name>' }));
        process.exit(1);
      }
      const groups = await new Promise((res, rej) =>
        alexa.getDeviceGroups((err, data) => (err ? rej(err) : res(data)))
      );
      const allGroups = (groups && groups.deviceGroups) || groups || [];
      const matched = allGroups.filter(
        (g) => g.name && g.name.toLowerCase().includes(filter)
      );
      console.log(JSON.stringify(matched, null, 2));
      break;
    }

    default:
      console.error(JSON.stringify({ error: `Unknown command: ${command}` }));
      process.exit(1);
  }

  process.exit(0);
}

run().catch((err) => {
  console.error(JSON.stringify({ error: err.message }));
  process.exit(1);
});
