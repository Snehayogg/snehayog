import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Service to manage device ID for persistent user identification
/// Device ID persists across app reinstalls (Android: Android ID, iOS: Identifier for Vendor)
class DeviceIdService {
  static const String _deviceIdKey = 'device_id_stored';
  static const String _deviceIdValueKey = 'device_id_value';

  static final DeviceIdService _instance = DeviceIdService._internal();
  factory DeviceIdService() => _instance;
  DeviceIdService._internal();

  String? _cachedDeviceId;

  /// Get or create device ID
  /// Returns existing device ID if available, otherwise generates and stores a new one
  Future<String> getDeviceId() async {
    // Return cached value if available
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if device ID was previously stored
      final hasStoredDeviceId = prefs.getBool(_deviceIdKey) ?? false;
      final storedDeviceId = prefs.getString(_deviceIdValueKey);

      if (hasStoredDeviceId &&
          storedDeviceId != null &&
          storedDeviceId.isNotEmpty) {
        _cachedDeviceId = storedDeviceId;
        if (kDebugMode) {
          print(
              '✅ DeviceIdService: Using stored device ID: ${_cachedDeviceId!.substring(0, 8)}...');
        }
        return _cachedDeviceId!;
      }

      // Generate new device ID from platform-specific identifier
      final deviceInfo = DeviceInfoPlugin();
      String platformDeviceId;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        // Android ID persists across app reinstalls (but not factory reset)
        platformDeviceId = androidInfo.id;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // Identifier for Vendor persists across reinstalls of same vendor's apps
        platformDeviceId = iosInfo.identifierForVendor ?? '';

        // Fallback to random UUID if identifierForVendor is null (rare case)
        if (platformDeviceId.isEmpty) {
          platformDeviceId =
              'ios_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}';
        }
      } else {
        // Fallback for other platforms
        platformDeviceId =
            '${defaultTargetPlatform.name}_${DateTime.now().millisecondsSinceEpoch}';
      }

      // Store device ID
      await prefs.setBool(_deviceIdKey, true);
      await prefs.setString(_deviceIdValueKey, platformDeviceId);

      _cachedDeviceId = platformDeviceId;

      if (kDebugMode) {
        print(
            '✅ DeviceIdService: Generated and stored new device ID: ${_cachedDeviceId!.substring(0, 8)}...');
      }

      return _cachedDeviceId!;
    } catch (e) {
      if (kDebugMode) {
        print('❌ DeviceIdService: Error getting device ID: $e');
      }

      // Fallback: Generate a temporary device ID
      final fallbackId = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
      _cachedDeviceId = fallbackId;
      return fallbackId;
    }
  }

  /// Check if device ID has been stored (user has logged in before)
  /// **PERMISSIVE APPROACH: Allows skipping login if platform device ID exists**
  /// Platform device IDs persist across reinstalls (Android ID / iOS Identifier for Vendor)
  /// **NOTE: This is permissive - any device with valid device ID can skip login**
  /// For production, backend verification should be added for better security
  Future<bool> hasStoredDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // **FIX: Only check SharedPreferences flag (clears on reinstall)**
      // Platform device ID always exists, so checking it doesn't tell us
      // if user logged in before. We only check if flag is stored in current session.
      final hasStored = prefs.getBool(_deviceIdKey) ?? false;
      final storedId = prefs.getString(_deviceIdValueKey);

      if (hasStored && storedId != null && storedId.isNotEmpty) {
        if (kDebugMode) {
          print(
              '✅ DeviceIdService: Found stored device ID flag in current session');
        }
        return true;
      }

      // **PERMISSIVE APPROACH: For reinstall scenario - check platform device ID**
      // Platform device IDs (Android ID / iOS Identifier for Vendor) persist
      // across app reinstalls. Since SharedPreferences clears on reinstall,
      // we use permissive approach: allow if device ID exists
      // This ensures reinstall doesn't force login screen

      try {
        final deviceInfo = DeviceInfoPlugin();
        String? platformDeviceId;

        if (defaultTargetPlatform == TargetPlatform.android) {
          final androidInfo = await deviceInfo.androidInfo;
          platformDeviceId = androidInfo.id;
          // Android ID can be "9774d56d682e549c" (emulator) - check for valid ID
          if (platformDeviceId.isEmpty ||
              platformDeviceId == '9774d56d682e549c') {
            platformDeviceId = null;
          }
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          final iosInfo = await deviceInfo.iosInfo;
          platformDeviceId = iosInfo.identifierForVendor;
        }

        // **PERMISSIVE: If platform device ID exists, allow access**
        // This assumes user might have logged in before (can't verify after reinstall)
        // Store it now so we don't check again
        if (platformDeviceId != null && platformDeviceId.isNotEmpty) {
          await prefs.setBool(_deviceIdKey, true);
          await prefs.setString(_deviceIdValueKey, platformDeviceId);
          _cachedDeviceId = platformDeviceId;

          if (kDebugMode) {
            print(
                '✅ DeviceIdService: Platform device ID found: ${platformDeviceId.substring(0, 8)}...');
            print(
                'ℹ️ DeviceIdService: Using permissive approach - allowing access based on device ID');
            print(
                'ℹ️ DeviceIdService: Note: This allows skipping login after reinstall');
          }

          return true; // Allow access (permissive)
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ DeviceIdService: Error getting platform device ID: $e');
        }
      }

      if (kDebugMode) {
        print('ℹ️ DeviceIdService: No valid device ID found - login required');
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ DeviceIdService: Error checking stored device ID: $e');
      }
      return false;
    }
  }

  /// Store device ID explicitly (called after successful login)
  Future<void> storeDeviceId() async {
    try {
      final deviceId =
          await getDeviceId(); // This will store if not already stored
      if (kDebugMode) {
        print(
            '✅ DeviceIdService: Device ID stored: ${deviceId.substring(0, 8)}...');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ DeviceIdService: Error storing device ID: $e');
      }
    }
  }

  /// Clear device ID (called on logout)
  Future<void> clearDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_deviceIdKey);
      await prefs.remove(_deviceIdValueKey);
      _cachedDeviceId = null;

      if (kDebugMode) {
        print('✅ DeviceIdService: Device ID cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ DeviceIdService: Error clearing device ID: $e');
      }
    }
  }

  /// Get stored device ID without generating new one
  Future<String?> getStoredDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_deviceIdValueKey);
    } catch (e) {
      if (kDebugMode) {
        print('❌ DeviceIdService: Error getting stored device ID: $e');
      }
      return null;
    }
  }
}
