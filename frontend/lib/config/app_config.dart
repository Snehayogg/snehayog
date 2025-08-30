/// Optimized app configuration for better performance and smaller size
class AppConfig {
  static const bool _isDevelopment = true;

  // Backend API configuration
  static String get baseUrl {
    if (_isDevelopment) {
      // Development: Use local network IP for physical device testing
      return 'http://192.168.0.190:5001';
    } else {
      // Production: Use your local network IP for physical device testing
      return 'http://192.168.0.190:5001';
    }
  }

  // **NEW: Fallback URLs for development**
  static const List<String> fallbackUrls = [
    'http://192.168.0.190:5001', // **PRIORITY: Your local network IP for physical devices**
    'http://localhost:5001',
    'http://10.0.2.2:5001', // Android emulator
  ];

  // **NEW: Network timeout configurations**
  static const Duration authTimeout = Duration(seconds: 10);
  static const Duration apiTimeout = Duration(seconds: 15);
  static const Duration uploadTimeout = Duration(minutes: 5);

  // Ad configuration
  static const int maxAdBudget = 1000; // Maximum daily budget in dollars
  static const int minAdBudget = 1; // Minimum daily budget in dollars

  // **NEW: Fixed CPM for India market**
  static const double fixedCpm =
      30.0; // ₹30 fixed CPM (Cost Per Mille) for carousel and video feed ads
  static const double bannerCpm =
      10.0; // ₹10 fixed CPM (Cost Per Mille) for banner ads

  // **NEW: Creator Revenue Model**
  static const double creatorRevenueShare = 0.80; // 80% to creator
  static const double platformRevenueShare = 0.20; // 20% to platform

  // **NEW: Razorpay Configuration (India)**
  static const String razorpayKeyId =
      'rzp_test_YOUR_TEST_KEY_ID'; // Replace with your test key
  static const String razorpayKeySecret =
      'YOUR_TEST_SECRET_KEY'; // Replace with your test secret
  static const String razorpayWebhookSecret =
      'YOUR_WEBHOOK_SECRET'; // Replace with your webhook secret

  // **NEW: Supported Payment Methods for Razorpay**
  static const List<String> supportedPaymentMethods = [
    'card',
    'netbanking',
    'wallet',
    'upi',
    'paytm',
    'phonepe',
    'amazonpay',
    'googlepay',
    'applepay',
  ];

  // **NEW: Ad Serving Rules**
  static const int adInsertionFrequency =
      2; // Every alternate screen (2nd screen)
  static const int maxAdsPerSession = 10; // Maximum ads shown per user session

  // Media upload configuration
  static const int maxImageSize = 5 * 1024 * 1024; // 5MB
  static const int maxVideoSize = 100 * 1024 * 1024; // 100MB

  // **NEW: Cloudinary Configuration for HLS Streaming**
  static const String cloudinaryCloudName =
      'dgq0hlygs'; // Replace with your actual cloud name
  static const String cloudinaryApiKey =
      '441141219573521'; // Replace with your actual API key
  static const String cloudinaryApiSecret =
      'mVM4MKP69IW0SGWHsS12aygq1uU'; // Replace with your actual API secret

  // Cloudinary streaming profiles
  static const Map<String, Map<String, dynamic>> streamingProfiles = {
    'portrait_reels': {
      'name': 'Portrait Reels',
      'aspect_ratio': '9:16',
      'quality_levels': [
        {'resolution': '1080x1920', 'bitrate': '3.5 Mbps', 'profile': 'HD'},
        {'resolution': '720x1280', 'bitrate': '1.8 Mbps', 'profile': 'HD'},
        {'resolution': '480x854', 'bitrate': '0.9 Mbps', 'profile': 'SD'},
        {'resolution': '360x640', 'bitrate': '0.6 Mbps', 'profile': 'SD'},
      ],
      'segment_duration': 2,
      'keyframe_interval': 2,
      'optimized_for': 'Mobile Scrolling'
    },
    'landscape_standard': {
      'name': 'Landscape Standard',
      'aspect_ratio': '16:9',
      'quality_levels': [
        {'resolution': '1920x1080', 'bitrate': '4.0 Mbps', 'profile': 'HD'},
        {'resolution': '1280x720', 'bitrate': '2.0 Mbps', 'profile': 'HD'},
        {'resolution': '854x480', 'bitrate': '1.0 Mbps', 'profile': 'SD'},
      ],
      'segment_duration': 2,
      'keyframe_interval': 2,
      'optimized_for': 'Standard Video'
    }
  };

