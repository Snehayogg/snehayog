/// Optimized app configuration for better performance and smaller size
class AppConfig {
  // Backend API configuration
  static const String baseUrl =
      'https://your-backend-url.com'; // Replace with your actual backend URL

  // Ad configuration
  static const int maxAdBudget = 1000; // Maximum daily budget in dollars
  static const int minAdBudget = 1; // Minimum daily budget in dollars

  // **NEW: Fixed CPM for India market**
  static const double fixedCpm = 30.0; // ₹30 fixed CPM (Cost Per Mille)

  // **NEW: Creator Revenue Model**
  static const double creatorRevenueShare = 0.80; // 80% to creator
  static const double platformRevenueShare = 0.20; // 20% to platform

  // **NEW: Cloudinary Configuration**
  static const String cloudinaryCloudName = 'your_cloud_name';
  static const String cloudinaryApiKey = 'your_api_key';
  static const String cloudinaryApiSecret = 'your_api_secret';
  static const String cloudinaryUploadPreset = 'snehayog_ads';

  // **NEW: Razorpay Configuration (India)**
  static const String razorpayKeyId = 'your_razorpay_key_id';
  static const String razorpayKeySecret = 'your_razorpay_key_secret';
  static const String razorpayWebhookSecret = 'your_webhook_secret';

  // **NEW: Payment Configuration**
  static const List<String> supportedPaymentMethods = [
    'UPI',
    'Cards',
    'NetBanking',
    'Wallets'
  ];

  // **NEW: Ad Serving Rules**
  static const int adInsertionFrequency =
      2; // Every alternate screen (2nd screen)
  static const int maxAdsPerSession = 10; // Maximum ads shown per user session

  // Media upload configuration
  static const int maxImageSize = 5 * 1024 * 1024; // 5MB
  static const int maxVideoSize = 100 * 1024 * 1024; // 100MB

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
}

/// Optimized network helper for better performance
class NetworkHelper {
  /// Get the appropriate server URL based on the environment
  static String getServerUrl() => AppConfig.baseUrl;

  /// Get the appropriate base URL for the current environment
  static String getBaseUrl() => AppConfig.baseUrl;
}
