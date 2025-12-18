import express from 'express';
import { apiVersioning } from '../middleware/apiVersioning.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import AppConfig from '../models/AppConfig.js';
import redisService from '../services/redisService.js';

const router = express.Router();

/**
 * GET /api/app-config
 * 
 * Fetches the active app configuration for the requesting platform.
 * This endpoint is heavily cached and optimized for high traffic.
 * 
 * Query Parameters:
 * - platform: 'android' | 'ios' | 'web' (default: 'android')
 * - environment: 'development' | 'staging' | 'production' (default: 'production')
 * 
 * Headers:
 * - X-API-Version: API version (e.g., '2024-10-01')
 * 
 * Response includes:
 * - versionControl: Forced update settings
 * - featureFlags: Feature toggles
 * - businessRules: Pricing, limits, thresholds
 * - recommendationParams: Algorithm parameters
 * - uiTexts: All UI text strings
 * - killSwitch: Emergency shutdown settings
 */
router.get(
  '/',
  apiVersioning, // Apply API versioning
  asyncHandler(async (req, res) => {
    const platform = req.query.platform || 'android';
    const environment = req.query.environment || process.env.NODE_ENV || 'production';
    
    // Cache key for this request
    const cacheKey = `app_config:${platform}:${environment}`;
    
    // Try to get from Redis cache first
    if (redisService.getConnectionStatus()) {
      try {
        const cached = await redisService.get(cacheKey);
        if (cached) {
          console.log(`✅ AppConfig: Cache hit for ${platform}/${environment}`);
          
          // Set cache headers
          res.setHeader('X-Cache', 'HIT');
          res.setHeader('Cache-Control', 'public, max-age=300, stale-while-revalidate=600');
          
          return res.json({
            success: true,
            platform: platform,
            environment: environment,
            apiVersion: req.apiVersion,
            config: JSON.parse(cached),
            cached: true,
            timestamp: new Date().toISOString()
          });
        }
      } catch (cacheError) {
        console.warn('⚠️ AppConfig: Cache read error:', cacheError.message);
      }
    }
    
    // Fetch from database
    console.log(`🔍 AppConfig: Fetching config for ${platform}/${environment}`);
    const config = await AppConfig.getActiveConfig(platform, environment);
    
    if (!config) {
      // Try to get latest config regardless of platform
      const fallbackConfig = await AppConfig.getLatestConfig(environment);
      
      if (!fallbackConfig) {
        return res.status(404).json({
          success: false,
          error: 'Configuration Not Found',
          message: `No active configuration found for platform: ${platform}, environment: ${environment}`,
          hint: 'Please ensure an AppConfig document exists in the database.'
        });
      }
      
      console.log(`⚠️ AppConfig: Using fallback config for ${platform}`);
      
      // Cache the fallback config
      if (redisService.getConnectionStatus()) {
        try {
          await redisService.setex(
            cacheKey,
            300, // 5 minutes TTL
            JSON.stringify(fallbackConfig.toObject())
          );
        } catch (cacheError) {
          console.warn('⚠️ AppConfig: Cache write error:', cacheError.message);
        }
      }
      
      // Set cache headers
      res.setHeader('X-Cache', 'MISS');
      res.setHeader('Cache-Control', 'public, max-age=300, stale-while-revalidate=600');
      
      return res.json({
        success: true,
        platform: platform,
        environment: environment,
        apiVersion: req.apiVersion,
        config: fallbackConfig.toObject(),
        cached: false,
        fallback: true,
        timestamp: new Date().toISOString()
      });
    }
    
    // Cache the config
    if (redisService.getConnectionStatus()) {
      try {
        await redisService.setex(
          cacheKey,
          300, // 5 minutes TTL
          JSON.stringify(config.toObject())
        );
      } catch (cacheError) {
        console.warn('⚠️ AppConfig: Cache write error:', cacheError.message);
      }
    }
    
    // Set cache headers
    res.setHeader('X-Cache', 'MISS');
    res.setHeader('Cache-Control', 'public, max-age=300, stale-while-revalidate=600');
    
    // Return config
    res.json({
      success: true,
      platform: platform,
      environment: environment,
      apiVersion: req.apiVersion,
      config: config.toObject(),
      cached: false,
      timestamp: new Date().toISOString()
    });
  })
);

/**
 * GET /api/app-config/version-check
 * 
 * Checks if the app version is supported and returns update information.
 * This is a lightweight endpoint for version validation.
 * 
 * Query Parameters:
 * - appVersion: Current app version (e.g., '1.2.3')
 * - platform: 'android' | 'ios' | 'web' (default: 'android')
 * 
 * Response:
 * - isSupported: Whether app version meets minimum requirement
 * - isLatest: Whether app version is the latest
 * - updateRequired: Whether forced update is required
 * - updateRecommended: Whether soft update is recommended
 * - updateMessages: Messages for forced/soft updates
 */
