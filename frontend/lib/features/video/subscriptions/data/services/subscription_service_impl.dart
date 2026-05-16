import 'dart:convert';
import 'package:vayug/core/interfaces/i_subscription_service.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/services/connectivity_service.dart';

class SubscriptionService implements ISubscriptionService {
  final HttpClientService _httpClient = HttpClientService.instance;

  // Internal cache for subscriber videos
  List<VideoModel>? _videosCache;
  DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  @override
  Future<List<VideoModel>> getSubscriberVideos({bool forceRefresh = false}) async {
    if (!forceRefresh && 
        _videosCache != null && 
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      return _videosCache!;
    }

    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) throw Exception('No internet connection');

    try {
      final baseUrl = await NetworkHelper.getBaseUrlWithFallback();
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/api/users/subscriber-videos'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> videoList = data['videos'] ?? [];
        
        final videos = videoList
            .map((json) => VideoModel.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        
        _videosCache = videos;
        _lastFetchTime = DateTime.now();
        return videos;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Please sign in to view subscriber content');
      } else {
        throw Exception('Failed to fetch subscriber videos');
      }
    } catch (e) {
      AppLogger.log('❌ SubscriptionService: Error: $e');
      rethrow;
    }
  }

  @override
  Future<List<Uploader>> getSubscribedCreators() async {
    // Implementation for fetching creators
    return [];
  }

  @override
  Future<bool> toggleSubscription(String creatorId) async {
    // Implementation for toggling subscription
    return false;
  }
}
