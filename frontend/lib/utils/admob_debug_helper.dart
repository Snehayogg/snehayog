import 'package:flutter/material.dart';
import 'package:snehayog/services/admob_service.dart';

/// Helper class for debugging AdMob issues
class AdMobDebugHelper {
  static void showDebugInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AdMob Debug Info'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoSection('Configuration', [
                'Test Ad Unit ID: ca-app-pub-3940256099942544/6300978111',
                'Service Initialized: ${AdMobService().isInitialized}',
                'Active Ads: ${AdMobService().activeAdCount}',
              ]),
              const SizedBox(height: 16),
              _buildInfoSection('Service Status', [
                'Initialized: ${AdMobService().isInitialized}',
                'Active Ads: ${AdMobService().activeAdCount}',
              ]),
              const SizedBox(height: 16),
              _buildInfoSection('Common Issues & Solutions', [
                '1. Check internet connection',
                '2. Verify AdMob app ID in manifest files',
                '3. Ensure ad unit ID is correct',
                '4. Check if account is approved',
                '5. Wait 24-48 hours after account creation',
                '6. Use test ads during development',
              ]),
              const SizedBox(height: 16),
              _buildInfoSection('Next Steps', [
                '1. Run app and check console logs',
                '2. Look for "MobileAds: Use RequestConfiguration.Builder.setTestDeviceIds()" message',
                '3. Copy your device ID from logs',
                '4. Test with test ads first',
                '5. Switch to production ads when ready',
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _printDebugInfo();
            },
            child: const Text('Print to Console'),
          ),
        ],
      ),
    );
  }

  static Widget _buildInfoSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4),
              child: Text(
                '• $item',
                style: const TextStyle(fontSize: 14),
              ),
            )),
      ],
    );
  }

  static void _printDebugInfo() {
    print('\n🔧 AdMob Debug Information:');
    print('================================');
    print('Configuration:');
    print('  Test Ad Unit ID: ca-app-pub-3940256099942544/6300978111');
    print('  Service Initialized: ${AdMobService().isInitialized}');
    print('  Active Ads: ${AdMobService().activeAdCount}');
    print('================================');
    print('Service Status:');
    print('  Initialized: ${AdMobService().isInitialized}');
    print('  Active Ads: ${AdMobService().activeAdCount}');
    print('================================');
    print('To get your test device ID:');
    print('1. Run the app');
    print(
        '2. Check console for: "MobileAds: Use RequestConfiguration.Builder.setTestDeviceIds() to get test ads on this device."');
    print('3. Test with test ads first');
    print('================================\n');
  }

  /// Check if AdMob is properly configured
  static bool isAdMobConfigured() {
    return AdMobService().isInitialized;
  }

  /// Get configuration issues
  static List<String> getConfigurationIssues() {
    final issues = <String>[];

    if (!AdMobService().isInitialized) {
      issues.add('AdMob service is not initialized');
    }

    if (AdMobService().activeAdCount == 0) {
      issues.add('No active ads found');
    }

    return issues;
  }
}
