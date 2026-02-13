import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/shared/services/http_client_service.dart';
import 'dart:convert';
import 'package:geocoding/geocoding.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';

class LocationOnboardingService {
  static const String _locationPermissionKey = 'location_permission_granted';
  static const String _locationOnboardingShownKey = 'location_onboarding_shown';

  /// Check if location onboarding should be shown
  static Future<bool> shouldShowLocationOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasShownOnboarding =
          prefs.getBool(_locationOnboardingShownKey) ?? false;
      final hasPermission = prefs.getBool(_locationPermissionKey) ?? false;

      // Check if user has location data in backend
      final hasLocationDataInBackend = await hasLocationInBackend();

      // Show onboarding if:
      // 1. Haven't shown onboarding yet, OR
      // 2. Don't have permission, OR
      // 3. Don't have location data in backend
      return !hasShownOnboarding || !hasPermission || !hasLocationDataInBackend;
    } catch (e) {
      return true; // Show onboarding on error
    }
  }

  /// Show location permission request using native system dialog
  static Future<bool> showLocationOnboarding(BuildContext context) async {
    try {
      print(
          '🚀 LocationOnboarding: Starting native location permission request');

      // Check current permission status
      final currentPermission = await Geolocator.checkPermission();
      print('📍 Current location permission: $currentPermission');

      if (currentPermission == LocationPermission.always ||
          currentPermission == LocationPermission.whileInUse) {
        print('✅ Location permission already granted');
        await _markLocationPermissionGranted();
        return true;
      }

      // Check if permission is permanently denied
      if (currentPermission == LocationPermission.deniedForever) {
        print('❌ Location permission permanently denied');
        await _markOnboardingShown();
        return false;
      }

      // Request permission using native system dialog
      print('📍 Requesting location permission via native system dialog...');
      final permission = await Geolocator.requestPermission();
      print('📍 Permission result: $permission');

      // Mark onboarding as shown regardless of result
      await _markOnboardingShown();

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        print('✅ Location permission granted via native dialog');
        await _markLocationPermissionGranted();

        // Try to get and save location to backend
        final locationSaved = await getCurrentLocationAndSave();
        if (locationSaved) {
          print('✅ Location data saved to backend');
        } else {
          print(
              '⚠️ Location permission granted but failed to save location data');
        }

        return true;
      } else {
        print('❌ Location permission denied via native dialog');
        return false;
      }
    } catch (e) {
      print('❌ LocationOnboarding: Error in location permission request: $e');
      await _markOnboardingShown();
      return false;
    }
  }

  /// Check if location permission is currently granted
  static Future<bool> isLocationPermissionGranted() async {
    try {
      final permission = await Geolocator.checkPermission();
      final isGranted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;

      print('🔍 LocationOnboarding: Permission granted: $isGranted');
      return isGranted;
    } catch (e) {
      print('❌ LocationOnboarding: Error checking permission: $e');
      return false;
    }
  }

  /// Request location permission (direct call without onboarding logic)
  static Future<bool> requestLocationPermission() async {
    try {
      print('📍 Direct location permission request...');
      final permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        await _markLocationPermissionGranted();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ LocationOnboarding: Error requesting permission: $e');
      return false;
    }
  }

  /// Get current location if permission is granted
  static Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await isLocationPermissionGranted();
      if (!hasPermission) {
        print('❌ LocationOnboarding: No location permission');
        return null;
      }

      print('📍 Getting current location...');
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      print(
          '✅ LocationOnboarding: Got location: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('❌ LocationOnboarding: Error getting location: $e');
      return null;
    }
  }

  /// Get current location and save to backend
  static Future<bool> getCurrentLocationAndSave() async {
    try {
      final position = await getCurrentLocation();
      if (position == null) {
        print('❌ LocationOnboarding: No location data to save');
        return false;
      }

      print('📍 Getting address from coordinates...');
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final address = _formatAddress(placemark);

        print('📍 Formatted address: $address');

        // Save to backend
        final success = await _saveLocationToBackend(
          latitude: position.latitude,
          longitude: position.longitude,
          address: address,
          city: placemark.locality ?? '',
          state: placemark.administrativeArea ?? '',
          country: placemark.country ?? '',
        );

        if (success) {
          print('✅ LocationOnboarding: Location saved to backend successfully');
          return true;
        } else {
          print('❌ LocationOnboarding: Failed to save location to backend');
          return false;
        }
      } else {
        print('❌ LocationOnboarding: No address found for coordinates');
        return false;
      }
    } catch (e) {
      print('❌ LocationOnboarding: Error getting and saving location: $e');
      return false;
    }
  }

  /// Save location data to backend
  static Future<bool> _saveLocationToBackend({
    required double latitude,
    required double longitude,
    required String address,
    required String city,
    required String state,
    required String country,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        print('❌ LocationOnboarding: No auth token available');
        return false;
      }

      final response = await httpClientService.post(
        Uri.parse('${AuthService.baseUrl}/api/users/update-location'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'latitude': latitude,
          'longitude': longitude,
          'address': address,
          'city': city,
          'state': state,
          'country': country,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ LocationOnboarding: Location saved to backend');
        return true;
      } else {
        print(
            '❌ LocationOnboarding: Backend error: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ LocationOnboarding: Error saving to backend: $e');
      return false;
    }
  }

  /// Check if user has location data in backend
  static Future<bool> hasLocationInBackend() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        print('❌ LocationOnboarding: No auth token available');
        return false;
      }

      final response = await httpClientService.get(
        Uri.parse('${AuthService.baseUrl}/api/users/location-permission'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final hasLocationData = data['hasLocationData'] ?? false;
        print(
            '📍 LocationOnboarding: Backend location status: $hasLocationData');
        return hasLocationData;
      } else {
        print(
            '❌ LocationOnboarding: Backend error: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ LocationOnboarding: Error checking backend location: $e');
      return false;
    }
  }

  /// Format address from placemark
  static String _formatAddress(Placemark placemark) {
    final parts = <String>[];

    if (placemark.street?.isNotEmpty == true) {
      parts.add(placemark.street!);
    }
    if (placemark.locality?.isNotEmpty == true) {
      parts.add(placemark.locality!);
    }
    if (placemark.administrativeArea?.isNotEmpty == true) {
      parts.add(placemark.administrativeArea!);
    }
    if (placemark.country?.isNotEmpty == true) {
      parts.add(placemark.country!);
    }

    return parts.join(', ');
  }

  /// Reset onboarding state (for testing)
  static Future<void> resetOnboardingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_locationPermissionKey);
      await prefs.remove(_locationOnboardingShownKey);
      print('🔄 LocationOnboarding: Reset onboarding state');
    } catch (e) {
      print('❌ LocationOnboarding: Error resetting state: $e');
    }
  }

  /// Debug: Print current onboarding status
  static Future<void> debugOnboardingStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasShownOnboarding =
          prefs.getBool(_locationOnboardingShownKey) ?? false;
      final hasPermission = prefs.getBool(_locationPermissionKey) ?? false;
      final currentPermission = await Geolocator.checkPermission();

      print('🔍 LocationOnboarding Debug Status:');
      print('   - Has shown onboarding: $hasShownOnboarding');
      print('   - Has permission flag: $hasPermission');
      print('   - Current system permission: $currentPermission');
      print(
          '   - Should show onboarding: ${await shouldShowLocationOnboarding()}');
    } catch (e) {
      print('❌ LocationOnboarding: Error in debug status: $e');
    }
  }

  // Private helper methods

  static Future<void> _markLocationPermissionGranted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_locationPermissionKey, true);
      print('✅ LocationOnboarding: Marked location permission as granted');
    } catch (e) {
      print('❌ LocationOnboarding: Error marking permission granted: $e');
    }
  }

  static Future<void> _markOnboardingShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_locationOnboardingShownKey, true);
      print('✅ LocationOnboarding: Marked onboarding as shown');
    } catch (e) {
      print('❌ LocationOnboarding: Error marking onboarding shown: $e');
    }
  }
}
