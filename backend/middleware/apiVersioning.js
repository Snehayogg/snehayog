/**
 * Date-Based API Versioning Middleware
 * 
 * This middleware implements date-based API versioning (e.g., 2024-01-01, 2024-10-01)
 * instead of semantic versioning. Versions are passed via HTTP header.
 * 
 * Features:
 * - Multiple active API versions simultaneously
 * - Stable contract per version
 * - Deprecation strategy for old versions
 * - Automatic version detection and routing
 */

/**
 * Supported API versions with their release dates and deprecation status
 * Format: 'YYYY-MM-DD'
 */
const SUPPORTED_VERSIONS = {
  '2024-01-01': {
    releaseDate: new Date('2024-01-01'),
    deprecated: false,
    deprecatedDate: null,
    endOfLifeDate: null,
    description: 'Initial API version'
  },
  '2024-10-01': {
    releaseDate: new Date('2024-10-01'),
    deprecated: false,
    deprecatedDate: null,
    endOfLifeDate: null,
    description: 'Backend-driven config support'
  }
};

/**
 * Default API version if none specified
 */
const DEFAULT_VERSION = '2024-10-01';

/**
 * Header name for API version
 */
const API_VERSION_HEADER = 'X-API-Version';

/**
 * Get the API version from request headers
 * @param {Object} req - Express request object
 * @returns {string} API version string (YYYY-MM-DD format)
 */
function getApiVersionFromRequest(req) {
  // Check for version in header
  const versionHeader = req.headers[API_VERSION_HEADER.toLowerCase()] || 
                        req.headers['x-api-version'] ||
                        req.headers['api-version'];
  
  if (versionHeader) {
    // Validate format (YYYY-MM-DD)
    const versionRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (versionRegex.test(versionHeader)) {
      return versionHeader;
    }
  }
  
  // Fallback to default version
  return DEFAULT_VERSION;
}

/**
 * Check if a version is supported
 * @param {string} version - API version string
 * @returns {boolean} True if version is supported
 */
function isVersionSupported(version) {
  return SUPPORTED_VERSIONS.hasOwnProperty(version);
}

/**
 * Check if a version is deprecated
 * @param {string} version - API version string
 * @returns {boolean} True if version is deprecated
 */
function isVersionDeprecated(version) {
  const versionInfo = SUPPORTED_VERSIONS[version];
  if (!versionInfo) return false;
  return versionInfo.deprecated === true;
}

/**
 * Get the latest API version
 * @returns {string} Latest API version
 */
function getLatestVersion() {
  const versions = Object.keys(SUPPORTED_VERSIONS)
    .sort()
    .reverse();
  return versions[0] || DEFAULT_VERSION;
}

/**
 * API Versioning Middleware
 * 
 * This middleware:
 * 1. Extracts API version from request headers
 * 2. Validates the version
 * 3. Attaches version info to request object
 * 4. Adds deprecation warnings if applicable
 * 5. Handles unsupported versions gracefully
 */
export const apiVersioning = (req, res, next) => {
  const requestedVersion = getApiVersionFromRequest(req);
  
  // Attach version info to request object
  req.apiVersion = requestedVersion;
  req.apiVersionInfo = SUPPORTED_VERSIONS[requestedVersion] || null;
  
  // Check if version is supported
  if (!isVersionSupported(requestedVersion)) {
    const latestVersion = getLatestVersion();
    
    return res.status(400).json({
      error: 'Unsupported API Version',
      message: `API version "${requestedVersion}" is not supported.`,
      supportedVersions: Object.keys(SUPPORTED_VERSIONS),
      latestVersion: latestVersion,
      requestedVersion: requestedVersion,
      hint: `Use ${API_VERSION_HEADER} header with one of the supported versions.`
    });
  }
  
  // Check if version is deprecated
  if (isVersionDeprecated(requestedVersion)) {
    const latestVersion = getLatestVersion();
    const versionInfo = SUPPORTED_VERSIONS[requestedVersion];
    
    // Add deprecation warning header
    res.setHeader('X-API-Version-Deprecated', 'true');
    res.setHeader('X-API-Version-Latest', latestVersion);
    
    if (versionInfo.endOfLifeDate) {
      const eolDate = new Date(versionInfo.endOfLifeDate);
      const daysUntilEol = Math.ceil((eolDate - new Date()) / (1000 * 60 * 60 * 24));
      
      res.setHeader('X-API-Version-End-Of-Life', eolDate.toISOString());
      res.setHeader('X-API-Version-Days-Until-EOL', daysUntilEol.toString());
      
      if (daysUntilEol <= 0) {
        return res.status(410).json({
          error: 'API Version End of Life',
          message: `API version "${requestedVersion}" has reached end of life.`,
          latestVersion: latestVersion,
          endOfLifeDate: versionInfo.endOfLifeDate,
          hint: 'Please upgrade to the latest API version.'
        });
      }
    }
  }
  
  // Add version info headers for client awareness
  res.setHeader('X-API-Version', requestedVersion);
  res.setHeader('X-API-Version-Latest', getLatestVersion());
  
  next();
};

/**
 * Middleware to require a specific minimum API version
 * @param {string} minVersion - Minimum required version (YYYY-MM-DD)
 */
export const requireMinVersion = (minVersion) => {
  return (req, res, next) => {
    const requestedVersion = req.apiVersion || getApiVersionFromRequest(req);
    
    // Compare versions (date-based, so string comparison works)
    if (requestedVersion < minVersion) {
      return res.status(400).json({
        error: 'API Version Too Old',
        message: `This endpoint requires API version ${minVersion} or higher.`,
        requestedVersion: requestedVersion,
        minimumVersion: minVersion,
        latestVersion: getLatestVersion(),
        hint: `Please upgrade your API version using ${API_VERSION_HEADER} header.`
      });
    }
    
    next();
  };
};

/**
 * Helper function to get version-specific behavior
 * @param {Object} versionHandlers - Object mapping versions to handlers
 * @returns {Function} Express middleware function
 * 
 * Example:
 * const handler = getVersionHandler({
 *   '2024-01-01': (req, res) => res.json({ legacy: true }),
 *   '2024-10-01': (req, res) => res.json({ modern: true })
 * });
 */
export const getVersionHandler = (versionHandlers) => {
  return (req, res, next) => {
    const version = req.apiVersion || getApiVersionFromRequest(req);
    const handler = versionHandlers[version];
    
    if (handler) {
      return handler(req, res, next);
    }
    
    // Fallback to default or latest version handler
    const latestVersion = getLatestVersion();
    const defaultHandler = versionHandlers[latestVersion] || versionHandlers[DEFAULT_VERSION];
    
    if (defaultHandler) {
      return defaultHandler(req, res, next);
    }
    
    return res.status(500).json({
      error: 'Version Handler Not Found',
      message: 'No handler found for the requested API version.'
    });
  };
};

/**
 * Export version utilities for use in routes
 */
export const versionUtils = {
  getApiVersionFromRequest,
  isVersionSupported,
  isVersionDeprecated,
  getLatestVersion,
  DEFAULT_VERSION,
  SUPPORTED_VERSIONS,
  API_VERSION_HEADER
};

