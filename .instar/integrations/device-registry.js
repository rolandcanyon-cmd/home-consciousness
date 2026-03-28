/**
 * Device Registry
 * Centralized registry for all house devices across all ecosystems
 */

const fs = require('fs').promises;
const path = require('path');

class DeviceRegistry {
  constructor(options = {}) {
    this.stateDir = options.stateDir || path.join(__dirname, '../state/devices');
    this.registryFile = path.join(this.stateDir, 'registry.json');
    this.devices = new Map();
  }

  /**
   * Initialize the registry - load from disk
   */
  async initialize() {
    await fs.mkdir(this.stateDir, { recursive: true });

    try {
      const data = await fs.readFile(this.registryFile, 'utf8');
      const registry = JSON.parse(data);

      for (const [id, device] of Object.entries(registry.devices || {})) {
        this.devices.set(id, device);
      }

      console.log(`Loaded ${this.devices.size} device(s) from registry`);
    } catch (err) {
      if (err.code === 'ENOENT') {
        // Registry doesn't exist yet, start fresh
        await this._save();
      } else {
        console.error('Error loading registry:', err.message);
      }
    }
  }

  /**
   * Register or update a device
   * @param {Object} device - Device information
   */
  async register(device) {
    if (!device.id) {
      throw new Error('Device must have an id');
    }

    const existing = this.devices.get(device.id);

    const updated = {
      ...existing,
      ...device,
      lastUpdated: new Date().toISOString(),
      firstSeen: existing?.firstSeen || new Date().toISOString()
    };

    this.devices.set(device.id, updated);
    await this._save();

    return updated;
  }

  /**
   * Register multiple devices at once
   */
  async registerBatch(devices) {
    const results = [];
    for (const device of devices) {
      results.push(await this.register(device));
    }
    return results;
  }

  /**
   * Get a device by ID
   */
  get(deviceId) {
    return this.devices.get(deviceId);
  }

  /**
   * Get all devices
   * @param {Object} filters - Optional filters (ecosystem, type, location, etc.)
   */
  getAll(filters = {}) {
    let devices = Array.from(this.devices.values());

    if (filters.ecosystem) {
      devices = devices.filter(d => d.ecosystem === filters.ecosystem);
    }

    if (filters.type) {
      devices = devices.filter(d => d.type === filters.type);
    }

    if (filters.location) {
      devices = devices.filter(d => d.location === filters.location);
    }

    if (filters.paired !== undefined) {
      devices = devices.filter(d => d.paired === filters.paired);
    }

    return devices;
  }

  /**
   * Update device metadata (location, name, custom fields)
   */
  async updateMetadata(deviceId, metadata) {
    const device = this.devices.get(deviceId);
    if (!device) {
      throw new Error(`Device ${deviceId} not found`);
    }

    const updated = {
      ...device,
      ...metadata,
      lastUpdated: new Date().toISOString()
    };

    this.devices.set(deviceId, updated);
    await this._save();

    return updated;
  }

  /**
   * Mark device as paired
   */
  async setPaired(deviceId, paired = true) {
    const device = this.devices.get(deviceId);
    if (!device) {
      throw new Error(`Device ${deviceId} not found`);
    }

    device.paired = paired;
    device.lastUpdated = new Date().toISOString();

    this.devices.set(deviceId, device);
    await this._save();

    return device;
  }

  /**
   * Update last seen timestamp
   */
  async updateLastSeen(deviceId) {
    const device = this.devices.get(deviceId);
    if (!device) return;

    device.lastSeen = new Date().toISOString();
    this.devices.set(deviceId, device);
    await this._save();
  }

  /**
   * Remove a device from registry
   */
  async remove(deviceId) {
    const existed = this.devices.delete(deviceId);
    if (existed) {
      await this._save();
    }
    return existed;
  }

  /**
   * Get registry statistics
   */
  getStats() {
    const devices = Array.from(this.devices.values());

    const byEcosystem = {};
    const byType = {};
    const byLocation = {};

    for (const device of devices) {
      // Count by ecosystem
      byEcosystem[device.ecosystem] = (byEcosystem[device.ecosystem] || 0) + 1;

      // Count by type
      byType[device.type] = (byType[device.type] || 0) + 1;

      // Count by location
      const loc = device.location || 'unknown';
      byLocation[loc] = (byLocation[loc] || 0) + 1;
    }

    return {
      total: devices.length,
      paired: devices.filter(d => d.paired).length,
      unpaired: devices.filter(d => !d.paired).length,
      byEcosystem,
      byType,
      byLocation
    };
  }

  /**
   * Find devices that haven't been seen recently
   * @param {number} hours - Consider offline if not seen in this many hours
   */
  getStaleDevices(hours = 24) {
    const cutoff = new Date(Date.now() - hours * 60 * 60 * 1000);
    return Array.from(this.devices.values()).filter(device => {
      return new Date(device.lastSeen) < cutoff;
    });
  }

  /**
   * Save registry to disk
   */
  async _save() {
    const registry = {
      version: '1.0',
      lastUpdated: new Date().toISOString(),
      devices: Object.fromEntries(this.devices)
    };

    await fs.writeFile(
      this.registryFile,
      JSON.stringify(registry, null, 2),
      'utf8'
    );
  }

  /**
   * Export registry for backup/inspection
   */
  async export() {
    return {
      version: '1.0',
      exportedAt: new Date().toISOString(),
      devices: Array.from(this.devices.values()),
      stats: this.getStats()
    };
  }
}

module.exports = DeviceRegistry;
