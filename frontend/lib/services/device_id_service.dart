import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vayu/config/app_config.dart';

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

  /// **IMPROVED: Check if device ID has been stored (user has logged in before)**
  /// Uses backend verification to check if device ID has logged in before
  /// This works across app reinstalls since device ID is stored on backend
  Future<bool> hasStoredDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // **FAST PATH: Check local flag first (for same session)**
      final hasStored = prefs.getBool(_deviceIdKey) ?? false;
      final storedId = prefs.getString(_deviceIdValueKey);

      if (hasStored && storedId != null && storedId.isNotEmpty) {
        if (kDebugMode) {
          print(
              '✅ DeviceIdService: Found stored device ID flag in current session');
        }
        return true;
      }

      // **REINSTALL SCENARIO: Verify with backend if device ID has logged in before**
      // Platform device IDs persist across reinstalls, so we can check backend
      try {
        final deviceInfo = DeviceInfoPlugin();
        String? platformDeviceId;

        if (defaultTargetPlatform == TargetPlatform.android) {
          final androidInfo = await deviceInfo.androidInfo;
          platformDeviceId = androidInfo.id;
          // Skip emulator ID and empty IDs
          if (platformDeviceId.isEmpty ||
              platformDeviceId == '9774d56d682e549c') {
            if (kDebugMode) {
              print(
                  '⚠️ DeviceIdService: Invalid Android ID (emulator or empty)');
            }
            return false;
          }
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          final iosInfo = await deviceInfo.iosInfo;
          platformDeviceId = iosInfo.identifierForVendor;
          if (platformDeviceId == null || platformDeviceId.isEmpty) {
            if (kDebugMode) {
              print(
                  '⚠️ DeviceIdService: iOS identifierForVendor is null or empty');
            }
            return false;
          }
        } else {
          if (kDebugMode) {
            print('⚠️ DeviceIdService: Unsupported platform');
          }
          return false;
        }

        // **VERIFY WITH BACKEND: Check if this device ID has logged in before**
        try {
          // Use getBaseUrlWithFallback for better reliability
          final baseUrl = await AppConfig.getBaseUrlWithFallback();
          final response = await http
              .post(
                Uri.parse('$baseUrl/api/auth/check-device'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'deviceId': platformDeviceId}),
              )
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final hasLoggedIn = data['hasLoggedIn'] ?? false;

            if (hasLoggedIn) {
              // Device ID found on backend - user logged in before
              // Store it locally for future checks
              await prefs.setBool(_deviceIdKey, true);
              await prefs.setString(_deviceIdValueKey, platformDeviceId);
              _cachedDeviceId = platformDeviceId;

              if (kDebugMode) {
                print(
                    '✅ DeviceIdService: Device ID verified with backend - user logged in before');
                print(
                    '✅ DeviceIdService: Device ID: ${platformDeviceId.substring(0, 8)}...');
                print(
                    '✅ DeviceIdService: User: ${data['userName'] ?? 'Unknown'}');
              }

              return true;
            } else {
              if (kDebugMode) {
                print(
                    'ℹ️ DeviceIdService: Device ID not found on backend - first time login');
              }
              return false;
            }
          } else {
            if (kDebugMode) {
              print(
                  '⚠️ DeviceIdService: Backend check failed: ${response.statusCode}');
            }
            // **IMPROVED: Don't fall back to permissive approach - require login**
            // This is more secure and prevents unauthorized access
            return false;
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ DeviceIdService: Error checking with backend: $e');
            print(
                'ℹ️ DeviceIdService: Backend unreachable - requiring login for security');
          }
          // **IMPROVED: Don't allow access if backend is unreachable**
          // This is more secure - user should login when backend is available
          return false;
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ DeviceIdService: Error getting platform device ID: $e');
        }
        return false;
      }
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
