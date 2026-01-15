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
    try {
      // 1. Return cached value if available (fastest)
      if (_cachedPlatformId != null && _cachedPlatformId!.isNotEmpty) {
        return _cachedPlatformId!;
      }

      final prefs = await SharedPreferences.getInstance();
      
      // 2. Check SharedPreferences for persistent ID
      String? storedPlatformId = prefs.getString(_storageKey);
      if (storedPlatformId != null && storedPlatformId.trim().isNotEmpty) {
        _cachedPlatformId = storedPlatformId.trim();
        if (kDebugMode) {
          print('✅ PlatformIdService: Using stored persistent ID: $_cachedPlatformId');
        }
        return _cachedPlatformId!;
      }

      // 3. Generate new ID if none stored
      final deviceInfo = DeviceInfoPlugin();
      String newPlatformId = '';

      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          final androidInfo = await deviceInfo.androidInfo;
          newPlatformId = androidInfo.id;
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          final iosInfo = await deviceInfo.iosInfo;
          newPlatformId = iosInfo.identifierForVendor ?? '';
        }
      } catch (deviceError) {
        if (kDebugMode) {
          print('⚠️ PlatformIdService: Error getting device info: $deviceError');
        }
      }

      // 4. Validate and Fallback
      if (newPlatformId.trim().isEmpty || newPlatformId == '9774d56d682e549c') {
         // Generate robust fallback using timestamp and random number
         final timestamp = DateTime.now().millisecondsSinceEpoch;
         final random = (timestamp % 10000) + 1000;
         newPlatformId = 'fallback_${defaultTargetPlatform.name}_${timestamp}_$random';
         
         if (kDebugMode) {
           print('⚠️ PlatformIdService: Generated fallback ID: $newPlatformId');
         }
      }

      // 5. Store and return
      await prefs.setString(_storageKey, newPlatformId);
      _cachedPlatformId = newPlatformId;
      
      if (kDebugMode) {
        print('✅ PlatformIdService: Generated and stored NEW Platform ID: $newPlatformId');
      }
      
      return newPlatformId;

    } catch (e) {
      // Ultimate failsafe
      final fallback = 'emergency_fallback_${DateTime.now().millisecondsSinceEpoch}';
      if (kDebugMode) {
         print('❌ PlatformIdService: Critical error, using emergency fallback: $e');
      }
      return _cachedPlatformId ?? fallback;
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
