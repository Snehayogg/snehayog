import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/location_service.dart';

/// Modern location permission dialog matching Android's native design
/// Shows "Precise" vs "Approximate" location options
class LocationPermissionDialog extends StatefulWidget {
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
  State<LocationPermissionDialog> createState() =>
      _LocationPermissionDialogState();

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

class _LocationPermissionDialogState extends State<LocationPermissionDialog> {
  bool _isLoading = false;
  bool _selectedPrecise = true; // Default to precise location

  @override
  Widget build(BuildContext context) {
    final appName = widget.appName ?? 'Vayu';

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Location icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.location_on,
                size: 32,
                color: Colors.blue.shade600,
              ),
            ),
            const SizedBox(height: 16),

            // Main question
            Text(
              'Allow $appName to access this device\'s precise location?',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Location accuracy options
            Row(
              children: [
                Expanded(
                  child: _buildLocationOption(
                    title: 'Precise',
                    description: 'More accurate location',
                    icon: Icons.my_location,
                    isSelected: _selectedPrecise,
                    onTap: () => setState(() => _selectedPrecise = true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildLocationOption(
                    title: 'Approximate',
                    description: 'Less accurate location',
                    icon: Icons.location_searching,
                    isSelected: !_selectedPrecise,
                    onTap: () => setState(() => _selectedPrecise = false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Permission duration options
            _buildPermissionOptions(),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationOption({
    required String title,
    required String description,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? Colors.blue.shade50 : Colors.white,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? Colors.blue : Colors.grey.shade600,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.blue : Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.blue.shade700 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionOptions() {
    return Column(
      children: [
        // While using the app
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : () => _requestPermission(LocationPermission.whileInUse),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'While using the app',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // Only this time
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _isLoading
                ? null
                : () => _requestPermission(LocationPermission.whileInUse,
                    oneTime: true),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: const BorderSide(color: Colors.blue),
            ),
            child: const Text(
              'Only this time',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Deny
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _isLoading ? null : _denyPermission,
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Deny',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _requestPermission(LocationPermission permission,
      {bool oneTime = false}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check current permission
      LocationPermission currentPermission = await Geolocator.checkPermission();

      if (currentPermission == LocationPermission.denied) {
        // Request permission
        LocationPermission newPermission = await Geolocator.requestPermission();

        if (newPermission == LocationPermission.denied) {
          _showPermissionDenied();
          return;
        }

        if (newPermission == LocationPermission.deniedForever) {
          _showPermissionPermanentlyDenied();
          return;
        }
      }

      // Test if we can actually get location
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationServiceDisabled();
        return;
      }

      // Try to get a quick location to verify permission works
      LocationAccuracy accuracy =
          _selectedPrecise ? LocationAccuracy.high : LocationAccuracy.medium;
      Position? position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: const Duration(seconds: 5),
        ),
      );

      _showPermissionGranted();
    } catch (e) {
      print('Error requesting location permission: $e');
      _showPermissionDenied();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _denyPermission() {
    widget.onPermissionDenied?.call();
    Navigator.of(context).pop(false);
  }

  void _showPermissionGranted() {
    widget.onPermissionGranted?.call();
    Navigator.of(context).pop(true);

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Location permission granted!'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showPermissionDenied() {
    widget.onPermissionDenied?.call();
    Navigator.of(context).pop(false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.location_off, color: Colors.white),
            SizedBox(width: 8),
            Text('Location permission denied. Some features may not work.'),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showPermissionPermanentlyDenied() {
    widget.onPermissionDenied?.call();
    Navigator.of(context).pop(false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.orange),
            SizedBox(width: 8),
            Text('Permission Required'),
          ],
        ),
        content: const Text(
          'Location permission has been permanently denied. Please enable it in app settings to use location features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showLocationServiceDisabled() {
    widget.onPermissionDenied?.call();
    Navigator.of(context).pop(false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red),
            SizedBox(width: 8),
            Text('Location Services Disabled'),
          ],
        ),
        content: const Text(
          'Location services are disabled on this device. Please enable them in settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

/// Helper widget to show location permission dialog with custom styling
class LocationPermissionHelper {
  /// Show location permission dialog with modern Android-style design
  static Future<bool> requestLocationPermission(
    BuildContext context, {
    String? appName,
    VoidCallback? onGranted,
    VoidCallback? onDenied,
  }) async {
    final result = await LocationPermissionDialog.show(
      context,
      appName: appName,
      onPermissionGranted: onGranted,
      onPermissionDenied: onDenied,
    );

    return result ?? false;
  }

  /// Quick check if location permission is already granted
  static Future<bool> hasLocationPermission() async {
    final locationService = LocationService();
    return await locationService.isLocationPermissionGranted();
  }

  /// Show location permission dialog only if needed
  static Future<bool> requestIfNeeded(
    BuildContext context, {
    String? appName,
    VoidCallback? onGranted,
    VoidCallback? onDenied,
  }) async {
    // Check if permission is already granted
    if (await hasLocationPermission()) {
      onGranted?.call();
      return true;
    }

    // Show permission dialog
    return await requestLocationPermission(
      context,
      appName: appName,
      onGranted: onGranted,
      onDenied: onDenied,
    );
  }
}

/// Example usage widget
class LocationPermissionExample extends StatelessWidget {
  const LocationPermissionExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location Permission Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.location_on,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            const Text(
              'Enable Location Access',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'We need your location to show you personalized content and connect with nearby creators.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                bool granted = await LocationPermissionHelper.requestIfNeeded(
                  context,
                  appName: 'Vayu',
                  onGranted: () {
                    print('✅ Location permission granted!');
                  },
                  onDenied: () {
                    print('❌ Location permission denied');
                  },
                );

                if (granted) {
                  // Proceed with location-based features
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Great! Location features are now enabled.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.location_on),
              label: const Text('Enable Location'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


