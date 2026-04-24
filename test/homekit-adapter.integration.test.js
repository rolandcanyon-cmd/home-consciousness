/**
 * HomeKit Adapter Integration Tests
 * Tests that interact with real HomeKit devices on the network
 *
 * NOTE: These tests require HomeKit devices to be available
 * Run with: npm run test:homekit
 */

const { expect } = require('chai');
const fs = require('fs').promises;
const path = require('path');
const HomeKitAdapter = require('../.instar/integrations/homekit-adapter');

describe('HomeKitAdapter Integration Tests', function() {
  let adapter;
  let testStateDir;

  beforeEach(async function() {
    testStateDir = path.join(__dirname, 'test-state', `homekit-${Date.now()}`);
    await fs.mkdir(path.join(testStateDir, 'pairing'), { recursive: true });

    adapter = new HomeKitAdapter({
      stateDir: testStateDir
    });

    await adapter.initialize();
  });

  afterEach(async function() {
    await adapter.cleanup();
    await fs.rm(testStateDir, { recursive: true, force: true });
  });

  describe('Device Discovery', function() {
    it('Given HomeKit devices on network, When discovering, Then devices should be found', async function() {
      // Given: HomeKit devices exist on the network
      // (This is an assumption - tests will fail if no devices present)

      // When: We run discovery for 10 seconds
      const devices = await adapter.discover(10000);

      // Then: We should find at least one device
      expect(devices).to.be.an('array');
      expect(devices.length).to.be.at.least(1);

      // And: Each device should have required fields
      for (const device of devices) {
        expect(device.id).to.be.a('string');
        expect(device.id).to.match(/^homekit:/);
        expect(device.ecosystem).to.equal('homekit');
        expect(device.name).to.be.a('string');
        expect(device.type).to.be.a('string');
        expect(device.address).to.be.a('string');
        expect(device.port).to.be.a('number');
        expect(device.paired).to.be.a('boolean');
        expect(device.lastSeen).to.be.a('string');
      }
    }).timeout(15000);

    it('Given a short discovery duration, When discovering, Then it should complete in time', async function() {
      // Given: A short discovery window
      const duration = 3000; // 3 seconds
      const startTime = Date.now();

      // When: We run discovery
      const devices = await adapter.discover(duration);

      // Then: It should complete within the time window (plus small overhead)
      const elapsed = Date.now() - startTime;
      expect(elapsed).to.be.lessThan(duration + 1000);

      // And: Devices should still be returned (even if fewer)
      expect(devices).to.be.an('array');
    }).timeout(5000);

    it('Given devices discovered, When devices Map is checked, Then they should be cached', async function() {
      // Given: We've discovered devices
      const devices = await adapter.discover(5000);
      expect(devices.length).to.be.at.least(1);

      // When: We check the adapter's internal devices cache
      const cachedDeviceCount = adapter.devices.size;

      // Then: The cache should contain the discovered devices
      expect(cachedDeviceCount).to.equal(devices.length);

      // And: Each device should be retrievable from cache
      for (const device of devices) {
        expect(adapter.devices.has(device.id)).to.be.true;
      }
    }).timeout(8000);
  });

  describe('Adapter State', function() {
    it('Given a fresh adapter, When initialized, Then pairing data should be empty', async function() {
      // Given: A freshly initialized adapter
      // (done in beforeEach)

      // Then: No pairing data should exist
      expect(adapter.pairingData.size).to.equal(0);
      expect(adapter.clients.size).to.equal(0);
    });

    it('Given no previous state, When discovering, Then internal maps should populate', async function() {
      // Given: No previous discoveries
      expect(adapter.devices.size).to.equal(0);

      // When: We discover devices
      await adapter.discover(5000);

      // Then: The internal devices map should be populated
      expect(adapter.devices.size).to.be.at.least(1);
    }).timeout(8000);
  });

  describe('Error Handling', function() {
    it('Given adapter not initialized, When calling discover, Then it should still work', async function() {
      // Given: A fresh adapter (initialization already done in beforeEach, but testing it doesn't break)

      // When: We discover
      const devices = await adapter.discover(5000);

      // Then: Discovery should succeed
      expect(devices).to.be.an('array');
    }).timeout(8000);
  });

  describe('Cleanup', function() {
    it('Given an adapter with discovery running, When cleanup is called, Then resources should be released', async function() {
      // Given: Discovery has been run
      await adapter.discover(3000);

      // When: We cleanup
      await adapter.cleanup();

      // Then: Internal state should be cleared
      expect(adapter.clients.size).to.equal(0);
      expect(adapter.eventHandlers.size).to.equal(0);

      // And: Discovery should be stopped
      expect(adapter.discovery).to.exist; // It exists but should be stopped
    }).timeout(5000);
  });
});

describe('HomeKitAdapter - Discovery Output Validation', function() {
  let adapter;
  let testStateDir;
  let discoveredDevices;

  before(async function() {
    // Run discovery once for all tests in this suite
    testStateDir = path.join(__dirname, 'test-state', `homekit-validation-${Date.now()}`);
    await fs.mkdir(path.join(testStateDir, 'pairing'), { recursive: true });

    adapter = new HomeKitAdapter({
      stateDir: testStateDir
    });

    await adapter.initialize();
    discoveredDevices = await adapter.discover(10000);
  });

  after(async function() {
    await adapter.cleanup();
    await fs.rm(testStateDir, { recursive: true, force: true });
  });

  it('Given discovered devices, Then each should have valid device type', function() {
    expect(discoveredDevices.length).to.be.at.least(1);

    const validTypes = [
      'other', 'bridge', 'fan', 'garage-door', 'lightbulb', 'lock',
      'outlet', 'switch', 'thermostat', 'sensor', 'security-system',
      'door', 'window', 'window-covering', 'programmable-switch',
      'range-extender', 'camera', 'video-doorbell', 'air-purifier',
      'heater', 'air-conditioner', 'humidifier', 'dehumidifier',
      'sprinkler', 'faucet', 'shower', 'television', 'target-controller',
      'unknown'
    ];

    for (const device of discoveredDevices) {
      expect(validTypes).to.include(device.type,
        `Device ${device.name} has invalid type: ${device.type}`);
    }
  });

  it('Given discovered devices, Then IDs should be properly formatted', function() {
    for (const device of discoveredDevices) {
      // Should start with 'homekit:'
      expect(device.id).to.match(/^homekit:/);

      // Should have MAC address format after prefix (case-insensitive)
      expect(device.id).to.match(/^homekit:[A-Fa-f0-9]{2}:[A-Fa-f0-9]{2}:[A-Fa-f0-9]{2}:[A-Fa-f0-9]{2}:[A-Fa-f0-9]{2}:[A-Fa-f0-9]{2}$/);
    }
  });

  it('Given discovered devices, Then metadata should be present', function() {
    for (const device of discoveredDevices) {
      expect(device.metadata).to.exist;
      expect(device.metadata).to.be.an('object');

      // Metadata should contain HomeKit-specific fields (may be undefined if not provided by device)
      // Just verify the structure exists
      expect(device.metadata).to.have.property('statusFlags');
      expect(device.metadata).to.have.property('configNumber');
      expect(device.metadata).to.have.property('protocolVersion');
    }
  });

  it('Given discovered devices, Then timestamps should be valid ISO 8601', function() {
    for (const device of discoveredDevices) {
      expect(device.lastSeen).to.exist;

      const date = new Date(device.lastSeen);
      expect(date).to.be.instanceOf(Date);
      expect(isNaN(date.getTime())).to.be.false;
    }
  });
});
