import 'package:flutter/material.dart';
import '../services/location_service.dart';

/// Simple location permission dialog
class LocationPermissionDialog extends StatelessWidget {
  final String? appName;
  final VoidCallback? onPermissionGranted;
  final VoidCallback? onPermissionDenied;

  const LocationPermissionDialog({
    super.key,
    this.appName,
    this.onPermissionGranted,
    this.onPermissionDenied,
  });

  @override
  Widget build(BuildContext context) {
    final appName = this.appName ?? 'Snehayog';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.location_on, color: Colors.blue[600]),
          const SizedBox(width: 8),
          const Text('Location Access'),
        ],
      ),
      content: Text(
        'Allow $appName to access your location to show you personalized content and connect with nearby creators.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            onPermissionDenied?.call();
            Navigator.of(context).pop(false);
          },
          child: const Text('Deny'),
        ),
        ElevatedButton(
          onPressed: () async {
            final locationService = LocationService();
            bool granted = await locationService.requestLocationPermission();

            if (granted) {
              onPermissionGranted?.call();
              Navigator.of(context).pop(true);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Location permission granted!'),
                  backgroundColor: Colors.green,
                ),
              );
            } else {
              onPermissionDenied?.call();
              Navigator.of(context).pop(false);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Location permission denied.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          },
          child: const Text('Allow'),
        ),
      ],
    );
  }

  /// Show the location permission dialog
  static Future<bool?> show(
    BuildContext context, {
    String? appName,
    VoidCallback? onPermissionGranted,
    VoidCallback? onPermissionDenied,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => LocationPermissionDialog(
        appName: appName,
        onPermissionGranted: onPermissionGranted,
        onPermissionDenied: onPermissionDenied,
      ),
    );
  }
}

/// Helper class for location permission
class LocationPermissionHelper {
  /// Show location permission dialog only if needed
  static Future<bool> requestIfNeeded(
    BuildContext context, {
    String? appName,
    VoidCallback? onGranted,
    VoidCallback? onDenied,
  }) async {
    final locationService = LocationService();

    // Check if permission is already granted
    if (await locationService.isLocationPermissionGranted()) {
      onGranted?.call();
      return true;
    }

    // Show permission dialog
    final result = await LocationPermissionDialog.show(
      context,
      appName: appName,
      onPermissionGranted: onGranted,
      onPermissionDenied: onDenied,
    );

    return result ?? false;
  }
}
