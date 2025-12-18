import 'package:vayu/services/app_remote_config_service.dart';

/// AppText - Text Management System
///
/// This utility provides centralized text management:
/// - All texts come from backend (via AppRemoteConfig)
/// - Fallback to default texts if backend unavailable
/// - Prepared for multi-language support
/// - No hard-coded strings in UI
///
/// Usage:
/// ```dart
/// Text(AppText.get('app_name'))
/// Text(AppText.get('btn_upload', fallback: 'Upload'))
/// ```
class AppText {
  // Default fallback texts (used when backend config is unavailable)
  static const Map<String, String> _defaultTexts = {
    // Common texts
    'app_name': 'Vayu',
    'app_tagline': 'Create • Video • Earn',

    // Navigation
    'nav_yug': 'Yug',
    'nav_vayu': 'Vayu',
    'nav_profile': 'Profile',
    'nav_ads': 'Ads',

    // Buttons
    'btn_upload': 'Upload',
    'btn_create_ad': 'Create Advertisement',
    'btn_save': 'Save',
    'btn_cancel': 'Cancel',
    'btn_submit': 'Submit',
    'btn_visit_now': 'Visit Now',
    'btn_update_app': 'Update App',

    // Upload screen
    'upload_title': 'Upload & Create',
    'upload_select_media': 'Select Media',
    'upload_media_hint': 'Upload Video or Product Image',
    'upload_product_image_hint':
        'Product image selected. Please add your product/website URL in the External Link field.',

    // Ad creation
    'ad_create_title': 'Create Advertisement',
    'ad_budget_label': 'Daily Budget',
    'ad_duration_label': 'Campaign Duration',

    // Profile
    'profile_my_videos': 'My Videos',
    'profile_earnings': 'Earnings',
    'profile_settings': 'Settings',

    // Errors
    'error_network': 'Network error. Please check your connection.',
    'error_upload_failed': 'Upload failed. Please try again.',
    'error_invalid_url':
        'Please enter a valid URL starting with http:// or https://',

    // Success messages
    'success_upload': 'Upload successful!',
    'success_ad_created': 'Advertisement created successfully!',

    // Update messages
    'update_required':
        'A new version of the app is available. Please update to continue.',
    'update_recommended': 'A new version is available with exciting features!',
  };

  /// Get text by key
  ///
  /// [key] - Text key (e.g., 'app_name', 'btn_upload')
  /// [fallback] - Optional fallback text if key not found
  ///
  /// Returns text from backend config, or fallback, or key itself
  static String get(String key, {String? fallback}) {
    // Try to get from remote config first
    final configService = AppRemoteConfigService.instance;
    if (configService.isConfigAvailable) {
      final text = configService.getText(key, fallback: fallback);
      if (text != key) {
        // Text found in remote config
        return text;
      }
    }

    // Try default texts
    if (_defaultTexts.containsKey(key)) {
      return _defaultTexts[key]!;
    }

    // Use provided fallback or return key
    return fallback ?? key;
  }

  /// Get multiple texts at once
  ///
  /// Returns a map of key-value pairs
  static Map<String, String> getMultiple(List<String> keys) {
    final result = <String, String>{};
    for (final key in keys) {
      result[key] = get(key);
    }
    return result;
  }

  /// Check if a text key exists
  static bool hasKey(String key) {
    final configService = AppRemoteConfigService.instance;
    if (configService.isConfigAvailable) {
      final text = configService.getText(key);
      if (text != key) {
        return true;
      }
    }
    return _defaultTexts.containsKey(key);
  }

  /// Get all available text keys
  static List<String> getAllKeys() {
    final keys = <String>{};

    // Add keys from remote config
    final configService = AppRemoteConfigService.instance;
    if (configService.isConfigAvailable && configService.config != null) {
      keys.addAll(configService.config!.uiTexts.keys);
    }

    // Add default keys
    keys.addAll(_defaultTexts.keys);

    return keys.toList()..sort();
  }
}

/// Extension for easier text access in widgets
extension AppTextExtension on String {
  /// Get text using this string as key
  ///
  /// Usage:
  /// ```dart
  /// Text('app_name'.t)
  /// Text('btn_upload'.t(fallback: 'Upload'))
  /// ```
  String t({String? fallback}) => AppText.get(this, fallback: fallback);
}
