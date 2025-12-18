# Quick Start: Backend-Driven Architecture

## 5-Minute Setup

### Step 1: Seed AppConfig (Backend)

```bash
cd snehayog/backend
node scripts/seed-app-config.js
```

This creates the initial AppConfig document in MongoDB.

### Step 2: Initialize in Flutter (Frontend)

Add to `main.dart`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize remote config
  await AppRemoteConfigService.instance.initialize();
  
  runApp(MyApp());
}
```

### Step 3: Wrap App with ForcedUpdateWidget

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ForcedUpdateWidget(
        child: HomeScreen(),
      ),
    );
  }
}
```

### Step 4: Use AppText for Strings

Replace hard-coded strings:

```dart
// Before
Text('Upload')

// After
Text(AppText.get('btn_upload'))
// Or
Text('btn_upload'.t)
```

## Common Tasks

### Update UI Text

**MongoDB**:
```javascript
db.app_configs.updateOne(
  { platform: 'android', environment: 'production' },
  { $set: { 'uiTexts.btn_upload': 'Upload Video' } }
);
```

**Result**: All `AppText.get('btn_upload')` calls automatically use new text.

### Enable/Disable Feature

**MongoDB**:
```javascript
db.app_configs.updateOne(
  { platform: 'android' },
  { $set: { 'featureFlags.imageUploadForCreators': false } }
);
```

**Flutter**:
```dart
if (AppRemoteConfigService.instance.config?.featureFlags.imageUploadForCreators == true) {
  // Show feature
}
```

### Force App Update

**MongoDB**:
```javascript
db.app_configs.updateOne(
  { platform: 'android' },
  { 
    $set: { 
      'versionControl.minSupportedAppVersion': '1.5.0',
      'versionControl.latestAppVersion': '1.5.0'
    }
  }
);
```

**Result**: Users with version < 1.5.0 will see forced update screen.

### Emergency Kill Switch

**MongoDB**:
```javascript
db.app_configs.updateOne(
  { platform: 'android' },
  { 
    $set: { 
      'killSwitch.enabled': true,
      'killSwitch.message': 'App is temporarily unavailable.'
    }
  }
);
```

**Result**: App shows message and blocks usage.

## API Endpoints

- `GET /api/app-config` - Full configuration
- `GET /api/app-config/version-check?appVersion=1.4.0` - Check version
- `GET /api/app-config/texts` - UI texts only
- `GET /api/app-config/kill-switch` - Kill switch status

## Testing

### Test Forced Update

1. Set `minSupportedAppVersion` to higher than current app version
2. Restart app
3. Should see forced update screen

### Test Kill Switch

1. Set `killSwitch.enabled: true`
2. Restart app
3. Should see kill switch message

### Test Text Updates

1. Update `uiTexts` in MongoDB
2. Clear app cache: `AppRemoteConfigService.instance.clearCache()`
3. Restart app
4. Should see new texts

## Troubleshooting

**Config not loading?**
- Check MongoDB connection
- Verify AppConfig document exists
- Check platform/environment match

**Forced update not working?**
- Verify version format (e.g., "1.4.0")
- Check `minSupportedAppVersion` in config
- Verify update URLs

**Texts not updating?**
- Clear app cache
- Restart app
- Check config fetch logs

## Next Steps

- Read [BACKEND_DRIVEN_ARCHITECTURE.md](./BACKEND_DRIVEN_ARCHITECTURE.md) for full documentation
- Read [API_VERSIONING_STRATEGY.md](./API_VERSIONING_STRATEGY.md) for versioning details
- Customize AppConfig for your needs
- Add more feature flags and business rules

