#!/usr/bin/env node
/**
 * HomeKit Device Discovery
 * Scans for both Wi-Fi and BLE HomeKit accessories
 */

const { IPDiscovery } = require('hap-controller');

console.log('🔍 Scanning for HomeKit devices...\n');

const ipDiscovery = new IPDiscovery();
const devices = new Map();

ipDiscovery.on('serviceUp', (service) => {
  const key = `${service.id}`;
  if (!devices.has(key)) {
    devices.set(key, service);
    console.log('📱 Found HomeKit device:');
    console.log(`   ID: ${service.id}`);
    console.log(`   Name: ${service.name || 'Unknown'}`);
    console.log(`   Address: ${service.address}:${service.port}`);
    console.log(`   Category: ${getCategoryName(service.ci)}`);
    console.log(`   Status: ${service.sf === 1 ? 'Paired' : 'Unpaired'}`);
    console.log(`   Model: ${service.md || 'Unknown'}`);
    console.log('');
  }
});

ipDiscovery.on('serviceDown', (service) => {
  console.log(`⚠️  Device went offline: ${service.name || service.id}`);
});

// Start discovery
ipDiscovery.start();

// Run for 10 seconds
setTimeout(() => {
  console.log(`\n✅ Discovery complete. Found ${devices.size} device(s).`);
  ipDiscovery.stop();

  if (devices.size === 0) {
    console.log('\nNo HomeKit devices found. Possible reasons:');
    console.log('  - No devices on network');
    console.log('  - Devices are BLE-only (not Wi-Fi)');
    console.log('  - Firewall blocking mDNS');
  } else {
    console.log('\nTo control these devices, you\'ll need to pair with them using their PIN codes.');
  }

  process.exit(0);
}, 10000);

// Handle errors
process.on('unhandledRejection', (error) => {
  console.error('Error during discovery:', error.message);
});

// Category mapping
function getCategoryName(categoryId) {
  const categories = {
    1: 'Other',
    2: 'Bridge',
    3: 'Fan',
    4: 'Garage Door Opener',
    5: 'Lightbulb',
    6: 'Door Lock',
    7: 'Outlet',
    8: 'Switch',
    9: 'Thermostat',
    10: 'Sensor',
    11: 'Security System',
    12: 'Door',
    13: 'Window',
    14: 'Window Covering',
    15: 'Programmable Switch',
    16: 'Range Extender',
    17: 'IP Camera',
    18: 'Video Doorbell',
    19: 'Air Purifier',
    20: 'Heater',
    21: 'Air Conditioner',
    22: 'Humidifier',
    23: 'Dehumidifier',
    28: 'Sprinkler',
    29: 'Faucet',
    30: 'Shower System',
    31: 'Television',
    32: 'Target Controller',
  };
  return categories[categoryId] || `Unknown (${categoryId})`;
}
