import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/ad_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/cloudinary_service.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/core/managers/smart_cache_manager.dart';
import 'package:snehayog/services/active_ads_service.dart';
import 'package:snehayog/services/ad_refresh_notifier.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  static String get baseUrl => AppConfig.baseUrl;
  final AuthService _authService = AuthService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  // final RazorpayService _razorpayService = RazorpayService();  // Temporarily commented
  final SmartCacheManager _cacheManager = SmartCacheManager();
  final ActiveAdsService _activeAdsService = ActiveAdsService();
  final AdRefreshNotifier _adRefreshNotifier = AdRefreshNotifier();

  // Create a new ad
  Future<AdModel> createAd({
    required String title,
    required String description,
    String? imageUrl,
    String? videoUrl,
    String? link,
    required String adType,
    required int budget,
    required String targetAudience,
    required List<String> targetKeywords,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // **NEW: Calculate impressions based on ad type CPM**
      final cpm = adType == 'banner' ? AppConfig.bannerCpm : AppConfig.fixedCpm;
      final impressions = AppConfig.calculateImpressionsFromBudgetWithCpm(
        budget / 100.0,
        cpm,
      );

      // **NEW: Calculate revenue split**
      // final revenueSplit =
      //     _razorpayService.calculateRevenueSplit(budget / 100.0);  // Temporarily commented

      final response = await http.post(
        Uri.parse('$baseUrl/api/ads'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({
          'title': title,
          'description': description,
          'imageUrl': imageUrl,
          'videoUrl': videoUrl,
          'link': link,
          'adType': adType == 'carousel'
              ? 'carousel'
              : adType == 'video feed'
                  ? 'video feed ad'
                  : adType, // **FIX: Correct adType format**
          'budget': budget,
          'targetAudience': targetAudience,
          'targetKeywords': targetKeywords,
          'startDate': startDate?.toIso8601String(),
          'endDate': endDate?.toIso8601String(),
          'uploaderId': userData['googleId'] ?? userData['id'],
          'uploaderName': userData['name'],
          'uploaderProfilePic': userData['profilePic'],
          'estimatedImpressions': impressions,
          'fixedCpm': cpm,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        return AdModel.fromJson(data);
      } else {
        throw Exception('Failed to create ad: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating ad: $e');
    }
  }

  // **NEW: Create ad with payment processing**
  Future<Map<String, dynamic>> createAdWithPayment({
    required String title,
    required String description,
    String? imageUrl,
    String? videoUrl,
    String? link,
    required String adType,
    required double budget,
    required String targetAudience,
    required List<String> targetKeywords,
    DateTime? startDate,
    DateTime? endDate,
    int? minAge,
    int? maxAge,
    String? gender,
    List<String>? locations,
    List<String>? interests,
    List<String>? platforms,
    String? deviceType,
    String? optimizationGoal,
    int? frequencyCap,
    String? timeZone,
    Map<String, bool>? dayParting,
    // **NEW: Support multiple image URLs for carousel ads**
    List<String>? imageUrls,
  }) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final cpm = adType == 'banner' ? AppConfig.bannerCpm : AppConfig.fixedCpm;
      final impressions = AppConfig.calculateImpressionsFromBudgetWithCpm(
        budget,
        cpm,
      );

      print('🔍 AdService: Creating ad with payment...');
      print(
        '🔍 AdService: Budget: ₹$budget, Ad Type: $adType, CPM: ₹$cpm, Estimated impressions: $impressions',
      );

      String backendAdType = adType;
      if (adType == 'carousel') {
        backendAdType = 'carousel';
      } else if (adType == 'video feed') {
        backendAdType = 'video feed ad';
      }

      final requestData = {
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'videoUrl': videoUrl,
        'link': link,
        'adType': backendAdType, // **FIX: Use corrected adType**
        'budget': budget.toDouble(),
        'targetAudience': targetAudience,
        'uploaderId': userData['googleId'] ?? userData['id'],
        'uploaderName': userData['name'],
        'uploaderProfilePic': userData['profilePic'],
        'estimatedImpressions': impressions,
        'fixedCpm': cpm,
        'duration': startDate != null && endDate != null
            ? endDate.difference(startDate).inDays + 1
            : 1,
      };

      // **NEW: Add imageUrls for carousel ads**
      if (imageUrls != null && imageUrls.isNotEmpty && adType == 'carousel') {
        requestData['imageUrls'] = imageUrls;
        print('🔍 AdService: Sending ${imageUrls.length} carousel image URLs');
      }

      // **NEW: Validate required fields before sending**
      if (title.isEmpty ||
          description.isEmpty ||
          adType.isEmpty ||
          budget <= 0) {
        throw Exception(
            'Required fields validation failed: title=$title, description=$description, adType=$adType, budget=$budget');
      }

      final uploaderId = userData['googleId'] ?? userData['id'];
      if (uploaderId == null || uploaderId.toString().isEmpty) {
        throw Exception('Uploader ID is missing or empty: $uploaderId');
      }

      // **NEW: Add uploaderId to request data**
      requestData['uploaderId'] = uploaderId;
      requestData['targetKeywords'] = targetKeywords;
      requestData['startDate'] = startDate?.toIso8601String();
      requestData['endDate'] = endDate?.toIso8601String();

      // **NEW: Add advanced targeting data as individual parameters**
      if (minAge != null) requestData['minAge'] = minAge;
      if (maxAge != null) requestData['maxAge'] = maxAge;
      if (gender != null) requestData['gender'] = gender;
      if (locations != null && locations.isNotEmpty) {
        requestData['locations'] = locations;
      }
      if (interests != null && interests.isNotEmpty) {
        requestData['interests'] = interests;
      }
      if (platforms != null && platforms.isNotEmpty) {
        requestData['platforms'] = platforms;
      }
      requestData['deviceType'] = deviceType ?? 'all';

      // **NEW: Add additional campaign settings**
      if (optimizationGoal != null) {
        requestData['optimizationGoal'] = optimizationGoal;
      }
      if (frequencyCap != null) {
        requestData['frequencyCap'] = frequencyCap;
      }
      if (timeZone != null) {
        requestData['timeZone'] = timeZone;
      }
      if (dayParting != null && dayParting.isNotEmpty) {
        requestData['dayParting'] = dayParting;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/ads/create-with-payment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode(requestData),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ AdService: Ad created successfully with payment required');

        return {
          'success': true,
          'ad': data['ad'],
          'invoice': data['invoice'],
          'message': data['message'],
        };
      } else {
        // **NEW: Enhanced error logging**
        print(
            '❌ AdService: Backend returned error status: ${response.statusCode}');
        print('❌ AdService: Response body: ${response.body}');

        final error = json.decode(response.body);
        print('❌ AdService: Parsed error: $error');

        throw Exception(error['error'] ?? 'Failed to create ad');
      }
    } catch (e) {
      print('❌ AdService: Error creating ad with payment: $e');
      throw Exception('Error creating ad: $e');
    }
  }

  // **NEW: Process payment after successful Razorpay payment**
  Future<Map<String, dynamic>> processPayment({
    required String orderId,
    required String paymentId,
    required String signature,
    required String adId,
  }) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      print('🔍 AdService: Processing payment...');
      print('🔍 AdService: Order ID: $orderId, Payment ID: $paymentId');

      final response = await http.post(
        Uri.parse('$baseUrl/api/ads/process-payment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({
          'orderId': orderId,
          'paymentId': paymentId,
          'signature': signature,
          'adId': adId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ AdService: Payment processed successfully');

        return {
          'success': true,
          'ad': data['ad'],
          'invoice': data['invoice'],
          'message': data['message'],
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to process payment');
      }
    } catch (e) {
      print('❌ AdService: Error processing payment: $e');
      throw Exception('Error processing payment: $e');
    }
  }

  // **NEW: Process payment and activate ad**
  Future<AdModel> processPaymentAndActivateAd({
    required String adId,
    required String paymentId,
    required String orderId,
  }) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // Verify payment with Razorpay
      // final paymentDetails =
      //     await _razorpayService.getPaymentDetails(paymentId); // Temporarily commented

      // if (paymentDetails['status'] != 'captured') {
      //   throw Exception('Payment not completed');
      // }

      // Update ad status to active
      final updatedAd = await updateAdStatus(adId, 'active');

      // **NEW: Record payment and revenue split**
      // await _recordPaymentAndRevenue(adId, paymentDetails); // Temporarily commented

      return updatedAd;
    } catch (e) {
      throw Exception('Error processing payment: $e');
    }
  }

  // **NEW: Record payment and calculate revenue split**
  Future<void> _recordPaymentAndRevenue(
    String adId,
    Map<String, dynamic> paymentDetails,
  ) async {
    try {
      final amount = paymentDetails['amount'] / 100.0; // Convert from paise
      // final revenueSplit = _razorpayService.calculateRevenueSplit(amount); // Temporarily commented

      await http.post(
        Uri.parse('$baseUrl/api/ads/$adId/payment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer ${(await _authService.getUserData())?['token']}',
        },
        body: json.encode({
          'paymentId': paymentDetails['id'],
          'amount': amount,
          'currency': paymentDetails['currency'],
          'paymentMethod': paymentDetails['method'],
          // 'creatorRevenue': revenueSplit['creator'],
          // 'platformRevenue': revenueSplit['platform'],
          'status': 'completed',
        }),
      );
    } catch (e) {
      print('Error recording payment: $e');
    }
  }

  // Get user's ads
  Future<List<AdModel>> getUserAds() async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // **FIXED: Use the correct user ID format that matches backend expectations**
      // The backend expects req.user.id from JWT token, so we need to use the same ID format
      String userId;
      if (userData['id'] != null) {
        userId = userData['id'].toString();
      } else if (userData['googleId'] != null) {
        userId = userData['googleId'].toString();
      } else {
        throw Exception('User ID not found in user data');
      }

      print('🔍 AdService: Fetching ads for user ID: $userId');
      print('🔍 AdService: User data keys: ${userData.keys.toList()}');

      final response = await http.get(
        Uri.parse('$baseUrl/api/ads/user/$userId'),
        headers: {'Authorization': 'Bearer ${userData['token']}'},
      );

      print('🔍 AdService: Response status: ${response.statusCode}');
      print('🔍 AdService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final ads = data.map((json) => AdModel.fromJson(json)).toList();
        print('✅ AdService: Successfully fetched ${ads.length} ads');
        return ads;
      } else {
        print(
          '❌ AdService: Failed to fetch ads - Status: ${response.statusCode}, Body: ${response.body}',
        );
        throw Exception('Failed to fetch ads: ${response.body}');
      }
    } catch (e) {
      print('❌ AdService: Error in getUserAds: $e');
      throw Exception('Error fetching ads: $e');
    }
  }

  // Get all active ads (for display)
  Future<List<AdModel>> getActiveAds() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/ads/active'));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => AdModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch active ads: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching active ads: $e');
    }
  }

  // **NEW: Get ads for video feed (with insertion logic)**
  Future<List<AdModel>> getAdsForVideoFeed({
    required int currentIndex,
    required int totalVideos,
  }) async {
    try {
      final activeAds = await getActiveAds();
      final adsForFeed = <AdModel>[];

      // **NEW: Insert ads every alternate screen as per requirements**
      for (int i = 0; i < totalVideos; i++) {
        if ((i + 1) % AppConfig.adInsertionFrequency == 0) {
          // Insert ad at this position
          final adIndex =
              (i ~/ AppConfig.adInsertionFrequency) % activeAds.length;
          if (adIndex < activeAds.length) {
            adsForFeed.add(activeAds[adIndex]);
          }
        }
      }

      return adsForFeed;
    } catch (e) {
      throw Exception('Error getting ads for video feed: $e');
    }
  }

  // Update ad status
  Future<AdModel> updateAdStatus(String adId, String status) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.patch(
        Uri.parse('$baseUrl/api/ads/$adId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({'status': status}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return AdModel.fromJson(data);
      } else {
        throw Exception('Failed to update ad status: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating ad status: $e');
    }
  }

  // Delete ad
  Future<bool> deleteAd(String adId) async {
    try {
      print('🗑️ AdService: Starting delete for ad ID: $adId');

      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      print('🔍 AdService: User authenticated, making delete request...');
      print('🔍 AdService: Delete URL: $baseUrl/api/ads/$adId');

      final response = await http.delete(
        Uri.parse('$baseUrl/api/ads/$adId'),
        headers: {'Authorization': 'Bearer ${userData['token']}'},
      );

      print('🔍 AdService: Delete response status: ${response.statusCode}');
      print('🔍 AdService: Delete response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        print('✅ AdService: Ad deleted successfully');

        // **NEW: Clear ad cache after successful deletion**
        await _clearAdCache();
        print('🧹 AdService: Cleared ad cache after deletion');

        // **NEW: Clear ActiveAdsService cache**
        await _activeAdsService.clearAdsCache();
        print('🧹 AdService: Cleared ActiveAdsService cache');

        // **NEW: Notify video feed to refresh ads**
        await _notifyVideoFeedRefresh();
        print('📢 AdService: Notified video feed to refresh ads');

        return true;
      } else {
        print('❌ AdService: Delete failed with status ${response.statusCode}');
        throw Exception('Delete failed: ${response.body}');
      }
    } catch (e) {
      print('❌ AdService: Delete error: $e');
      throw Exception('Error deleting ad: $e');
    }
  }

  // **NEW: Get ad analytics**
  Future<Map<String, dynamic>> getAdAnalytics(String adId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.get(
        Uri.parse(
          '$baseUrl/api/ads/analytics/$adId?userId=${userData['googleId'] ?? userData['id']}',
        ),
        headers: {'Authorization': 'Bearer ${userData['token']}'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to get analytics');
      }
    } catch (e) {
      throw Exception('Error getting analytics: $e');
    }
  }

  // **NEW: Track ad impression**
  Future<void> trackAdImpression(
    String adId,
    String userId,
    String platform,
    String location,
  ) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return;

      await http.post(
        Uri.parse('$baseUrl/api/ads/track-impression/$adId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({
          'userId': userId,
          'platform': platform,
          'location': location,
        }),
      );
    } catch (e) {
      print('Error tracking impression: $e');
    }
  }

  // **NEW: Track ad click**
  Future<void> trackAdClick(
    String adId,
    String userId,
    String platform,
    String location,
  ) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return;

      await http.post(
        Uri.parse('$baseUrl/api/ads/track-click/$adId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({
          'userId': userId,
          'platform': platform,
          'location': location,
        }),
      );
    } catch (e) {
      print('Error tracking click: $e');
    }
  }

  // **NEW: Upload ad media using Cloudinary**
  Future<String> uploadAdMedia(File file, String mediaType) async {
    try {
      if (mediaType == 'image') {
        return await _cloudinaryService.uploadImage(
          file,
          folder: 'snehayog/ads/images',
        );
      } else if (mediaType == 'video') {
        final result = await _cloudinaryService.uploadVideo(
          file,
          folder: 'snehayog/ads/videos',
        );
        // Extract URL from the result map
        return result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
      } else {
        throw Exception('Unsupported media type: $mediaType');
      }
    } catch (e) {
      throw Exception('Error uploading media: $e');
    }
  }

  // **NEW: Delete ad media from Cloudinary**
  Future<bool> deleteAdMedia(String mediaUrl, String mediaType) async {
    try {
      // Extract public ID from Cloudinary URL
      final uri = Uri.parse(mediaUrl);
      final pathSegments = uri.pathSegments;

      if (pathSegments.length >= 3 && pathSegments[1] == 'upload') {
        final publicId = pathSegments.sublist(3).join('/');
        return await _cloudinaryService.deleteMedia(publicId, mediaType);
      }

      return false;
    } catch (e) {
      print('Error deleting media: $e');
      return false;
    }
  }

  // Get ad performance metrics
  Future<Map<String, dynamic>> getAdPerformance(String adId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/ads/$adId/performance'),
        headers: {'Authorization': 'Bearer ${userData['token']}'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to fetch ad performance: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching ad performance: $e');
    }
  }

  // **NEW: Get creator revenue summary**
  Future<Map<String, dynamic>> getCreatorRevenueSummary() async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.get(
        Uri.parse(
          '$baseUrl/api/ads/creator/revenue/${userData['googleId'] ?? userData['id']}',
        ),
        headers: {'Authorization': 'Bearer ${userData['token']}'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to fetch creator revenue: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching creator revenue: $e');
    }
  }

  /// **NEW: Clear ad cache to ensure deleted ads are removed from video feed**
  Future<void> _clearAdCache() async {
    try {
      print('🧹 AdService: Clearing ad cache...');

      // Clear active ads cache
      await _clearCacheForKey('active_ads');
      await _clearCacheForKey('user_ads');

      // Clear any ad-related cache entries
      final cacheKeys = [
        'active_ads',
        'user_ads',
        'banner_ads',
        'video_feed_ads',
        'ads_page_1',
        'ads_page_2',
        'ads_page_3',
      ];

      for (final key in cacheKeys) {
        await _clearCacheForKey(key);
      }

      print('✅ AdService: Ad cache cleared successfully');
    } catch (e) {
      print('⚠️ AdService: Error clearing ad cache: $e');
      // Don't throw error - cache clearing failure shouldn't break ad deletion
    }
  }

  /// **NEW: Clear specific cache key**
  Future<void> _clearCacheForKey(String key) async {
    try {
      print('🧹 AdService: Clearing cache for key: $key');

      // Clear from SmartCacheManager by forcing refresh with null data
      // This will effectively clear the cache entry
      await _cacheManager.get(
        key,
        fetchFn: () async => null as dynamic,
        cacheType: 'ads',
        maxAge: Duration.zero, // Force immediate expiration
        forceRefresh: true,
      );
      print('✅ AdService: Cleared cache for key: $key');
    } catch (e) {
      print('⚠️ AdService: Error clearing cache for key $key: $e');
    }
  }

  /// **NEW: Notify video feed to refresh ads**
  Future<void> _notifyVideoFeedRefresh() async {
    try {
      print('📢 AdService: Notifying video feed to refresh ads...');

      // Clear video feed specific cache keys
      final videoFeedCacheKeys = [
        'video_feed_ads',
        'active_ads_video_feed',
        'banner_ads_video_feed',
        'ads_serve_response',
      ];

      for (final key in videoFeedCacheKeys) {
        await _clearCacheForKey(key);
      }

      // Also clear any cached video feed data that includes ads
      await _clearCacheForKey('video_feed_page_1');
      await _clearCacheForKey('video_feed_page_2');
      await _clearCacheForKey('video_feed_page_3');

      // **NEW: Notify video feed listeners to refresh ads**
      try {
        _adRefreshNotifier.notifyRefresh();
        print(
            '📢 AdService: Sent refresh notification to video feed listeners');
      } catch (e) {
        print('⚠️ AdService: Could not send refresh notification: $e');
      }

      print(
          '✅ AdService: Video feed cache cleared, ads will refresh on next load');
    } catch (e) {
      print('⚠️ AdService: Error notifying video feed refresh: $e');
    }
  }
}
