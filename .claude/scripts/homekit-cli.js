#!/usr/bin/env node
/**
 * HomeKit CLI Tool
 * Interactive command-line interface for HomeKit device management
 */

const HomeKitAdapter = require('../../.instar/integrations/homekit-adapter');
const DeviceRegistry = require('../../.instar/integrations/device-registry');
const readline = require('readline');

const adapter = new HomeKitAdapter();
const registry = new DeviceRegistry();

async function main() {
  console.log('🏠 HomeKit Device Manager\n');

  await adapter.initialize();
  await registry.initialize();

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: 'homekit> '
  });

  console.log('Commands:');
  console.log('  discover     - Scan for HomeKit devices');
  console.log('  list         - Show registered devices');
  console.log('  pair <id>    - Pair with a device (you\'ll be prompted for PIN)');
  console.log('  info <id>    - Get device capabilities');
  console.log('  state <id>   - Get current device state');
  console.log('  set <id>     - Control a device (interactive)');
  console.log('  stats        - Show registry statistics');
  console.log('  help         - Show this help');
  console.log('  exit         - Quit\n');

  rl.prompt();

  rl.on('line', async (line) => {
    const [command, ...args] = line.trim().split(/\s+/);

    try {
      switch (command) {
        case 'discover':
          await handleDiscover();
          break;

        case 'list':
          await handleList(args[0]);
          break;

        case 'pair':
          if (!args[0]) {
            console.log('Usage: pair <device-id>');
          } else {
            await handlePair(args[0], rl);
          }
          break;

        case 'info':
          if (!args[0]) {
            console.log('Usage: info <device-id>');
          } else {
            await handleInfo(args[0]);
          }
          break;

        case 'state':
          if (!args[0]) {
            console.log('Usage: state <device-id>');
          } else {
            await handleState(args[0]);
          }
          break;

        case 'set':
          if (!args[0]) {
            console.log('Usage: set <device-id>');
          } else {
            await handleSet(args[0], rl);
          }
          break;

        case 'stats':
          await handleStats();
          break;

        case 'help':
          console.log('\nCommands:');
          console.log('  discover     - Scan for HomeKit devices');
          console.log('  list [filter] - Show registered devices (all/paired/unpaired)');
          console.log('  pair <id>    - Pair with a device');
          console.log('  info <id>    - Get device capabilities');
          console.log('  state <id>   - Get current device state');
          console.log('  set <id>     - Control a device');
          console.log('  stats        - Show registry statistics');
          console.log('  exit         - Quit\n');
          break;

        case 'exit':
        case 'quit':
          console.log('Goodbye!');
          await adapter.cleanup();
          process.exit(0);
          break;

        case '':
          // Empty line, just re-prompt
          break;

        default:
          console.log(`Unknown command: ${command}. Type 'help' for commands.`);
      }
    } catch (err) {
      console.error(`Error: ${err.message}`);
    }

    rl.prompt();
  });

  rl.on('close', async () => {
    console.log('\nGoodbye!');
    await adapter.cleanup();
    process.exit(0);
  });
}

async function handleDiscover() {
  console.log('🔍 Scanning for HomeKit devices...');

  const devices = await adapter.discover(10000);

  if (devices.length === 0) {
    console.log('No devices found.');
    return;
  }

  console.log(`\nFound ${devices.length} device(s):\n`);

  // Register all discovered devices
  await registry.registerBatch(devices);

  for (const device of devices) {
    console.log(`${device.paired ? '✓' : '○'} ${device.id}`);
    console.log(`  Name: ${device.name}`);
    console.log(`  Type: ${device.type}`);
    console.log(`  Model: ${device.model}`);
    console.log(`  Address: ${device.address}:${device.port}`);
    console.log(`  Status: ${device.paired ? 'Paired' : 'Not paired'}`);
    console.log('');
  }
}

async function handleList(filter) {
  const filters = {};

  if (filter === 'paired') {
    filters.paired = true;
  } else if (filter === 'unpaired') {
    filters.paired = false;
  }

  const devices = registry.getAll(filters);

  if (devices.length === 0) {
    console.log('No devices registered. Run "discover" first.');
    return;
  }

  console.log(`\nRegistered devices (${devices.length}):\n`);

  for (const device of devices) {
    console.log(`${device.paired ? '✓' : '○'} ${device.id}`);
    console.log(`  Name: ${device.name}`);
    console.log(`  Type: ${device.type}`);
    console.log(`  Location: ${device.location || 'Not set'}`);
    console.log(`  Last seen: ${device.lastSeen}`);
    console.log('');
  }
}

