import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class VideoLocalDataSource {
  static const String _boxName = 'video_feed_cache';

  // Cache keys
  static const String _yogFeedKey = 'feed_yog_v1';
  static const String _vayuFeedKey = 'feed_vayu_v1';
  static const String _lastUpdatedKey = 'last_updated_';

  // Cache validity duration (e.g., consider cache valid for 24 hours for offline viewing)
  // But we always try to refresh in background
  static const Duration _cacheMaxAge = Duration(days: 7);

  /// Initialize the box (safe to call multiple times)
  Future<Box> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return await Hive.openBox(_boxName);
    }
  }

  /// **Save Video Feed to Cache**
  Future<void> cacheVideoFeed(List<VideoModel> videos, String type) async {
    try {
      final box = await _getBox();
      final key = type == 'vayu'
          ? _vayuFeedKey
          : _yogFeedKey; // Default/Yog share same key

      // Convert entire list to JSON string for simple storage
      // VideoModel has toJson(), but we need to ensure it's fully serializable
      final List<Map<String, dynamic>> jsonList =
          videos.map((v) => v.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      await box.put(key, jsonString);
      await box.put(_lastUpdatedKey + type, DateTime.now().toIso8601String());

      AppLogger.log(
          '💾 LocalDataSource: Cached ${videos.length} videos for type: $type');
    } catch (e) {
      AppLogger.log('⚠️ LocalDataSource: Failed to cache feed: $e');
    }
  }

  /// **Get Cached Video Feed**
  /// Returns null if no cache exists
  Future<List<VideoModel>?> getCachedVideoFeed(String type) async {
    try {
      final box = await _getBox();
      final key = type == 'vayu' ? _vayuFeedKey : _yogFeedKey;
      final updateKey = _lastUpdatedKey + type;

      if (!box.containsKey(key)) {
        AppLogger.log('⚠️ LocalDataSource: No cache found for type: $type');
        return null;
      }

      // **EVICTION POLICY: Check Time-To-Live (TTL)**
      if (box.containsKey(updateKey)) {
        final lastUpdatedStr = box.get(updateKey) as String;
        final lastUpdated = DateTime.parse(lastUpdatedStr);
        final age = DateTime.now().difference(lastUpdated);

        if (age > _cacheMaxAge) {
          AppLogger.log(
              '🧹 LocalDataSource: Cache expired (Age: ${age.inHours}h). Evicting...');
          await box.delete(key);
          await box.delete(updateKey);
          return null;
        }
      }

      final jsonString = box.get(key) as String;
      final List<dynamic> jsonList = jsonDecode(jsonString);

      final videos = jsonList
          .map((json) => VideoModel.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.log(
          '🚀 LocalDataSource: Retrieved ${videos.length} cached videos for type: $type');
      return videos;
    } catch (e) {
      AppLogger.log('❌ LocalDataSource: Error reading cache: $e');
      return null;
    }
  }

  /// **Delete Cache** (Optional, e.g., on logout)
  Future<void> clearCache() async {
    final box = await _getBox();
    await box.clear();
    AppLogger.log('🧹 LocalDataSource: Cache cleared');
  }
}
