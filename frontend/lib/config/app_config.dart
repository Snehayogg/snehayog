import 'package:http/http.dart' as http;

/// Optimized app configuration for better performance and smaller size
class AppConfig {
  // **MANUAL: Development mode control**
  static const bool _isDevelopment =
      false; // Set to true for local testing, false for production

  // **NEW: Smart URL selection with fallback**
  static String? _cachedBaseUrl;

  // Local development server (Wi‑Fi/LAN)
  // **IMPORTANT**: Update this IP to match your local machine's IP address
  // Find your IP: Windows: ipconfig | Linux/Mac: ifconfig or ip addr
  // Make sure your phone/emulator is on the same Wi‑Fi network
  static const String _localIpBaseUrl = 'http://192.168.0.198:5001';

  // Primary production endpoints
  static const String _customDomainUrl = 'https://api.snehayog.site';
  static const String _railwayUrl =
      'https://snehayog-production.up.railway.app';

  // **NEW: Clear cache method for development**
  static void clearCache() {
    print('🔄 AppConfig: Clearing cached URL');
    _cachedBaseUrl = null;
    if (_isDevelopment) {
      print(
          '🔧 AppConfig: Development mode - will use local server on next request');
    }
  }

  // Backend API configuration with smart fallback
  static String get baseUrl {
    // **FIXED: In development mode, ALWAYS use local server and ignore cache**
    if (_isDevelopment) {
      print(
          '🔧 AppConfig.baseUrl: DEVELOPMENT MODE - Using local server: $_localIpBaseUrl');
      print(
          '🔧 AppConfig.baseUrl: Make sure your backend is running on $_localIpBaseUrl');
      // Clear cache to ensure we always use local server in dev mode
      _cachedBaseUrl = _localIpBaseUrl;
      return _localIpBaseUrl;
    }

    // Production mode: use cache if available
    if (_cachedBaseUrl != null) {
      print('🔍 AppConfig: Using cached URL: $_cachedBaseUrl');
      return _cachedBaseUrl!;
    }

    print('🔍 AppConfig: No cached URL, defaulting to custom domain');
    _cachedBaseUrl = _customDomainUrl;
    return _cachedBaseUrl!;
  }

