import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/ad_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/cloudinary_service.dart';
import 'package:snehayog/services/razorpay_service.dart';
import 'package:snehayog/config/app_config.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  static String get baseUrl => AppConfig.baseUrl;
  final AuthService _authService = AuthService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final RazorpayService _razorpayService = RazorpayService();

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

      // **NEW: Calculate impressions based on fixed CPM**
      final impressions =
          AppConfig.calculateImpressionsFromBudget(budget / 100.0);

      // **NEW: Calculate revenue split**
      final revenueSplit =
          _razorpayService.calculateRevenueSplit(budget / 100.0);

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
          'adType': adType,
          'budget': budget,
          'targetAudience': targetAudience,
          'targetKeywords': targetKeywords,
          'startDate': startDate?.toIso8601String(),
          'endDate': endDate?.toIso8601String(),
          'uploaderId': userData['googleId'] ?? userData['id'],
          'uploaderName': userData['name'],
          'uploaderProfilePic': userData['profilePic'],
          // **NEW: Revenue and impression data**
          'estimatedImpressions': impressions,
          'fixedCpm': AppConfig.fixedCpm,
          'creatorRevenue': revenueSplit['creator'],
          'platformRevenue': revenueSplit['platform'],
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
  }) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // Calculate impressions based on fixed CPM
      final impressions = AppConfig.calculateImpressionsFromBudget(budget);
      final revenueSplit = _razorpayService.calculateRevenueSplit(budget);

      print('🔍 AdService: Creating ad with payment...');
      print(
          '🔍 AdService: Budget: ₹$budget, Estimated impressions: $impressions');

      final response = await http.post(
        Uri.parse('$baseUrl/api/ads/create-with-payment'),
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
          'adType': adType,
          'budget': budget,
          'targetAudience': targetAudience,
          'targetKeywords': targetKeywords,
          'startDate': startDate?.toIso8601String(),
          'endDate': endDate?.toIso8601String(),
          'uploaderId': userData['googleId'] ?? userData['id'],
          'uploaderName': userData['name'],
          'uploaderProfilePic': userData['profilePic'],
          'estimatedImpressions': impressions,
          'fixedCpm': AppConfig.fixedCpm,
          'creatorRevenue': revenueSplit['creator'],
          'platformRevenue': revenueSplit['platform'],
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ AdService: Ad created successfully with payment required');

        return {
          'success': true,
          'ad': data['ad'],
          'invoice': data['invoice'],
          'message': data['message']
        };
      } else {
        final error = json.decode(response.body);
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
          'message': data['message']
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
      final paymentDetails =
          await _razorpayService.getPaymentDetails(paymentId);

      if (paymentDetails['status'] != 'captured') {
        throw Exception('Payment not completed');
      }

      // Update ad status to active
      final updatedAd = await updateAdStatus(adId, 'active');

      // **NEW: Record payment and revenue split**
      await _recordPaymentAndRevenue(adId, paymentDetails);

      return updatedAd;
    } catch (e) {
      throw Exception('Error processing payment: $e');
    }
  }

  // **NEW: Record payment and calculate revenue split**
  Future<void> _recordPaymentAndRevenue(
      String adId, Map<String, dynamic> paymentDetails) async {
    try {
      final amount = paymentDetails['amount'] / 100.0; // Convert from paise
      final revenueSplit = _razorpayService.calculateRevenueSplit(amount);

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
          'creatorRevenue': revenueSplit['creator'],
          'platformRevenue': revenueSplit['platform'],
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

      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/ads/user/${userData['googleId'] ?? userData['id']}'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => AdModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch ads: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching ads: $e');
    }
  }

  // Get all active ads (for display)
  Future<List<AdModel>> getActiveAds() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/ads/active'),
      );

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
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/api/ads/$adId'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
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
            '$baseUrl/api/ads/analytics/$adId?userId=${userData['googleId'] ?? userData['id']}'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
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
        return await _cloudinaryService.uploadImage(file,
            folder: 'snehayog/ads/images');
      } else if (mediaType == 'video') {
        return await _cloudinaryService.uploadVideo(file,
            folder: 'snehayog/ads/videos');
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
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
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
            '$baseUrl/api/ads/creator/revenue/${userData['googleId'] ?? userData['id']}'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
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
}
