import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/utils/app_logger.dart';

class FeedLocalDataSource {
  static const String _boxName = 'feed_cache';
  static const String _feedPrefix = 'feed_page_';
  static const String _lastUpdatedPrefix = 'last_updated_';
  static const Duration _cacheMaxAge = Duration(hours: 24); // Cache feeds for 24 hours

  Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  /// Cache Feed Page
  Future<void> cacheFeed(int page, String? videoType, List<VideoModel> videos) async {
    try {
      final box = await _getBox();
      final typeSuffix = videoType != null ? '_$videoType' : '';
      final key = '$_feedPrefix$page$typeSuffix';
      final updateKey = '$_lastUpdatedPrefix$key';

      final jsonList = videos.map((v) => v.toJson()).toList();
      await box.put(key, jsonEncode(jsonList));
      await box.put(updateKey, DateTime.now().toIso8601String());

      AppLogger.log('💾 FeedLocalDataSource: Cached ${videos.length} videos for page $page (type: $videoType)');
    } catch (e) {
      AppLogger.log('❌ FeedLocalDataSource: Error caching feed: $e');
    }
  }

  /// Get Cached Feed Page
  Future<List<VideoModel>?> getCachedFeed(int page, String? videoType) async {
    try {
      final box = await _getBox();
      final typeSuffix = videoType != null ? '_$videoType' : '';
      final key = '$_feedPrefix$page$typeSuffix';

      if (!box.containsKey(key)) return null;

      final updateKey = '$_lastUpdatedPrefix$key';
      if (box.containsKey(updateKey)) {
        final lastUpdatedStr = box.get(updateKey) as String;
        final lastUpdated = DateTime.parse(lastUpdatedStr);
        if (DateTime.now().difference(lastUpdated) > _cacheMaxAge) {
          AppLogger.log('⏳ FeedLocalDataSource: cache expired for page $page');
          await box.delete(key);
          await box.delete(updateKey);
          return null;
        }
      }

      final jsonString = box.get(key) as String;
      final List<dynamic> jsonList = jsonDecode(jsonString);

      return jsonList.map((json) {
        // Ensure map keys are strings for VideoModel.fromJson
        if (json is Map) {
          return VideoModel.fromJson(Map<String, dynamic>.from(json));
        }
        return VideoModel.fromJson(json);
      }).toList();
    } catch (e) {
      AppLogger.log('❌ FeedLocalDataSource: Error reading cached feed: $e');
      return null;
    }
  }

  /// Clear entire feed cache
  Future<void> clearFeedCache() async {
    try {
      final box = await _getBox();
      await box.clear();
      AppLogger.log('🧹 FeedLocalDataSource: Cache cleared');
    } catch (e) {
      AppLogger.log('❌ FeedLocalDataSource: Error clearing cache: $e');
    }
  }
}
