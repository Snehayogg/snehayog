import User from '../models/User.js';

/**
 * Middleware to track app versions from request headers
 * Handles both the new X-App-Version and the legacy X-API-Version with mapping
 */
export const versionTracking = async (req, res, next) => {
  try {
    // 1. Check if user is authenticated (populated by verifyToken or passiveVerifyToken)
    if (!req.user || !req.user.id) {
      return next();
    }

    // 2. Extract versions from headers
    const appVersionRaw = req.headers['x-app-version'];
    const apiVersionDate = req.headers['x-api-version'];

    if (!appVersionRaw && !apiVersionDate) {
      return next();
    }

    // 3. Mapping logic for legacy versions (Best Effort)
    const versionMap = {
      '2026-04-02': '2.5.8+47',
      // Add more historic mappings here if needed
    };

    // 4. Determine final version string
    // Priority: Real version header > Mapped date header > Literal date header
    let finalVersion = appVersionRaw || versionMap[apiVersionDate] || apiVersionDate;

    // 5. Update database if version has changed
    // We do this asynchronously to not block the request
    if (finalVersion && req.user.appVersion !== finalVersion) {
      // Use setImmediate to run this outside the current request cycle
      setImmediate(async () => {
        try {
          // **FIX: Use req.user._id (ObjectId) instead of req.user.id (Google ID string)**
          await User.findByIdAndUpdate(req.user._id, { 
            appVersion: finalVersion,
            lastActive: new Date() // Also update activity timestamp
          });
        } catch (err) {
          // Log error but don't crash requested operation
          console.error('⚠️ VersionTracking Error:', err.message);
        }
      });
    }

    next();
  } catch (error) {
    // Silent fail for version tracking to avoid breaking real requests
    console.error('⚠️ VersionTracking Middleware Error:', error.message);
    next();
  }
};
