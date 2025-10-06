import 'dart:io';
import 'package:flutter/foundation.dart';

/// Secure configuration loader for Flutter
/// This class handles loading configuration from environment variables or secure storage
class SecureConfig {
  static const String _defaultBaseUrl = 'http://192.168.0.188:3000';

  // **NEW: Environment-based configuration**
  static String get baseUrl {
    // Try to get from environment variable first
    final envUrl = Platform.environment['SNEHAYOG_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }

    // Fallback to default for development
    if (kDebugMode) {
      return _defaultBaseUrl;
    }

    // For production, require environment variable
    throw Exception(
        'SNEHAYOG_BASE_URL environment variable is required for production');
  }

  // **NEW: Razorpay configuration from environment**
  static String get razorpayKeyId {
    final key = Platform.environment['RAZORPAY_KEY_ID'];
    if (key == null || key.isEmpty) {
      throw Exception('RAZORPAY_KEY_ID environment variable is required');
    }
    return key;
  }

  static String get razorpayKeySecret {
    final secret = Platform.environment['RAZORPAY_KEY_SECRET'];
    if (secret == null || secret.isEmpty) {
      throw Exception('RAZORPAY_KEY_SECRET environment variable is required');
    }
    return secret;
  }

  static String get razorpayWebhookSecret {
    final webhook = Platform.environment['RAZORPAY_WEBHOOK_SECRET'];
    if (webhook == null || webhook.isEmpty) {
      throw Exception(
          'RAZORPAY_WEBHOOK_SECRET environment variable is required');
    }
    return webhook;
  }

  // **NEW: Cloudinary configuration from environment**
  static String get cloudinaryCloudName {
    final cloudName = Platform.environment['CLOUDINARY_CLOUD_NAME'];
    if (cloudName == null || cloudName.isEmpty) {
      throw Exception('CLOUDINARY_CLOUD_NAME environment variable is required');
    }
    return cloudName;
  }

  static String get cloudinaryApiKey {
    final apiKey = Platform.environment['CLOUDINARY_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('CLOUDINARY_API_KEY environment variable is required');
    }
    return apiKey;
  }

  static String get cloudinaryApiSecret {
    final apiSecret = Platform.environment['CLOUDINARY_API_SECRET'];
    if (apiSecret == null || apiSecret.isEmpty) {
      throw Exception('CLOUDINARY_API_SECRET environment variable is required');
    }
    return apiSecret;
  }

  // **NEW: Feature flags from environment**
  static bool get enablePayments {
    return Platform.environment['ENABLE_PAYMENTS'] != 'false';
  }

  static bool get enableAnalytics {
    return Platform.environment['ENABLE_ANALYTICS'] != 'false';
  }

  static bool get enableUPIPayments {
    return Platform.environment['ENABLE_UPI_PAYMENTS'] != 'false';
  }

  // **NEW: Development helper methods**
  static bool get isDevelopment => kDebugMode;
  static bool get isProduction => !kDebugMode;

  // **NEW: Configuration validation**
  static void validateConfig() {
    try {
      // Test if required values can be accessed
      final baseUrlTest = baseUrl;
      final razorpayKeyIdTest = razorpayKeyId;
      final razorpayKeySecretTest = razorpayKeySecret;
      final razorpayWebhookSecretTest = razorpayWebhookSecret;
      final cloudinaryCloudNameTest = cloudinaryCloudName;
      final cloudinaryApiKeyTest = cloudinaryApiKey;
      final cloudinaryApiSecretTest = cloudinaryApiSecret;

      print('✅ Secure configuration validated successfully');
      print('🔍 Base URL: $baseUrlTest');
      print(
          '🔍 Razorpay Environment: ${razorpayKeyIdTest.startsWith('rzp_test_') ? 'TEST' : 'LIVE'}');
      print(
          '🔍 Features: Payments=$enablePayments, Analytics=$enableAnalytics, UPI=$enableUPIPayments');
    } catch (e) {
      print('❌ Configuration validation failed: $e');
      rethrow;
    }
  }

  // **NEW: Get configuration summary for debugging**
  static Map<String, dynamic> getConfigSummary() {
    return {
      'baseUrl': baseUrl,
      'razorpayKeyId': '${razorpayKeyId.substring(0, 10)}...',
      'razorpayEnvironment':
          razorpayKeyId.startsWith('rzp_test_') ? 'TEST' : 'LIVE',
      'cloudinaryCloudName': cloudinaryCloudName,
      'features': {
        'payments': enablePayments,
        'analytics': enableAnalytics,
        'upiPayments': enableUPIPayments,
      },
      'environment': isDevelopment ? 'development' : 'production',
    };
  }
}
