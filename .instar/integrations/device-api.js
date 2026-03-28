/**
 * Device API Service
 * REST API endpoints for device discovery, control, and management
 * Designed to integrate with Instar server's externalOperations
 */

const HomeKitAdapter = require('./homekit-adapter');
const DeviceRegistry = require('./device-registry');

class DeviceAPI {
  constructor() {
    this.adapter = new HomeKitAdapter();
    this.registry = new DeviceRegistry();
    this.initialized = false;
  }

  /**
   * Initialize the API (load state)
   */
  async initialize() {
    if (this.initialized) return;

    await this.adapter.initialize();
    await this.registry.initialize();

    this.initialized = true;
    console.log('Device API initialized');
  }

  /**
   * Register routes with an Express app or router
   * @param {Express.Router} router - Express router instance
   */
  registerRoutes(router) {
    // Device discovery
    router.get('/devices/discover', async (req, res) => {
      try {
        await this.initialize();

        const duration = parseInt(req.query.duration) || 10000;
        const devices = await this.adapter.discover(duration);

        // Register discovered devices
        await this.registry.registerBatch(devices);

        res.json({
          success: true,
          count: devices.length,
          devices
        });
      } catch (err) {
        res.status(500).json({
          success: false,
          error: err.message
        });
      }
    });

    // List all devices
    router.get('/devices', async (req, res) => {
      try {
        await this.initialize();

        const filters = {};
        if (req.query.ecosystem) filters.ecosystem = req.query.ecosystem;
        if (req.query.type) filters.type = req.query.type;
        if (req.query.location) filters.location = req.query.location;
        if (req.query.paired !== undefined) {
          filters.paired = req.query.paired === 'true';
        }

        const devices = this.registry.getAll(filters);

        res.json({
          success: true,
          count: devices.length,
          devices
        });
      } catch (err) {
        res.status(500).json({
          success: false,
          error: err.message
        });
      }
    });

    // Get device by ID
    router.get('/devices/:deviceId', async (req, res) => {
      try {
        await this.initialize();

        const device = this.registry.get(req.params.deviceId);

        if (!device) {
          return res.status(404).json({
            success: false,
            error: 'Device not found'
          });
        }

        res.json({
          success: true,
          device
        });
      } catch (err) {
        res.status(500).json({
          success: false,
          error: err.message
        });
      }
    });

    // Update device metadata
    router.patch('/devices/:deviceId', async (req, res) => {
      try {
        await this.initialize();

        const updated = await this.registry.updateMetadata(
          req.params.deviceId,
          req.body
        );

        res.json({
          success: true,
          device: updated
        });
      } catch (err) {
        res.status(404).json({
          success: false,
          error: err.message
        });
      }
    });

    // Pair with a device
    router.post('/devices/:deviceId/pair', async (req, res) => {
      try {
        await this.initialize();

        const { pin } = req.body;

        if (!pin) {
          return res.status(400).json({
            success: false,
            error: 'PIN required'
          });
        }

        await this.adapter.pair(req.params.deviceId, pin);
        await this.registry.setPaired(req.params.deviceId, true);

        res.json({
          success: true,
          message: 'Device paired successfully'
        });
      } catch (err) {
        res.status(400).json({
          success: false,
          error: err.message
        });
      }
    });

    // Get device capabilities
    router.get('/devices/:deviceId/capabilities', async (req, res) => {
      try {
        await this.initialize();

        const capabilities = await this.adapter.getCapabilities(req.params.deviceId);

        res.json({
          success: true,
          capabilities
        });
      } catch (err) {
        res.status(400).json({
          success: false,
          error: err.message
        });
      }
    });

    // Get device state
    router.get('/devices/:deviceId/state', async (req, res) => {
      try {
        await this.initialize();

        const characteristics = req.query.chars
          ? req.query.chars.split(',')
          : null;

        const state = await this.adapter.getState(
          req.params.deviceId,
          characteristics
        );

        res.json({
          success: true,
          state
        });
      } catch (err) {
        res.status(400).json({
          success: false,
          error: err.message
        });
      }
    });

    // Control device (set state)
    router.post('/devices/:deviceId/control', async (req, res) => {
      try {
        await this.initialize();

        const { characteristics } = req.body;

        if (!characteristics || typeof characteristics !== 'object') {
          return res.status(400).json({
            success: false,
            error: 'characteristics object required'
          });
        }

        await this.adapter.setState(req.params.deviceId, characteristics);

        res.json({
          success: true,
          message: 'Device state updated'
        });
      } catch (err) {
        res.status(400).json({
          success: false,
          error: err.message
        });
      }
    });

    // Subscribe to device events
    router.post('/devices/:deviceId/subscribe', async (req, res) => {
      try {
        await this.initialize();

        const { characteristics } = req.body;

        if (!Array.isArray(characteristics)) {
          return res.status(400).json({
            success: false,
            error: 'characteristics array required'
          });
        }

        // Note: Real-time subscription would need WebSocket support
        // For now, just acknowledge the request
        await this.adapter.subscribe(
          req.params.deviceId,
          characteristics,
          (event) => {
            console.log(`Event from ${req.params.deviceId}:`, event);
          }
        );

        res.json({
          success: true,
          message: 'Subscribed to device events (check server logs)'
        });
      } catch (err) {
        res.status(400).json({
          success: false,
          error: err.message
        });
      }
    });

    // Registry statistics
    router.get('/devices/stats/summary', async (req, res) => {
      try {
        await this.initialize();

        const stats = this.registry.getStats();

        res.json({
          success: true,
          stats
        });
      } catch (err) {
        res.status(500).json({
          success: false,
          error: err.message
        });
      }
    });

    // Get stale devices
    router.get('/devices/stats/stale', async (req, res) => {
      try {
        await this.initialize();

        const hours = parseInt(req.query.hours) || 24;
        const stale = this.registry.getStaleDevices(hours);

        res.json({
          success: true,
          count: stale.length,
          devices: stale
        });
      } catch (err) {
        res.status(500).json({
          success: false,
          error: err.message
        });
      }
    });

    // Export registry
    router.get('/devices/export', async (req, res) => {
      try {
        await this.initialize();

        const data = await this.registry.export();

        res.json({
          success: true,
          data
        });
      } catch (err) {
        res.status(500).json({
          success: false,
          error: err.message
        });
      }
    });

    console.log('Device API routes registered');
  }

  /**
   * Cleanup - called on server shutdown
   */
  async cleanup() {
    if (this.adapter) {
      await this.adapter.cleanup();
    }
  }
}

module.exports = DeviceAPI;