  // **UPDATED: Try custom domain first, then Railway, then local server**
  static Future<String> getBaseUrlWithFallback() async {
    // In explicit development mode, always use local server and skip remote checks
    if (_isDevelopment) {
      print('🔧 AppConfig.getBaseUrlWithFallback: DEVELOPMENT MODE');
      print('🔧 Forcing local server: $_localIpBaseUrl');
      print('🔧 Make sure your backend is running on $_localIpBaseUrl');
      _cachedBaseUrl = _localIpBaseUrl;
      return _localIpBaseUrl;
    }

    // **FIX: Use cache if available (don't clear it every time!)**
    if (_cachedBaseUrl != null) {
      return _cachedBaseUrl!;
    }

    print('🔍 AppConfig: Starting server connectivity check...');
    print('🔍 AppConfig: Order: Custom Domain → Railway → Local Server');

    // 1) Custom domain (snehayog.site) - FIRST PRIORITY
    try {
      print('🔍 AppConfig: [1/3] Testing custom domain: $_customDomainUrl...');
      final response = await http.get(
        Uri.parse('$_customDomainUrl/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        print('✅ AppConfig: Custom domain accessible at $_customDomainUrl');
        _cachedBaseUrl = _customDomainUrl;
        return _customDomainUrl;
      }
    } catch (e) {
      print('❌ AppConfig: Custom domain not accessible: $e');
    }

    print(
        '⚠️ AppConfig: Custom domain unreachable, trying Railway as fallback...');

    // 2) Railway URL - SECOND PRIORITY
    try {
      print('🔍 AppConfig: [2/3] Testing Railway server: $_railwayUrl...');
      final response = await http.get(
        Uri.parse('$_railwayUrl/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        print('✅ AppConfig: Railway server accessible at $_railwayUrl');
        _cachedBaseUrl = _railwayUrl;
        return _railwayUrl;
      }
    } catch (e) {
      print('❌ AppConfig: Railway server not accessible: $e');
    }

    print(
        '⚠️ AppConfig: Railway unreachable, trying local server as fallback...');

    // 3) Local IP server (172.20.10.2:5001) - THIRD PRIORITY
    try {
      print('🔍 AppConfig: [3/3] Testing local IP server: $_localIpBaseUrl...');
      final response = await http.get(
        Uri.parse('$_localIpBaseUrl/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        print('✅ AppConfig: Local IP server accessible at $_localIpBaseUrl');
        _cachedBaseUrl = _localIpBaseUrl;
        return _localIpBaseUrl;
      }
    } catch (e) {
      print('❌ AppConfig: Local IP server not accessible: $e');
    }

    // All servers failed - use default custom domain as last resort
    print(
        '⚠️ AppConfig: All servers unreachable, using default custom domain as last resort');
    _cachedBaseUrl = _customDomainUrl;
    return _cachedBaseUrl!;
  }

  // **UPDATED: Check server connectivity - Custom Domain → Railway → Local Server**
  static Future<String> checkAndUpdateServerUrl() async {
    // In explicit development mode, always use local server
    if (_isDevelopment) {
      print('🔧 AppConfig.checkAndUpdateServerUrl: DEVELOPMENT MODE');
      print(
          '🔧 Skipping connectivity check, forcing local server: $_localIpBaseUrl');
      print('🔧 Make sure your backend is running on $_localIpBaseUrl');
      _cachedBaseUrl = _localIpBaseUrl;
      return _localIpBaseUrl;
    }

    print('🔍 AppConfig: Checking server connectivity...');
    print('🔍 AppConfig: Order: Custom Domain → Railway → Local Server');

    try {
      print('🔍 AppConfig: [1/3] Testing custom domain: $_customDomainUrl...');
      final response = await http.get(
        Uri.parse('$_customDomainUrl/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        print('✅ AppConfig: Custom domain is accessible at $_customDomainUrl');
        _cachedBaseUrl = _customDomainUrl;
        return _customDomainUrl;
      }
    } catch (e) {
      print('❌ AppConfig: Custom domain not accessible: $e');
    }

    print(
        '⚠️ AppConfig: Custom domain unreachable, trying Railway as fallback...');

    // 2) Railway URL - SECOND PRIORITY
    try {
      print('🔍 AppConfig: [2/3] Testing Railway server: $_railwayUrl...');
      final response = await http.get(
        Uri.parse('$_railwayUrl/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        print('✅ AppConfig: Railway server is accessible at $_railwayUrl');
        _cachedBaseUrl = _railwayUrl;
        return _railwayUrl;
      }
    } catch (e) {
      print('❌ AppConfig: Railway server not accessible: $e');
    }

    print(
        '⚠️ AppConfig: Railway unreachable, trying local server as fallback...');

    // 3) Local IP server (172.20.10.2:5001) - THIRD PRIORITY
    try {
      print('🔍 AppConfig: [3/3] Testing local IP server: $_localIpBaseUrl...');
      final response = await http.get(
        Uri.parse('$_localIpBaseUrl/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        print('✅ AppConfig: Local IP server is accessible at $_localIpBaseUrl');
        _cachedBaseUrl = _localIpBaseUrl;
        return _localIpBaseUrl;
      }
    } catch (e) {
      print('❌ AppConfig: Local IP server not accessible: $e');
    }

    // If all servers fail, return default
    print(
        '⚠️ AppConfig: All servers failed, using default custom domain as last resort');
    _cachedBaseUrl = _customDomainUrl;
    return _cachedBaseUrl!;
  }

  // **NEW: Reset cached URL (useful for retry scenarios)**
  static void resetCachedUrl() {
    _cachedBaseUrl = null;
    print('🔄 AppConfig: Cached URL reset, will recheck on next request');
  }

  // **NEW: Fallback URLs - custom domain first for production**
  static const List<String> fallbackUrls = [
    _customDomainUrl,
    _railwayUrl,
  ];

  // **NEW: Network timeout configurations**
  static const Duration authTimeout = Duration(seconds: 30);
  static const Duration apiTimeout = Duration(seconds: 30);
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
  // Note: API credentials should be fetched from backend for security
  static const String cloudinaryCloudName = 'dkklingts';

  // SECURITY WARNING: Never hardcode API secrets in frontend code!
  // These should be fetched from backend API endpoints
  static const String cloudinaryApiKey = ''; // Empty - fetch from backend
  static const String cloudinaryApiSecret =
      ''; // Empty - never store in frontend

  // Cloudinary streaming profiles - Cost optimized (720p max)
  static const Map<String, Map<String, dynamic>> streamingProfiles = {
    'portrait_reels': {
      'name': 'Portrait Reels',
      'aspect_ratio': '9:16',
      'quality_levels': [
        {
          'resolution': '720x1280',
          'bitrate': '1.8 Mbps',
          'profile': 'HD'
        }, // 720p as highest
        {'resolution': '480x854', 'bitrate': '0.9 Mbps', 'profile': 'SD'},
        {'resolution': '360x640', 'bitrate': '0.6 Mbps', 'profile': 'SD'},
        {'resolution': '240x427', 'bitrate': '0.3 Mbps', 'profile': 'LOW'},
      ],
      'segment_duration': 2,
      'keyframe_interval': 2,
      'optimized_for': 'Mobile Scrolling - Cost Optimized'
    },
    'landscape_standard': {
      'name': 'Landscape Standard',
      'aspect_ratio': '16:9',
      'quality_levels': [
        {
          'resolution': '1280x720',
          'bitrate': '2.0 Mbps',
          'profile': 'HD'
        }, // 720p as highest
        {'resolution': '854x480', 'bitrate': '1.0 Mbps', 'profile': 'SD'},
        {'resolution': '640x360', 'bitrate': '0.5 Mbps', 'profile': 'LOW'},
      ],
      'segment_duration': 2,
      'keyframe_interval': 2,
      'optimized_for': 'Standard Video - Cost Optimized'
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

  // **NEW: AdMob Configuration**
  // Delegates to AdMobConfig for modular approach
  static String? get adMobBannerAdUnitId {
    // Import and use AdMobConfig
    // This getter provides backward compatibility
    try {
      // Dynamic import to avoid circular dependencies
      // AdMobConfig will be imported where needed
      return null; // Will be resolved by AdMobConfig
    } catch (e) {
      return null;
    }
  }
}

/// Optimized network helper for better performance
class NetworkHelper {
  /// Get the appropriate server URL based on the environment
  static String getServerUrl() => AppConfig.baseUrl;

  /// Get the appropriate base URL for the current environment
  static String getBaseUrl() => AppConfig.baseUrl;

  /// Get base URL with automatic Railway first, local fallback (async version)
  static Future<String> getBaseUrlAsync() => AppConfig.getBaseUrlWithFallback();

  /// Get base URL with fallback: Custom Domain → Railway → Local Server
  static Future<String> getBaseUrlWithFallback() =>
      AppConfig.getBaseUrlWithFallback();

  /// API endpoints
  static String get apiBaseUrl => '${AppConfig.baseUrl}/api';
  static String get healthEndpoint =>
      '${AppConfig.baseUrl}/api/health'; // Consistent API health endpoint
  static String get videosEndpoint => '$apiBaseUrl/videos';
  static String get authEndpoint => '$apiBaseUrl/auth';
  static String get usersEndpoint => '$apiBaseUrl/users';

  /// Network timeout configurations - Increased for better remote connectivity
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 5);
  static const Duration shortTimeout = Duration(seconds: 30);

  /// Retry configurations - Enhanced for better reliability
  static const int defaultMaxRetries = 3;
  static const Duration defaultRetryDelay = Duration(seconds: 2);

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

  /// **NEW: Check if Railway server is accessible**
  static Future<bool> isRailwayAccessible() async {
    try {
      print('🔍 NetworkHelper: Checking Railway server accessibility...');
      final response = await http.get(
        Uri.parse('${AppConfig._railwayUrl}/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      final isAccessible = response.statusCode == 200;
      print('🔍 NetworkHelper: Railway server accessible: $isAccessible');
      return isAccessible;
    } catch (e) {
      print('❌ NetworkHelper: Railway server not accessible: $e');
      return false;
    }
  }

  /// **NEW: Check if custom domain is accessible**
  static Future<bool> isCustomDomainAccessible() async {
    try {
      print('🔍 NetworkHelper: Checking custom domain accessibility...');
      final response = await http.get(
        Uri.parse('${AppConfig._customDomainUrl}/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      final isAccessible = response.statusCode == 200;
      print('🔍 NetworkHelper: Custom domain accessible: $isAccessible');
      return isAccessible;
    } catch (e) {
      print('❌ NetworkHelper: Custom domain not accessible: $e');
      return false;
    }
  }

  /// **UPDATED: Get best available server URL - Custom Domain → Railway → Local Server**
  static Future<String> getBestServerUrl() async {
    // Use AppConfig's getBaseUrlWithFallback which prioritizes: Custom Domain → Railway → Local Server
    return await AppConfig.getBaseUrlWithFallback();
  }
}