  // HLS streaming configuration
  static const Map<String, dynamic> hlsConfig = {
    'segment_duration': 2, // 2 seconds per segment
    'keyframe_interval': 60, // 2 seconds at 30fps
    'abr_enabled': true, // Adaptive Bitrate enabled
    'buffer_size': 10, // 10 seconds buffer
    'hls_version': '3',
    'compatibility': 'modern'
  };

  // Ad types supported
  static const List<String> supportedAdTypes = [
    'banner',
    'interstitial',
    'rewarded',
    'native'
  ];

  // Ad statuses
  static const List<String> adStatuses = [
    'draft',
    'active',
    'paused',
    'completed'
  ];

  // Target audience options
  static const List<String> targetAudienceOptions = [
    'all',
    'youth',
    'professionals',
    'students',
    'parents',
    'seniors'
  ];

  // **NEW: Helper methods for revenue calculations**
  static double calculateCreatorRevenue(double adSpend) {
    return adSpend * creatorRevenueShare;
  }

  static double calculatePlatformRevenue(double adSpend) {
    return adSpend * platformRevenueShare;
  }

  static double calculateCpmFromBudget(double budget, int impressions) {
    if (impressions <= 0) return 0.0;
    return (budget / impressions) * 1000;
  }

  static int calculateImpressionsFromBudget(double budget) {
    return (budget / fixedCpm * 1000).round();
  }

  static int calculateImpressionsFromBudgetWithCpm(double budget, double cpm) {
    return (budget / cpm * 1000).round();
  }

  // **NEW: Check if backend is accessible**
  // Note: This method requires http package import in the file where it's used
  // static Future<bool> isBackendAccessible() async {
  //   try {
  //     final response = await http.get(
  //       Uri.parse('$baseUrl/api/health'),
  //     ).timeout(const Duration(seconds: 5));
  //     return response.statusCode == 200;
  //   } catch (e) {
  //     return false;
  //   }
  // }
}

/// Optimized network helper for better performance
class NetworkHelper {
  /// Get the appropriate server URL based on the environment
  static String getServerUrl() => AppConfig.baseUrl;

  /// Get the appropriate base URL for the current environment
  static String getBaseUrl() => AppConfig.baseUrl;

  /// API endpoints
  static String get apiBaseUrl => '${AppConfig.baseUrl}/api';
  static String get healthEndpoint =>
      '${AppConfig.baseUrl}/health'; // Use correct endpoint
  static String get videosEndpoint => '$apiBaseUrl/videos';
  static String get authEndpoint => '$apiBaseUrl/auth';
  static String get usersEndpoint => '$apiBaseUrl/users';

  /// Network timeout configurations
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const Duration uploadTimeout = Duration(minutes: 5);
  static const Duration shortTimeout = Duration(seconds: 5);

  /// Retry configurations
  static const int defaultMaxRetries = 2;
  static const Duration defaultRetryDelay = Duration(seconds: 1);

  /// File size limits
  static const int maxVideoFileSize = 100 * 1024 * 1024; // 100MB
  static const int maxImageFileSize = 5 * 1024 * 1024; // 5MB

  /// Valid file extensions
  static const List<String> validVideoExtensions = [
    'mp4',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm'
  ];

  static const List<String> validImageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp'
  ];

  /// Validation methods
  static bool isValidVideoExtension(String extension) {
    return validVideoExtensions.contains(extension.toLowerCase());
  }

  static bool isValidImageExtension(String extension) {
    return validImageExtensions.contains(extension.toLowerCase());
  }

  /// File size formatting
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Check if file size is within limits
  static bool isFileSizeValid(int fileSize, {bool isVideo = true}) {
    final maxSize = isVideo ? maxVideoFileSize : maxImageFileSize;
    return fileSize <= maxSize;
  }
}
