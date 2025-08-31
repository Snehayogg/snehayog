/// Optimized app configuration for better performance and smaller size
class AppConfig {
  static const bool _isDevelopment = true;

  // Backend API configuration
  static String get baseUrl {
    if (_isDevelopment) {
      return 'http://192.168.0.190:5001';
    } else {
      return 'http://192.168.0.190:5001';
    }
  }

  // **NEW: Fallback URLs for development**
  static const List<String> fallbackUrls = [
    'http://192.168.0.190:5001',
    'http://localhost:5001',
    'http://10.0.2.2:5001',
  ];

  // **NEW: Network timeout configurations**
  static const Duration authTimeout = Duration(seconds: 30);
  static const Duration apiTimeout = Duration(seconds: 45);
  static const Duration uploadTimeout = Duration(minutes: 10);

  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  // Ad configuration
  static const int maxAdBudget = 1000; // Maximum daily budget in dollars
  static const int minAdBudget = 1; // Minimum daily budget in dollars

  // **NEW: Fixed CPM for India market**
  static const double fixedCpm = 30.0;
  static const double bannerCpm = 10.0;

  static const double creatorRevenueShare = 0.80;
  static const double platformRevenueShare = 0.20;

  static const String razorpayKeyId = 'rzp_test_RBiIx4GqiPJgsc';
  static const String razorpayKeySecret = 'ZfJRn3obw6qAg3FkZuEN8CkD';
  static const String razorpayWebhookSecret = 'M_6mvVtUguwMwp3';

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

  // **NEW: Enhanced Ad Serving Logic**
  static const Map<String, Map<String, dynamic>> adTypeConfig = {
    'banner': {
      'cpm': 10.0, // ₹10 per 1000 impressions
      'maxFileSize': 5 * 1024 * 1024, // 5MB
      'supportedFormats': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      'displayFrequency': 2, // Every 2nd screen
      'priority': 1, // Lower priority than video ads
      'estimatedImpressionsPerDay': 50000, // Based on user base
    },
    'carousel': {
      'cpm': 30.0, // ₹30 per 1000 impressions
      'maxFileSize': 10 * 1024 * 1024, // 10MB
      'supportedFormats': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      'displayFrequency': 3, // Every 3rd screen
      'priority': 2, // Medium priority
      'estimatedImpressionsPerDay': 25000,
    },
    'video feed ad': {
      'cpm': 30.0,
      'maxFileSize': 100 * 1024 * 1024, // 100MB
      'supportedFormats': ['mp4', 'webm', 'avi', 'mov', 'mkv'],
      'displayFrequency': 4, // Every 4th screen
      'priority': 3, // Highest priority
      'estimatedImpressionsPerDay': 15000,
    },
  };

  // **NEW: Campaign Duration & Budget Logic**
  static const Map<String, int> campaignDurationLimits = {
    'min_days': 1,
    'max_days': 365,
    'recommended_min_days': 7,
    'recommended_max_days': 90,
  };

  // **NEW: Budget & Impression Management**
  static const Map<String, dynamic> budgetConfig = {
    'min_daily_budget': 100.0, // ₹100 minimum
    'max_daily_budget': 10000.0, // ₹10,000 maximum
    'budget_multiplier': 1.0, // For campaign duration
    'impression_buffer': 0.1, // 10% buffer for over-delivery
  };

  // **NEW: Ad Serving Algorithm Parameters**
  static const Map<String, dynamic> servingConfig = {
    'impression_frequency_cap': 3, // Max impressions per user per day
    'session_frequency_cap': 5, // Max impressions per user session
    'quality_score_threshold': 0.7, // Minimum quality score for ad display
    'relevance_threshold': 0.6, // Minimum relevance score
    'competition_window': 300, // 5 minutes between competing ads
  };

  // **NEW: Calculate campaign metrics**
  static Map<String, dynamic> calculateCampaignMetrics({
    required double dailyBudget,
    required int campaignDays,
    required String adType,
  }) {
    final config = adTypeConfig[adType] ?? adTypeConfig['banner']!;
    final cpm = config['cpm'] as double;
    final estimatedDailyImpressions =
        config['estimatedImpressionsPerDay'] as int;

    // Calculate total budget
    final totalBudget = dailyBudget * campaignDays;

    // Calculate expected impressions
    final expectedImpressions = (totalBudget / cpm) * 1000;

    // Calculate daily impressions
    final dailyImpressions = (expectedImpressions / campaignDays).round();

    // Calculate actual campaign duration based on budget
    final actualDuration =
        (expectedImpressions / estimatedDailyImpressions).ceil();

    return {
      'totalBudget': totalBudget,
      'expectedImpressions': expectedImpressions,
      'dailyImpressions': dailyImpressions,
      'estimatedDuration': actualDuration,
      'cpm': cpm,
      'dailyBudget': dailyBudget,
      'campaignDays': campaignDays,
    };
  }

  // **NEW: Validate campaign parameters**
  static Map<String, dynamic> validateCampaign({
    required double dailyBudget,
    required int campaignDays,
    required String adType,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    // Budget validation
    if (dailyBudget < budgetConfig['min_daily_budget']) {
      errors.add(
          'Daily budget must be at least ₹${budgetConfig['min_daily_budget']}');
    }
    if (dailyBudget > budgetConfig['max_daily_budget']) {
      errors.add(
          'Daily budget cannot exceed ₹${budgetConfig['max_daily_budget']}');
    }

    // Duration validation
    if (campaignDays < campaignDurationLimits['min_days']!) {
      errors.add(
          'Campaign must run for at least ${campaignDurationLimits['min_days']} day');
    }
    if (campaignDays > campaignDurationLimits['max_days']!) {
      errors.add(
          'Campaign cannot exceed ${campaignDurationLimits['max_days']} days');
    }

    // Recommendations
    if (campaignDays < campaignDurationLimits['recommended_min_days']!) {
      warnings.add(
          'Consider running for at least ${campaignDurationLimits['recommended_min_days']} days for better results');
    }
    if (campaignDays > campaignDurationLimits['recommended_max_days']!) {
      warnings.add(
          'Long campaigns may have diminishing returns. Consider shorter, focused campaigns');
    }

    // Calculate metrics
    final metrics = calculateCampaignMetrics(
      dailyBudget: dailyBudget,
      campaignDays: campaignDays,
      adType: adType,
    );

    return {
      'isValid': errors.isEmpty,
      'errors': errors,
      'warnings': warnings,
      'metrics': metrics,
    };
  }

  // Media upload configuration
  static const int maxImageSize = 5 * 1024 * 1024;
  static const int maxVideoSize = 100 * 1024 * 1024;

  // **NEW: Cloudinary Configuration for HLS Streaming**
  static const String cloudinaryCloudName =
      'dgq0hlygs'; // Replace with your actual cloud name
  static const String cloudinaryApiKey = '441141219573521';
  static const String cloudinaryApiSecret = 'mVM4MKP69IW0SGWHsS12aygq1uU';

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