router.get(
  '/version-check',
  apiVersioning,
  asyncHandler(async (req, res) => {
    const appVersion = req.query.appVersion;
    const platform = req.query.platform || 'android';
    const environment = req.query.environment || process.env.NODE_ENV || 'production';
    
    if (!appVersion) {
      return res.status(400).json({
        success: false,
        error: 'Missing App Version',
        message: 'appVersion query parameter is required'
      });
    }
    
    // Get config
    const config = await AppConfig.getActiveConfig(platform, environment);
    
    if (!config) {
      return res.status(404).json({
        success: false,
        error: 'Configuration Not Found'
      });
    }
    
    // Check version support
    const isSupported = config.isAppVersionSupported(appVersion);
    const isLatest = config.isAppVersionLatest(appVersion);
    const updateRequired = !isSupported;
    const updateRecommended = !isLatest && isSupported;
    
    // Prepare response
    const response = {
      success: true,
      appVersion: appVersion,
      platform: platform,
      isSupported: isSupported,
      isLatest: isLatest,
      updateRequired: updateRequired,
      updateRecommended: updateRecommended,
      versionControl: {
        minSupportedVersion: config.versionControl.minSupportedAppVersion,
        latestVersion: config.versionControl.latestAppVersion
      }
    };
    
    // Add update messages if needed
    if (updateRequired) {
      response.updateMessage = config.versionControl.forceUpdateMessage;
      response.updateUrl = config.versionControl.updateUrl[platform] || 
                          config.versionControl.updateUrl.android;
    } else if (updateRecommended) {
      response.updateMessage = config.versionControl.softUpdateMessage;
      response.updateUrl = config.versionControl.updateUrl[platform] || 
                          config.versionControl.updateUrl.android;
    }
    
    res.json(response);
  })
);

/**
 * GET /api/app-config/texts
 * 
 * Fetches only UI texts (for lightweight text updates).
 * This endpoint is optimized for frequent polling.
 * 
 * Query Parameters:
 * - platform: 'android' | 'ios' | 'web' (default: 'android')
 * - keys: Comma-separated list of text keys to fetch (optional, returns all if not specified)
 */
router.get(
  '/texts',
  apiVersioning,
  asyncHandler(async (req, res) => {
    const platform = req.query.platform || 'android';
    const environment = req.query.environment || process.env.NODE_ENV || 'production';
    const requestedKeys = req.query.keys ? req.query.keys.split(',') : null;
    
    // Get config
    const config = await AppConfig.getActiveConfig(platform, environment);
    
    if (!config) {
      return res.status(404).json({
        success: false,
        error: 'Configuration Not Found'
      });
    }
    
    // Get texts
    const allTexts = config.uiTexts || new Map();
    const texts = {};
    
    if (requestedKeys) {
      // Return only requested keys
      requestedKeys.forEach(key => {
        const trimmedKey = key.trim();
        if (allTexts.has(trimmedKey)) {
          texts[trimmedKey] = allTexts.get(trimmedKey);
        }
      });
    } else {
      // Return all texts
      allTexts.forEach((value, key) => {
        texts[key] = value;
      });
    }
    
    res.setHeader('Cache-Control', 'public, max-age=300, stale-while-revalidate=600');
    
    res.json({
      success: true,
      platform: platform,
      texts: texts,
      timestamp: new Date().toISOString()
    });
  })
);

/**
 * GET /api/app-config/kill-switch
 * 
 * Checks kill switch status (for emergency shutdown).
 * This is a very lightweight endpoint for frequent polling.
 */
router.get(
  '/kill-switch',
  apiVersioning,
  asyncHandler(async (req, res) => {
    const platform = req.query.platform || 'android';
    const environment = req.query.environment || process.env.NODE_ENV || 'production';
    
    // Cache key
    const cacheKey = `kill_switch:${platform}:${environment}`;
    
    // Try cache first
    if (redisService.getConnectionStatus()) {
      try {
        const cached = await redisService.get(cacheKey);
        if (cached) {
          res.setHeader('X-Cache', 'HIT');
          res.setHeader('Cache-Control', 'public, max-age=60'); // 1 minute for kill switch
          return res.json(JSON.parse(cached));
        }
      } catch (cacheError) {
        console.warn('⚠️ KillSwitch: Cache read error:', cacheError.message);
      }
    }
    
    // Get config
    const config = await AppConfig.getActiveConfig(platform, environment);
    
    if (!config) {
      return res.json({
        success: true,
        killSwitchEnabled: false,
        maintenanceMode: false
      });
    }
    
    const response = {
      success: true,
      killSwitchEnabled: config.killSwitch.enabled || false,
      maintenanceMode: config.killSwitch.maintenanceMode || false,
      message: config.killSwitch.enabled ? config.killSwitch.message : null,
      maintenanceMessage: config.killSwitch.maintenanceMode ? config.killSwitch.maintenanceMessage : null,
      timestamp: new Date().toISOString()
    };
    
    // Cache response
    if (redisService.getConnectionStatus()) {
      try {
        await redisService.setex(cacheKey, 60, JSON.stringify(response)); // 1 minute TTL
      } catch (cacheError) {
        console.warn('⚠️ KillSwitch: Cache write error:', cacheError.message);
      }
    }
    
    res.setHeader('X-Cache', 'MISS');
    res.setHeader('Cache-Control', 'public, max-age=60');
    
    res.json(response);
  })
);

export default router;

