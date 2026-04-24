/**
 * Device Registry Tests
 * BDD-style tests using Given/When/Then structure
 */

const { expect } = require('chai');
const fs = require('fs').promises;
const path = require('path');
const DeviceRegistry = require('../.instar/integrations/device-registry');

describe('DeviceRegistry', function() {
  let registry;
  let testStateDir;

  // Setup: Create a temporary test directory
  beforeEach(async function() {
    testStateDir = path.join(__dirname, 'test-state', `registry-${Date.now()}`);
    await fs.mkdir(testStateDir, { recursive: true });

    registry = new DeviceRegistry({
      stateDir: testStateDir
    });
  });

  // Cleanup: Remove test directory
  afterEach(async function() {
    await fs.rm(testStateDir, { recursive: true, force: true });
  });

  describe('Initialization', function() {
    it('Given a fresh registry, When initialized, Then it should start empty', async function() {
      // Given: A fresh DeviceRegistry instance
      // (created in beforeEach)

      // When: We initialize it
      await registry.initialize();

      // Then: It should have no devices
      const devices = registry.getAll();
      expect(devices).to.be.an('array').that.is.empty;
      expect(registry.devices.size).to.equal(0);
    });

    it('Given an existing registry file, When initialized, Then it should load devices', async function() {
      // Given: An existing registry file with one device
      const registryFile = path.join(testStateDir, 'registry.json');
      const existingData = {
        version: '1.0',
        lastUpdated: new Date().toISOString(),
        devices: {
          'test:device:1': {
            id: 'test:device:1',
            name: 'Test Device',
            ecosystem: 'test',
            type: 'sensor'
          }
        }
      };
      await fs.writeFile(registryFile, JSON.stringify(existingData), 'utf8');

      // When: We initialize the registry
      await registry.initialize();

      // Then: It should load the device
      const devices = registry.getAll();
      expect(devices).to.have.lengthOf(1);
      expect(devices[0].id).to.equal('test:device:1');
      expect(devices[0].name).to.equal('Test Device');
    });
  });

  describe('Device Registration', function() {
    beforeEach(async function() {
      await registry.initialize();
    });

    it('Given a new device, When registered, Then it should be stored', async function() {
      // Given: A new device object
      const device = {
        id: 'homekit:AA:BB:CC:DD:EE:FF',
        name: 'Living Room Light',
        ecosystem: 'homekit',
        type: 'lightbulb',
        model: 'LIFX Mini W'
      };

      // When: We register it
      const result = await registry.register(device);

      // Then: It should be stored and retrievable
      expect(result.id).to.equal(device.id);
      expect(result.name).to.equal(device.name);

      const retrieved = registry.get(device.id);
      expect(retrieved).to.exist;
      expect(retrieved.name).to.equal('Living Room Light');
      expect(retrieved.firstSeen).to.exist;
      expect(retrieved.lastUpdated).to.exist;
    });

    it('Given an existing device, When registered again, Then it should update', async function() {
      // Given: An existing device
      const device = {
        id: 'test:device:1',
        name: 'Original Name',
        ecosystem: 'test',
        type: 'sensor'
      };
      await registry.register(device);

      // When: We register it again with updated info
      const updated = {
        id: 'test:device:1',
        name: 'Updated Name',
        location: 'Kitchen'
      };
      await registry.register(updated);

      // Then: The device should be updated
      const retrieved = registry.get('test:device:1');
      expect(retrieved.name).to.equal('Updated Name');
      expect(retrieved.location).to.equal('Kitchen');
      expect(retrieved.ecosystem).to.equal('test'); // Original fields preserved
    });

    it('Given multiple devices, When registered in batch, Then all should be stored', async function() {
      // Given: Multiple devices
      const devices = [
        { id: 'test:1', name: 'Device 1', ecosystem: 'test', type: 'sensor' },
        { id: 'test:2', name: 'Device 2', ecosystem: 'test', type: 'switch' },
        { id: 'test:3', name: 'Device 3', ecosystem: 'test', type: 'lightbulb' }
      ];

      // When: We register them in batch
      await registry.registerBatch(devices);

      // Then: All should be retrievable
      const all = registry.getAll();
      expect(all).to.have.lengthOf(3);
      expect(all.map(d => d.id)).to.include.members(['test:1', 'test:2', 'test:3']);
    });
  });

  describe('Device Retrieval', function() {
    beforeEach(async function() {
      await registry.initialize();

      // Register test devices
      await registry.registerBatch([
        { id: 'homekit:1', name: 'Light 1', ecosystem: 'homekit', type: 'lightbulb', location: 'living-room', paired: true },
        { id: 'homekit:2', name: 'Light 2', ecosystem: 'homekit', type: 'lightbulb', location: 'bedroom', paired: false },
        { id: 'lutron:1', name: 'Switch 1', ecosystem: 'lutron', type: 'switch', location: 'kitchen', paired: true },
        { id: 'lutron:2', name: 'Dimmer 1', ecosystem: 'lutron', type: 'dimmer', location: 'living-room', paired: true }
      ]);
    });

    it('Given devices exist, When getting all, Then all should be returned', async function() {
      // When: We get all devices
      const all = registry.getAll();

      // Then: We should get all 4 devices
      expect(all).to.have.lengthOf(4);
    });

    it('Given devices from multiple ecosystems, When filtering by ecosystem, Then only matching should return', async function() {
      // When: We filter by ecosystem
      const homekitDevices = registry.getAll({ ecosystem: 'homekit' });
      const lutronDevices = registry.getAll({ ecosystem: 'lutron' });

      // Then: Only matching devices should return
      expect(homekitDevices).to.have.lengthOf(2);
      expect(lutronDevices).to.have.lengthOf(2);
      expect(homekitDevices.every(d => d.ecosystem === 'homekit')).to.be.true;
    });

    it('Given devices of different types, When filtering by type, Then only matching should return', async function() {
      // When: We filter by type
      const lights = registry.getAll({ type: 'lightbulb' });
      const switches = registry.getAll({ type: 'switch' });

      // Then: Only matching types should return
      expect(lights).to.have.lengthOf(2);
      expect(switches).to.have.lengthOf(1);
    });

    it('Given paired and unpaired devices, When filtering by paired status, Then only matching should return', async function() {
      // When: We filter by paired status
      const paired = registry.getAll({ paired: true });
      const unpaired = registry.getAll({ paired: false });

      // Then: Only matching paired status should return
      expect(paired).to.have.lengthOf(3);
      expect(unpaired).to.have.lengthOf(1);
    });

    it('Given devices in different locations, When filtering by location, Then only matching should return', async function() {
      // When: We filter by location
      const livingRoom = registry.getAll({ location: 'living-room' });

      // Then: Only devices in that location should return
      expect(livingRoom).to.have.lengthOf(2);
      expect(livingRoom.every(d => d.location === 'living-room')).to.be.true;
    });
  });

  describe('Device Metadata Updates', function() {
    beforeEach(async function() {
      await registry.initialize();
      await registry.register({
        id: 'test:device:1',
        name: 'Test Device',
        ecosystem: 'test',
        type: 'sensor'
      });
    });

    it('Given a device, When updating metadata, Then changes should persist', async function() {
      // Given: An existing device
      const deviceId = 'test:device:1';

      // When: We update its metadata
      await registry.updateMetadata(deviceId, {
        location: 'kitchen',
        name: 'Kitchen Sensor'
      });

      // Then: The changes should be stored
      const device = registry.get(deviceId);
      expect(device.location).to.equal('kitchen');
      expect(device.name).to.equal('Kitchen Sensor');
      expect(device.lastUpdated).to.exist;
    });

    it('Given a device, When setting paired status, Then it should update', async function() {
      // Given: An unpaired device
      const deviceId = 'test:device:1';

      // When: We set it as paired
      await registry.setPaired(deviceId, true);

      // Then: It should be marked as paired
      const device = registry.get(deviceId);
      expect(device.paired).to.be.true;
    });

    it('Given a device, When updating last seen, Then timestamp should update', async function() {
      // Given: A device without a lastSeen timestamp
      const deviceId = 'test:device:1';
      const device = registry.get(deviceId);
      expect(device.lastSeen).to.be.undefined;

      // When: We update last seen
      await registry.updateLastSeen(deviceId);

      // Then: lastSeen should be set
      const updated = registry.get(deviceId);
      expect(updated.lastSeen).to.exist;
      expect(new Date(updated.lastSeen)).to.be.instanceOf(Date);

      // When: We update it again after a delay
      await new Promise(resolve => setTimeout(resolve, 10));
      const firstTimestamp = updated.lastSeen;
      await registry.updateLastSeen(deviceId);

      // Then: The timestamp should be newer
      const updated2 = registry.get(deviceId);
      expect(new Date(updated2.lastSeen).getTime()).to.be.at.least(new Date(firstTimestamp).getTime());
    });
  });

  describe('Statistics', function() {
    beforeEach(async function() {
      await registry.initialize();

      await registry.registerBatch([
        { id: 'homekit:1', ecosystem: 'homekit', type: 'lightbulb', location: 'living-room', paired: true },
        { id: 'homekit:2', ecosystem: 'homekit', type: 'sensor', location: 'bedroom', paired: false },
        { id: 'lutron:1', ecosystem: 'lutron', type: 'switch', location: 'kitchen', paired: true },
        { id: 'lutron:2', ecosystem: 'lutron', type: 'dimmer', location: 'living-room', paired: true }
      ]);
    });

    it('Given devices exist, When getting stats, Then accurate counts should return', async function() {
      // When: We get statistics
      const stats = registry.getStats();

      // Then: Counts should be accurate
      expect(stats.total).to.equal(4);
      expect(stats.paired).to.equal(3);
      expect(stats.unpaired).to.equal(1);
      expect(stats.byEcosystem.homekit).to.equal(2);
      expect(stats.byEcosystem.lutron).to.equal(2);
      expect(stats.byType.lightbulb).to.equal(1);
      expect(stats.byLocation['living-room']).to.equal(2);
    });
  });

  describe('Persistence', function() {
    it('Given devices in registry, When saved, Then they should persist across instances', async function() {
      // Given: A registry with devices
      await registry.initialize();
      await registry.register({
        id: 'test:device:1',
        name: 'Persistent Device',
        ecosystem: 'test',
        type: 'sensor'
      });

      // When: We create a new registry instance pointing to same directory
      const newRegistry = new DeviceRegistry({
        stateDir: testStateDir
      });
      await newRegistry.initialize();

      // Then: The device should be loaded
      const device = newRegistry.get('test:device:1');
      expect(device).to.exist;
      expect(device.name).to.equal('Persistent Device');
    });
  });

  describe('Device Removal', function() {
    beforeEach(async function() {
      await registry.initialize();
      await registry.register({
        id: 'test:device:1',
        name: 'Device to Remove',
        ecosystem: 'test',
        type: 'sensor'
      });
    });

    it('Given a device exists, When removed, Then it should no longer be retrievable', async function() {
      // Given: An existing device
      expect(registry.get('test:device:1')).to.exist;

      // When: We remove it
      const removed = await registry.remove('test:device:1');

      // Then: It should be gone
      expect(removed).to.be.true;
      expect(registry.get('test:device:1')).to.be.undefined;
      expect(registry.getAll()).to.be.empty;
    });
  });
});
