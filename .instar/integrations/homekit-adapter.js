/**
 * HomeKit Adapter
 * Provides a unified interface to discover, pair, and control HomeKit devices
 */

const { IPDiscovery, HttpClient } = require('hap-controller');
const fs = require('fs').promises;
const path = require('path');

class HomeKitAdapter {
  constructor(options = {}) {
    this.stateDir = options.stateDir || path.join(__dirname, '../state/devices');
    this.pairingFile = path.join(this.stateDir, 'pairing', 'homekit-pairing.json');
    this.registryFile = path.join(this.stateDir, 'registry.json');

    this.discovery = null;
    this.devices = new Map();
    this.clients = new Map();
    this.pairingData = new Map();
    this.eventHandlers = new Map();
  }

  /**
   * Initialize the adapter - load existing pairings
   */
  async initialize() {
    // Ensure directories exist
    await fs.mkdir(path.join(this.stateDir, 'pairing'), { recursive: true });

    // Load existing pairings
    try {
      const data = await fs.readFile(this.pairingFile, 'utf8');
      const pairings = JSON.parse(data);

      for (const [deviceId, pairing] of Object.entries(pairings)) {
        this.pairingData.set(deviceId, pairing);
      }

      console.log(`Loaded ${this.pairingData.size} HomeKit pairing(s)`);
    } catch (err) {
      if (err.code !== 'ENOENT') {
        console.error('Error loading pairings:', err.message);
      }
    }
  }

  /**
   * Discover HomeKit devices on the network
   * @param {number} duration - How long to scan in milliseconds (default 10s)
   * @returns {Promise<Array>} - List of discovered devices
   */
  async discover(duration = 10000) {
    return new Promise((resolve, reject) => {
      const discovered = new Map();

      this.discovery = new IPDiscovery();

      this.discovery.on('serviceUp', (service) => {
        const device = {
          id: `homekit:${service.id}`,
          ecosystem: 'homekit',
          nativeId: service.id,
          name: service.name || 'Unknown',
          type: this._getCategoryName(service.ci),
          model: service.md || 'Unknown',
          address: service.address,
          port: service.port,
          category: service.ci,
          paired: this.pairingData.has(service.id),
          lastSeen: new Date().toISOString(),
          metadata: {
            statusFlags: service.sf,
            configNumber: service.c,
            protocolVersion: service.pv
          }
        };

        discovered.set(device.id, device);
        this.devices.set(device.id, service);
      });

      this.discovery.start();

      setTimeout(() => {
        this.discovery.stop();
        resolve(Array.from(discovered.values()));
      }, duration);

      this.discovery.on('error', (err) => {
        console.error('Discovery error:', err);
        reject(err);
      });
    });
  }

  /**
   * Pair with a HomeKit device
   * @param {string} deviceId - Device ID (homekit:XX:XX:XX:XX:XX:XX)
   * @param {string} pin - 8-digit PIN code (format: XXX-XX-XXX)
   */
  async pair(deviceId, pin) {
    const service = this.devices.get(deviceId);
    if (!service) {
      throw new Error(`Device ${deviceId} not found. Run discover() first.`);
    }

    // Remove dashes from PIN
    const cleanPin = pin.replace(/-/g, '');

    const client = new HttpClient(
      service.id,
      service.address,
      service.port
    );

    try {
      await client.pairSetup(cleanPin);
      const longTermData = client.getLongTermData();

      // Store pairing data
      this.pairingData.set(service.id, longTermData);
      await this._savePairings();

      // Store client for later use
      this.clients.set(deviceId, client);

      console.log(`✅ Successfully paired with ${service.name}`);
      return { success: true, deviceId };
    } catch (err) {
      console.error(`Failed to pair with ${service.name}:`, err.message);
      throw new Error(`Pairing failed: ${err.message}`);
    }
  }

  /**
   * Get or create an authenticated client for a device
   */
  _getClient(deviceId) {
    // Check if we already have a client
    if (this.clients.has(deviceId)) {
      return this.clients.get(deviceId);
    }

    // Get device info and pairing data
    const service = this.devices.get(deviceId);
    const pairing = this.pairingData.get(service?.id);

    if (!service || !pairing) {
      throw new Error(`Device ${deviceId} not paired. Run pair() first.`);
    }

    // Create authenticated client
    const client = new HttpClient(
      service.id,
      service.address,
      service.port,
      pairing
    );

    this.clients.set(deviceId, client);
    return client;
  }

  /**
   * Get device capabilities (accessories and characteristics)
   * @param {string} deviceId
   */
  async getCapabilities(deviceId) {
    const client = this._getClient(deviceId);

    try {
      const accessories = await client.getAccessories();
      return this._parseAccessories(accessories);
    } catch (err) {
      throw new Error(`Failed to get capabilities: ${err.message}`);
    }
  }

