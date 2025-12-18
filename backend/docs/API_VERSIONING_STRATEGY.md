# API Versioning Strategy

## Overview

This document describes the date-based API versioning strategy used in the Vayu backend. This approach uses date-based versioning (e.g., `2024-01-01`, `2024-10-01`) instead of semantic versioning for better clarity and predictability.

## Date-Based Versioning

### Format
- **Format**: `YYYY-MM-DD` (e.g., `2024-01-01`, `2024-10-01`)
- **Header**: `X-API-Version`
- **Default Version**: `2024-10-01`

### Why Date-Based?

1. **Clarity**: Dates are immediately understandable - you know when a version was released
2. **Predictability**: Easy to plan deprecation schedules
3. **No Confusion**: No debates about semantic versioning (major.minor.patch)
4. **Business-Friendly**: Non-technical stakeholders can understand version timelines

## Version Lifecycle

### 1. Active Versions
- Multiple API versions can be active simultaneously
- Each version maintains a stable contract
- Backward compatibility is maintained within a version

### 2. Deprecation
- Versions can be marked as deprecated
- Deprecated versions continue to work but show warnings
- Deprecation date is set when marking a version as deprecated

### 3. End of Life (EOL)
- Versions can have an end-of-life date
- After EOL, the version returns `410 Gone`
- Clients must upgrade to a supported version

## Implementation

### Middleware
The `apiVersioning` middleware (`middleware/apiVersioning.js`) handles:
- Version extraction from headers
- Version validation
- Deprecation warnings
- EOL enforcement

### Usage in Routes
```javascript
import { apiVersioning } from '../middleware/apiVersioning.js';

// Apply to all routes
app.use('/api', apiVersioning);

// Or to specific routes
router.get('/endpoint', apiVersioning, handler);
```

### Version-Specific Behavior
```javascript
import { getVersionHandler } from '../middleware/apiVersioning.js';

const handler = getVersionHandler({
  '2024-01-01': (req, res) => {
    // Legacy behavior
    res.json({ legacy: true });
  },
  '2024-10-01': (req, res) => {
    // Modern behavior
    res.json({ modern: true });
  }
});

router.get('/endpoint', handler);
```

## Deprecation Strategy

### Timeline Example

1. **Release New Version** (e.g., `2024-10-01`)
   - New version is active
   - Old version (`2024-01-01`) still works

2. **Deprecate Old Version** (e.g., 3 months later)
   ```javascript
   '2024-01-01': {
     deprecated: true,
     deprecatedDate: '2024-01-15',
     endOfLifeDate: '2024-04-15', // 3 months after deprecation
   }
   ```
   - Old version shows deprecation warnings
   - Headers indicate deprecation status

3. **End of Life** (e.g., 6 months after release)
   - Old version returns `410 Gone`
   - Clients must upgrade

### Communication

1. **Deprecation Notice**: 3 months before EOL
   - Add `X-API-Version-Deprecated: true` header
   - Include `X-API-Version-End-Of-Life` date
   - Log deprecation warnings

2. **EOL Notice**: 1 month before EOL
   - Increase warning frequency
   - Send notifications to known clients

3. **EOL Enforcement**: On EOL date
   - Return `410 Gone` for deprecated versions
   - Provide clear error message with upgrade path

## Best Practices

### 1. Version Stability
- **Never break backward compatibility within a version**
- If breaking changes are needed, create a new version
- Document all changes in version release notes

### 2. Version Support Window
- **Support at least 2-3 versions simultaneously**
- Keep old versions active for 6-12 months
- Provide migration guides for major changes

### 3. Version Communication
- **Document version changes clearly**
- Provide migration guides
- Announce deprecations well in advance
- Use headers to communicate version status

### 4. Testing
- **Test all active versions**
- Ensure backward compatibility
- Test deprecation and EOL flows

## Example: Adding a New Version

### Step 1: Define Version
```javascript
// middleware/apiVersioning.js
const SUPPORTED_VERSIONS = {
  '2024-01-01': { ... },
  '2024-10-01': { ... },
  '2025-01-01': { // New version
    releaseDate: new Date('2025-01-01'),
    deprecated: false,
    description: 'New features and improvements'
  }
};
```

### Step 2: Update Default Version
```javascript
const DEFAULT_VERSION = '2025-01-01';
```

### Step 3: Implement Version-Specific Logic
```javascript
const handler = getVersionHandler({
  '2024-10-01': legacyHandler,
  '2025-01-01': newHandler,
});
```

### Step 4: Deprecate Old Version (after 3 months)
```javascript
'2024-10-01': {
  deprecated: true,
  deprecatedDate: '2024-10-15',
  endOfLifeDate: '2025-01-15', // 3 months grace period
}
```

## Monitoring

### Metrics to Track
- **Version Usage**: Which versions are most used
- **Deprecation Warnings**: How many clients see warnings
- **EOL Errors**: How many clients hit EOL
- **Migration Rate**: How quickly clients upgrade

### Alerts
- Alert when deprecated version usage exceeds threshold
- Alert when EOL date approaches
- Alert on version-related errors

## Common Pitfalls

### ❌ Don't
- Break backward compatibility within a version
- Deprecate versions too quickly
- Remove versions without proper notice
- Use semantic versioning alongside date-based

### ✅ Do
- Maintain stable contracts per version
- Provide clear migration paths
- Give adequate notice for deprecations
- Test all active versions
- Document version changes

## Migration Guide for Clients

### Flutter App
```dart
// Set API version in headers
final response = await http.get(
  url,
  headers: {
    'X-API-Version': '2024-10-01',
  },
);
```

### Handling Deprecation
```dart
// Check deprecation header
if (response.headers['x-api-version-deprecated'] == 'true') {
  // Show warning to user
  // Plan migration to new version
}
```

### Handling EOL
```dart
if (response.statusCode == 410) {
  // Version is end of life
  // Force app update or show error
}
```

## Summary

- **Format**: Date-based (`YYYY-MM-DD`)
- **Header**: `X-API-Version`
- **Support**: Multiple active versions simultaneously
- **Deprecation**: 3-month notice before EOL
- **EOL**: 6-12 months after release
- **Stability**: Never break backward compatibility within a version

