import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage device ID for persistent authentication
/// 
/// **CRITICAL**: Device IDs MUST persist across app reinstalls for auto-login to work!
/// 
/// **Android**: Uses Android ID (device-level, persists across reinstalls)
/// **iOS**: Uses Keychain via flutter_secure_storage (persists across reinstalls)
/// 
/// The device ID is used to link the device to a user's refresh token in MongoDB,
/// enabling automatic login even after the app is uninstalled and reinstalled.
class PlatformIdService {
  static final PlatformIdService _instance = PlatformIdService._internal();
  factory PlatformIdService() => _instance;
  PlatformIdService._internal();

  String? _cachedDeviceId;
  
  // Storage keys
  static const String _secureStorageKey = 'device_id_persistent';
  static const String _sharedPrefsKey = 'persistent_platform_id';
  
  // Secure storage for iOS Keychain (survives reinstalls)
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      // CRITICAL: This makes the keychain item survive app reinstalls
    ),
  );

  /// Get persistent device ID
  /// This ID survives app reinstalls and is used for auto-login
  Future<String> getPlatformId() async {
    try {
      // 1. Return cached value if available (fastest)
      if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
        return _cachedDeviceId!;
      }

      // 2. Try to get from persistent storage first
      String? storedId;
      
      if (Platform.isIOS) {
        // iOS: Use Keychain (persists across reinstalls)
        try {
          storedId = await _secureStorage.read(key: _secureStorageKey);
          if (storedId != null && storedId.isNotEmpty) {
            _cachedDeviceId = storedId;
            if (kDebugMode) {
              print('✅ PlatformIdService: Using iOS Keychain ID: ${_cachedDeviceId!.substring(0, 8)}...');
            }
            return _cachedDeviceId!;
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ PlatformIdService: Keychain read error: $e');
          }
        }
      } else {
        // Android: Check SharedPreferences first
        try {
          final prefs = await SharedPreferences.getInstance();
          storedId = prefs.getString(_sharedPrefsKey);
          if (storedId != null && storedId.isNotEmpty) {
            _cachedDeviceId = storedId;
            if (kDebugMode) {
              print('✅ PlatformIdService: Using stored Android ID: ${_cachedDeviceId!.substring(0, 8)}...');
            }
            return _cachedDeviceId!;
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ PlatformIdService: SharedPrefs read error: $e');
          }
        }
      }

      // 3. Generate new ID from device
      final deviceInfo = DeviceInfoPlugin();
      String newDeviceId = '';

      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          // Android ID is device-specific and persists across reinstalls
          newDeviceId = androidInfo.id;
          
          // Fallback for emulators or when ID is generic
          if (newDeviceId.isEmpty || newDeviceId == '9774d56d682e549c') {
            newDeviceId = 'android_${DateTime.now().millisecondsSinceEpoch}_${androidInfo.model.replaceAll(' ', '_')}';
          }
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          // identifierForVendor persists until all apps from vendor are deleted
          // But we store it in Keychain which ALWAYS persists
          newDeviceId = iosInfo.identifierForVendor ?? '';
          
          if (newDeviceId.isEmpty) {
            newDeviceId = 'ios_${DateTime.now().millisecondsSinceEpoch}_${iosInfo.model.replaceAll(' ', '_')}';
          }
        }
      } catch (deviceError) {
        if (kDebugMode) {
          print('⚠️ PlatformIdService: Device info error: $deviceError');
        }
        newDeviceId = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
      }

      // 4. Store the new ID persistently
      if (Platform.isIOS) {
        try {
          await _secureStorage.write(key: _secureStorageKey, value: newDeviceId);
          if (kDebugMode) {
            print('✅ PlatformIdService: Stored NEW ID in iOS Keychain');
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ PlatformIdService: Keychain write error: $e');
          }
        }
      } else {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_sharedPrefsKey, newDeviceId);
          if (kDebugMode) {
            print('✅ PlatformIdService: Stored NEW ID in SharedPreferences');
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ PlatformIdService: SharedPrefs write error: $e');
          }
        }
      }

      _cachedDeviceId = newDeviceId;
      
      if (kDebugMode) {
        print('✅ PlatformIdService: Generated device ID: ${newDeviceId.substring(0, 8)}...');
      }
      
      return newDeviceId;

    } catch (e) {
      // Ultimate failsafe
      final fallback = 'emergency_${DateTime.now().millisecondsSinceEpoch}';
      if (kDebugMode) {
        print('❌ PlatformIdService: Critical error, using fallback: $e');
      }
      return _cachedDeviceId ?? fallback;
    }
  }

  /// Get device name for display in sessions list
  Future<String> getDeviceName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return '${info.brand} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return info.name;
      }
      
      return 'Unknown Device';
    } catch (e) {
      return 'Unknown Device';
    }
  }

  /// Get platform type
  String getPlatformType() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Clear device ID (use with caution - breaks auto-login)
  /// Only call this when user explicitly wants to unlink device
  Future<void> clearDeviceId() async {
    _cachedDeviceId = null;
    
    try {
      if (Platform.isIOS) {
        await _secureStorage.delete(key: _secureStorageKey);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sharedPrefsKey);
      
      if (kDebugMode) {
        print('✅ PlatformIdService: Device ID cleared (auto-login disabled)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ PlatformIdService: Error clearing device ID: $e');
      }
    }
  }

  // Legacy method name for backward compatibility
  Future<void> clearCache() => clearDeviceId();
}
