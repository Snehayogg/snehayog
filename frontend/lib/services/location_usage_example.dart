import 'package:flutter/material.dart';
import 'location_permission_service.dart';

/// Example of how to use the simple location permission service
/// Add this to your main app startup (like in main.dart or home screen)
class LocationUsageExample {
  /// Call this when your app starts to request location permission
  static Future<void> requestLocationOnAppStart(BuildContext context) async {
    await LocationPermissionService.requestLocationPermissionOnStartup(
      context,
      appName: 'Snehayog',
    );
  }
}

/// Example widget showing how to integrate location permission
class LocationPermissionExampleWidget extends StatelessWidget {
  const LocationPermissionExampleWidget({super.key});

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
              'Location Permission',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'This app will request location permission when you first open it.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                await LocationPermissionService
                    .requestLocationPermissionOnStartup(
                  context,
                  appName: 'Snehayog',
                );
              },
              child: const Text('Request Location Permission'),
            ),
          ],
        ),
      ),
    );
  }
}
