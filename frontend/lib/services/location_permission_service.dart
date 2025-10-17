import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/location_permission_dialog.dart';

/// Simple service to handle location permission on app startup
class LocationPermissionService {
  static const String _hasRequestedLocationKey =
      'has_requested_location_permission';

  /// Check if we should show location permission dialog
  static Future<bool> shouldShowLocationPermission() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_hasRequestedLocationKey) ?? false);
  }

  /// Mark that we have requested location permission
  static Future<void> markLocationPermissionRequested() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasRequestedLocationKey, true);
  }

  /// Show location permission dialog on app startup
  static Future<void> requestLocationPermissionOnStartup(
    BuildContext context, {
    String? appName,
  }) async {
    // Check if we should show the dialog
    bool shouldShow = await shouldShowLocationPermission();
    if (!shouldShow) return;

    // Mark that we have requested permission
    await markLocationPermissionRequested();

    // Show the dialog
    await LocationPermissionDialog.show(
      context,
      appName: appName ?? 'Snehayog',
      onPermissionGranted: () {
        print('✅ Location permission granted on startup');
      },
      onPermissionDenied: () {
        print('❌ Location permission denied on startup');
      },
    );
  }

  /// Reset permission request (for testing)
  static Future<void> resetPermissionRequest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hasRequestedLocationKey);
  }
}
