import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/location_permission_dialog.dart';
import 'location_service.dart';

/// Service to handle location permission onboarding for new users
class LocationOnboardingService {
  static const String _hasRequestedLocationKey =
      'has_requested_location_permission';
  static const String _userHasSeenLocationPromptKey =
      'user_seen_location_prompt';

  /// Check if we should show location permission dialog for new user
  static Future<bool> shouldShowLocationOnboarding() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if user has already seen the location prompt
    bool hasSeenPrompt = prefs.getBool(_userHasSeenLocationPromptKey) ?? false;

    return !hasSeenPrompt;
  }

  /// Mark that user has seen the location onboarding prompt
  static Future<void> markLocationOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_userHasSeenLocationPromptKey, true);
  }

  /// Show location permission dialog for new users
  /// Call this after successful sign-in
  static Future<void> showLocationOnboardingIfNeeded(
    context, {
    String? appName,
    VoidCallback? onPermissionGranted,
    VoidCallback? onPermissionDenied,
    VoidCallback? onSkip,
  }) async {
    // Check if we should show the onboarding
    bool shouldShow = await shouldShowLocationOnboarding();

    if (!shouldShow) {
      return; // User has already seen this
    }

    // Mark that user has seen the prompt
    await markLocationOnboardingSeen();

    // Show the permission dialog
    bool granted = await LocationPermissionHelper.requestLocationPermission(
      context,
      appName: appName ?? 'Snehayog',
      onGranted: () {
        print('✅ New user granted location permission');
        onPermissionGranted?.call();
      },
      onDenied: () {
        print('❌ New user denied location permission');
        onPermissionDenied?.call();
      },
    );

    // If user denied, you can show additional onboarding UI
    if (!granted) {
      _showLocationBenefitsDialog(context, onSkip: onSkip);
    }
  }

  /// Show additional dialog explaining benefits of location
  static Future<void> _showLocationBenefitsDialog(
    context, {
    VoidCallback? onSkip,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.blue),
            SizedBox(width: 8),
            Text('Discover Local Content'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📍 Find videos from creators near you'),
            SizedBox(height: 8),
            Text('🎯 Get personalized recommendations'),
            SizedBox(height: 8),
            Text('🤝 Connect with local communities'),
            SizedBox(height: 8),
            Text('📱 Share your location in videos (optional)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              onSkip?.call();
            },
            child: const Text('Skip for Now'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Try requesting permission again
              bool granted =
                  await LocationPermissionHelper.requestLocationPermission(
                context,
                appName: 'Snehayog',
              );

              if (granted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        '🎉 Location enabled! Enjoy personalized content.'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Enable Location'),
          ),
        ],
      ),
    );
  }

  /// Reset onboarding (for testing purposes)
  static Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userHasSeenLocationPromptKey);
    await prefs.remove(_hasRequestedLocationKey);
  }

  /// Check if user has location permission
  static Future<bool> hasLocationPermission() async {
    final locationService = LocationService();
    return await locationService.isLocationPermissionGranted();
  }
}
