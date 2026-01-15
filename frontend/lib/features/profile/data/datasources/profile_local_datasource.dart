import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/utils/app_logger.dart';

class ProfileLocalDataSource {
  static const String _boxName = 'profile_cache';

  // Cache keys prefix
  static const String _userDataPrefix = 'user_data_';
  static const String _userVideosPrefix = 'user_videos_';
  static const String _lastUpdatedPrefix = 'last_updated_';

  static const Duration _cacheMaxAge = Duration(days: 7);

  Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  /// Cache User Data (Map)
  Future<void> cacheUserData(String userId, Map<String, dynamic> data) async {
    try {
      final box = await _getBox();
      final key = '$_userDataPrefix$userId';
      final updateKey = '$_lastUpdatedPrefix$key';

      await box.put(key, jsonEncode(data));
      await box.put(updateKey, DateTime.now().toIso8601String());

      AppLogger.log('💾 ProfileLocalDataSource: Cached user data for $userId');
    } catch (e) {
      AppLogger.log('❌ ProfileLocalDataSource: Error caching user data: $e');
    }
  }

  /// Get Cached User Data
  Future<Map<String, dynamic>?> getCachedUserData(String userId) async {
    try {
      final box = await _getBox();
      final key = '$_userDataPrefix$userId';

      if (!box.containsKey(key)) return null;

      final updateKey = '$_lastUpdatedPrefix$key';
      if (box.containsKey(updateKey)) {
        final lastUpdatedStr = box.get(updateKey) as String;
        final lastUpdated = DateTime.parse(lastUpdatedStr);
        if (DateTime.now().difference(lastUpdated) > _cacheMaxAge) {
          AppLogger.log('⏳ ProfileLocalDataSource: Cache expired for $userId');
          await box.delete(key);
          await box.delete(updateKey);
          return null;
        }
      }

      final jsonString = box.get(key) as String;
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.log(
          '❌ ProfileLocalDataSource: Error reading cached user data: $e');
      return null;
    }
  }

  /// Cache User Videos
  Future<void> cacheUserVideos(String userId, List<VideoModel> videos) async {
    try {
      final box = await _getBox();
      final key = '$_userVideosPrefix$userId';
      final updateKey = '$_lastUpdatedPrefix$key';

      final jsonList = videos.map((v) => v.toJson()).toList();
      await box.put(key, jsonEncode(jsonList));
      await box.put(updateKey, DateTime.now().toIso8601String());

      AppLogger.log(
          '💾 ProfileLocalDataSource: Cached ${videos.length} videos for $userId');
    } catch (e) {
      AppLogger.log('❌ ProfileLocalDataSource: Error caching user videos: $e');
    }
  }

  /// Get Cached User Videos
  Future<List<VideoModel>?> getCachedUserVideos(String userId) async {
    try {
      final box = await _getBox();
      final key = '$_userVideosPrefix$userId';

      if (!box.containsKey(key)) return null;

      final updateKey = '$_lastUpdatedPrefix$key';
      if (box.containsKey(updateKey)) {
        final lastUpdatedStr = box.get(updateKey) as String;
        final lastUpdated = DateTime.parse(lastUpdatedStr);
        if (DateTime.now().difference(lastUpdated) > _cacheMaxAge) {
          AppLogger.log(
              '⏳ ProfileLocalDataSource: Video cache expired for $userId');
          await box.delete(key);
          await box.delete(updateKey);
          return null;
        }
      }

      final jsonString = box.get(key) as String;
      final List<dynamic> jsonList = jsonDecode(jsonString);

      return jsonList.map((json) => VideoModel.fromJson(json)).toList();
    } catch (e) {
      AppLogger.log(
          '❌ ProfileLocalDataSource: Error reading cached videos: $e');
      return null;
    }
  }

  /// Clear cache for specific user (e.g. on logout or refresh)
  Future<void> clearUserCache(String userId) async {
    final box = await _getBox();
    await box.delete('$_userDataPrefix$userId');
    await box.delete('$_userVideosPrefix$userId');
  }
}
