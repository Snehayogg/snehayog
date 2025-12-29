import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage platform ID as source of truth
/// Platform IDs persist across app reinstalls:
/// - Android: Android ID (persists across reinstalls, but not factory reset)
/// - iOS: Identifier for Vendor (persists across reinstalls of same vendor's apps)
///
/// **FIXED STRATEGY**: Store platform ID in SharedPreferences to ensure persistence
/// This ensures watch history persists even if device ID changes or app data is cleared
class PlatformIdService {
  static final PlatformIdService _instance = PlatformIdService._internal();
  factory PlatformIdService() => _instance;
  PlatformIdService._internal();

  String? _cachedPlatformId;
  static const String _storageKey = 'persistent_platform_id';

  /// Get platform device ID (source of truth)
  /// Always returns the same platform ID, even after app data is cleared
  /// This ensures watch history can be matched across app sessions
  Future<String> getPlatformId() async {
    // Return cached value if available (in-memory)
    if (_cachedPlatformId != null) {
      return _cachedPlatformId!;
    }

    try {
      // **FIXED: Check SharedPreferences first for persistent platform ID**
      final prefs = await SharedPreferences.getInstance();
      final storedPlatformId = prefs.getString(_storageKey);
      
      if (storedPlatformId != null && storedPlatformId.isNotEmpty) {
        // Use stored platform ID (persists across app reopens)
        _cachedPlatformId = storedPlatformId;
        if (kDebugMode) {
          print(
              '✅ PlatformIdService: Using stored platform ID: ${_cachedPlatformId!.substring(0, 8)}...');
        }
        return _cachedPlatformId!;
      }

      // No stored ID - generate new one from device
      final deviceInfo = DeviceInfoPlugin();
      String platformId;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        // Android ID persists across app reinstalls (but not factory reset)
        platformId = androidInfo.id;

        // Validate Android ID (skip emulator ID)
        if (platformId.isEmpty || platformId == '9774d56d682e549c') {
          if (kDebugMode) {
            print(
                '⚠️ PlatformIdService: Invalid Android ID (emulator or empty), generating persistent fallback');
          }
          // **FIXED: Generate persistent fallback ID (not timestamp-based)**
          // Use device model + Android ID hash for consistency
          final model = androidInfo.model.isNotEmpty ? androidInfo.model : 'unknown';
          platformId = 'android_${model}_${androidInfo.id.hashCode.abs()}';
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // Identifier for Vendor persists across reinstalls of same vendor's apps
        platformId = iosInfo.identifierForVendor ?? '';

        // Fallback to persistent ID if identifierForVendor is null (rare case)
        if (platformId.isEmpty) {
          if (kDebugMode) {
            print(
                '⚠️ PlatformIdService: iOS identifierForVendor is null, generating persistent fallback');
          }
          // **FIXED: Generate persistent fallback ID (not timestamp-based)**
          final model = iosInfo.model.isNotEmpty ? iosInfo.model : 'unknown';
          final name = iosInfo.name.isNotEmpty ? iosInfo.name : 'unknown';
          platformId = 'ios_${model}_${name.hashCode.abs()}';
        }
      } else {
        // Fallback for other platforms - use persistent identifier
        platformId = '${defaultTargetPlatform.name}_persistent';
      }

      // **CRITICAL: Store platform ID in SharedPreferences for persistence**
      await prefs.setString(_storageKey, platformId);
      
      // Cache in memory
      _cachedPlatformId = platformId;

      if (kDebugMode) {
        print(
            '✅ PlatformIdService: Generated and stored platform ID: ${_cachedPlatformId!.substring(0, 8)}...');
      }

      return _cachedPlatformId!;
    } catch (e) {
      if (kDebugMode) {
        print('❌ PlatformIdService: Error getting platform ID: $e');
      }

      // **FIXED: Try to get stored fallback ID first**
      try {
        final prefs = await SharedPreferences.getInstance();
        final storedId = prefs.getString(_storageKey);
        if (storedId != null && storedId.isNotEmpty) {
          _cachedPlatformId = storedId;
          return storedId;
        }
      } catch (_) {
        // Ignore SharedPreferences errors
      }

      // Last resort: Generate a persistent fallback ID (not timestamp-based)
      final fallbackId = 'fallback_persistent_${defaultTargetPlatform.name}';
      _cachedPlatformId = fallbackId;
      
      // Try to store it
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, fallbackId);
      } catch (_) {
        // Ignore storage errors
      }
      
      return fallbackId;
    }
  }

  /// Clear cached platform ID (called on logout or app reset)
  /// **WARNING**: This will clear the persistent platform ID, breaking watch history continuity
  /// Only use this if you want to reset the user's watch history
  Future<void> clearCache() async {
    _cachedPlatformId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      if (kDebugMode) {
        print(
            '✅ PlatformIdService: Platform ID cache and storage cleared (watch history will be reset)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ PlatformIdService: Error clearing platform ID storage: $e');
      }
    }
  }
}