  /**
   * Get current state of a device
   * @param {string} deviceId
   * @param {Array<string>} characteristics - Optional: specific characteristics to read (e.g., ['1.10'])
   */
  async getState(deviceId, characteristics = null) {
    const client = this._getClient(deviceId);

    try {
      // If no specific characteristics, get all accessories first
      if (!characteristics) {
        const accessories = await client.getAccessories();
        characteristics = this._extractAllCharacteristics(accessories);
      }

      const state = await client.getCharacteristics(characteristics, {
        meta: true,
        perms: true,
        type: true,
        ev: true
      });

      return this._parseCharacteristics(state);
    } catch (err) {
      throw new Error(`Failed to get state: ${err.message}`);
    }
  }

  /**
   * Set device state (control the device)
   * @param {string} deviceId
   * @param {Object} values - Characteristic values to set (e.g., {'1.10': true})
   */
  async setState(deviceId, values) {
    const client = this._getClient(deviceId);

    try {
      await client.setCharacteristics(values);
      return { success: true };
    } catch (err) {
      throw new Error(`Failed to set state: ${err.message}`);
    }
  }

  /**
   * Subscribe to real-time updates from a device
   * @param {string} deviceId
   * @param {Array<string>} characteristics - Which characteristics to monitor
   * @param {Function} callback - Called when updates arrive
   */
  async subscribe(deviceId, characteristics, callback) {
    const client = this._getClient(deviceId);

    try {
      // Set up event listener
      client.on('event', (event) => {
        callback(this._parseCharacteristics(event.characteristics));
      });

      // Subscribe to characteristics
      await client.subscribeCharacteristics(characteristics);

      // Store handler for cleanup
      this.eventHandlers.set(deviceId, { characteristics, callback });

      return { success: true };
    } catch (err) {
      throw new Error(`Failed to subscribe: ${err.message}`);
    }
  }

  /**
   * Unsubscribe from device updates
   */
  async unsubscribe(deviceId) {
    const handler = this.eventHandlers.get(deviceId);
    if (!handler) return;

    const client = this._getClient(deviceId);
    await client.unsubscribeCharacteristics(handler.characteristics);

    client.removeAllListeners('event');
    this.eventHandlers.delete(deviceId);
  }

  /**
   * Save pairing data to disk
   */
  async _savePairings() {
    const pairings = Object.fromEntries(this.pairingData);
    await fs.writeFile(
      this.pairingFile,
      JSON.stringify(pairings, null, 2),
      'utf8'
    );
  }

  /**
   * Parse accessories into a readable format
   */
  _parseAccessories(accessories) {
    return accessories.accessories.map(acc => ({
      aid: acc.aid,
      services: acc.services.map(svc => ({
        iid: svc.iid,
        type: svc.type,
        characteristics: svc.characteristics.map(char => ({
          iid: char.iid,
          type: char.type,
          description: char.description,
          format: char.format,
          perms: char.perms,
          value: char.value,
          characteristicId: `${acc.aid}.${char.iid}`
        }))
      }))
    }));
  }

  /**
   * Extract all characteristic IDs from accessories
   */
  _extractAllCharacteristics(accessories) {
    const chars = [];
    for (const acc of accessories.accessories) {
      for (const svc of acc.services) {
        for (const char of svc.characteristics) {
          if (char.perms.includes('pr')) { // Paired Read permission
            chars.push(`${acc.aid}.${char.iid}`);
          }
        }
      }
    }
    return chars;
  }

  /**
   * Parse characteristics into a readable format
   */
  _parseCharacteristics(characteristics) {
    const result = {};
    for (const [id, data] of Object.entries(characteristics)) {
      result[id] = {
        value: data.value,
        type: data.type,
        format: data.format,
        perms: data.perms
      };
    }
    return result;
  }

  /**
   * Get category name from category ID
   */
  _getCategoryName(categoryId) {
    const categories = {
      1: 'other', 2: 'bridge', 3: 'fan', 4: 'garage-door',
      5: 'lightbulb', 6: 'lock', 7: 'outlet', 8: 'switch',
      9: 'thermostat', 10: 'sensor', 11: 'security-system',
      12: 'door', 13: 'window', 14: 'window-covering',
      15: 'programmable-switch', 16: 'range-extender',
      17: 'camera', 18: 'video-doorbell', 19: 'air-purifier',
      20: 'heater', 21: 'air-conditioner', 22: 'humidifier',
      23: 'dehumidifier', 28: 'sprinkler', 29: 'faucet',
      30: 'shower', 31: 'television', 32: 'target-controller'
    };
    return categories[categoryId] || 'unknown';
  }

  /**
   * Cleanup - stop discovery, close connections
   */
  async cleanup() {
    if (this.discovery) {
      this.discovery.stop();
    }

    // Unsubscribe from all events
    for (const deviceId of this.eventHandlers.keys()) {
      await this.unsubscribe(deviceId);
    }

    this.clients.clear();
  }
}

module.exports = HomeKitAdapter;