async function handlePair(deviceId, rl) {
  const device = registry.get(deviceId);

  if (!device) {
    console.log(`Device ${deviceId} not found. Run "discover" first.`);
    return;
  }

  if (device.paired) {
    console.log(`Device ${deviceId} is already paired.`);
    return;
  }

  console.log(`\nPairing with: ${device.name}`);
  console.log('You need the 8-digit HomeKit PIN for this device.');
  console.log('Format: XXX-XX-XXX (e.g., 123-45-678)\n');

  return new Promise((resolve) => {
    rl.question('Enter PIN: ', async (pin) => {
      try {
        await adapter.pair(deviceId, pin);
        await registry.setPaired(deviceId, true);
        console.log(`✅ Successfully paired with ${device.name}`);
      } catch (err) {
        console.error(`Failed to pair: ${err.message}`);
      }
      resolve();
    });
  });
}

async function handleInfo(deviceId) {
  const device = registry.get(deviceId);

  if (!device) {
    console.log(`Device ${deviceId} not found.`);
    return;
  }

  if (!device.paired) {
    console.log(`Device ${deviceId} is not paired. Pair it first.`);
    return;
  }

  console.log(`\nGetting capabilities for: ${device.name}...`);

  const capabilities = await adapter.getCapabilities(deviceId);

  console.log(JSON.stringify(capabilities, null, 2));
}

async function handleState(deviceId) {
  const device = registry.get(deviceId);

  if (!device) {
    console.log(`Device ${deviceId} not found.`);
    return;
  }

  if (!device.paired) {
    console.log(`Device ${deviceId} is not paired. Pair it first.`);
    return;
  }

  console.log(`\nGetting state for: ${device.name}...`);

  const state = await adapter.getState(deviceId);

  console.log(JSON.stringify(state, null, 2));
}

async function handleSet(deviceId, rl) {
  const device = registry.get(deviceId);

  if (!device) {
    console.log(`Device ${deviceId} not found.`);
    return;
  }

  if (!device.paired) {
    console.log(`Device ${deviceId} is not paired. Pair it first.`);
    return;
  }

  console.log(`\nControl: ${device.name}`);
  console.log('Enter characteristic ID and value (e.g., "1.10 true" to turn on)');
  console.log('Format: <aid>.<iid> <value>');
  console.log('Tip: Run "info <id>" first to see available characteristics\n');

  return new Promise((resolve) => {
    rl.question('Set: ', async (input) => {
      const [charId, value] = input.trim().split(/\s+/);

      if (!charId || value === undefined) {
        console.log('Invalid format. Use: <aid>.<iid> <value>');
        resolve();
        return;
      }

      // Parse value
      let parsedValue = value;
      if (value === 'true') parsedValue = true;
      else if (value === 'false') parsedValue = false;
      else if (!isNaN(value)) parsedValue = parseFloat(value);

      try {
        await adapter.setState(deviceId, { [charId]: parsedValue });
        console.log(`✅ Set ${charId} = ${parsedValue}`);
      } catch (err) {
        console.error(`Failed: ${err.message}`);
      }

      resolve();
    });
  });
}

async function handleStats() {
  const stats = registry.getStats();

  console.log('\n📊 Registry Statistics:\n');
  console.log(`Total devices: ${stats.total}`);
  console.log(`Paired: ${stats.paired}`);
  console.log(`Unpaired: ${stats.unpaired}\n`);

  console.log('By ecosystem:');
  for (const [eco, count] of Object.entries(stats.byEcosystem)) {
    console.log(`  ${eco}: ${count}`);
  }

  console.log('\nBy type:');
  for (const [type, count] of Object.entries(stats.byType)) {
    console.log(`  ${type}: ${count}`);
  }

  console.log('\nBy location:');
  for (const [loc, count] of Object.entries(stats.byLocation)) {
    console.log(`  ${loc}: ${count}`);
  }

  console.log('');
}

// Start the CLI
main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
