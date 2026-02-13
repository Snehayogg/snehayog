import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vayu/shared/models/video_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class ProfileLocalDataSource {
  static const String _boxName = 'profile_cache';
  
  // Cache keys
  static const String _userPrefix = 'user_';
  static const String _videosPrefix = 'videos_';
  static const String _timestampPrefix = 'time_';

  /// Initialize the box (safe to call multiple times)
  Future<Box> _getBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return await Hive.openBox(_boxName);
    }
  }

  /// **Cache User Data with Earning Sanitization**
  Future<void> cacheUserData(String userId, Map<String, dynamic> data) async {
    try {
      final box = await _getBox();
      
      // Sanitization: Remove earning data before caching
      final sanitizedData = _sanitizeUserData(data);
      
      await box.put(_userPrefix + userId, jsonEncode(sanitizedData));
      await box.put(_timestampPrefix + _userPrefix + userId, DateTime.now().toIso8601String());
      
      AppLogger.log('💾 ProfileLocalDataSource: Cached data for $userId (Sanitized)');
    } catch (e) {
      AppLogger.log('⚠️ ProfileLocalDataSource: Failed to cache user data: $e');
    }
  }

  /// **Get Cached User Data**
  Future<Map<String, dynamic>?> getCachedUserData(String userId) async {
    try {
      final box = await _getBox();
      final key = _userPrefix + userId;
      
      if (!box.containsKey(key)) return null;
      
      final jsonString = box.get(key) as String;
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.log('❌ ProfileLocalDataSource: Error reading cached user data: $e');
      return null;
    }
  }

  /// **Cache User Videos with Earning Sanitization**
  Future<void> cacheUserVideos(String userId, List<VideoModel> videos) async {
    try {
      final box = await _getBox();
      
      // Sanitization: Set earnings to 0.0 before serializing
      final List<Map<String, dynamic>> jsonList = videos.map((v) {
        final videoJson = v.toJson();
        videoJson['earnings'] = 0.0;
        if (videoJson['uploader'] is Map) {
          final uploader = Map<String, dynamic>.from(videoJson['uploader'] as Map);
          uploader['earnings'] = 0.0;
          videoJson['uploader'] = uploader;
        }
        return videoJson;
      }).toList();
      
      await box.put(_videosPrefix + userId, jsonEncode(jsonList));
      await box.put(_timestampPrefix + _videosPrefix + userId, DateTime.now().toIso8601String());
      
      AppLogger.log('💾 ProfileLocalDataSource: Cached ${videos.length} videos for $userId (Sanitized)');
    } catch (e) {
      AppLogger.log('⚠️ ProfileLocalDataSource: Failed to cache user videos: $e');
    }
  }

  /// **Get Cached User Videos**
  Future<List<VideoModel>?> getCachedUserVideos(String userId) async {
    try {
      final box = await _getBox();
      final key = _videosPrefix + userId;
      
      if (!box.containsKey(key)) return null;
      
      final jsonString = box.get(key) as String;
      final List<dynamic> jsonList = jsonDecode(jsonString);
      
      return jsonList
          .map((json) => VideoModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.log('❌ ProfileLocalDataSource: Error reading cached user videos: $e');
      return null;
    }
  }

  /// **Sanitize User Data to remove earnings**
  Map<String, dynamic> _sanitizeUserData(Map<String, dynamic> data) {
    final sanitized = Map<String, dynamic>.from(data);
    
    // Remove direct earning fields
    sanitized.remove('earnings');
    sanitized.remove('totalEarnings');
    sanitized.remove('pendingEarnings');
    sanitized.remove('withdrawableEarnings');
    
    // Sanitize nested creator stats if any
    if (sanitized['creatorStats'] is Map) {
       final stats = Map<String, dynamic>.from(sanitized['creatorStats'] as Map);
       stats.remove('earnings');
       stats.remove('revenue');
       sanitized['creatorStats'] = stats;
    }

    // If videos are inside user data (e.g. preloaded), sanitize them too
    if (sanitized['videos'] is List) {
       final videosList = sanitized['videos'] as List;
       sanitized['videos'] = videosList.map((v) {
         if (v is Map) {
           final video = Map<String, dynamic>.from(v as Map);
           video['earnings'] = 0.0;
           if (video['uploader'] is Map) {
             final uploader = Map<String, dynamic>.from(video['uploader'] as Map);
             uploader['earnings'] = 0.0;
             video['uploader'] = uploader;
           }
           return video;
         }
         return v;
       }).toList();
    }
    
    return sanitized;
  }

  /// Clear cache for specific user
  Future<void> clearUserCache(String userId) async {
    try {
      final box = await _getBox();
      await box.delete(_userPrefix + userId);
      await box.delete(_videosPrefix + userId);
      await box.delete(_timestampPrefix + _userPrefix + userId);
      await box.delete(_timestampPrefix + _videosPrefix + userId);
      AppLogger.log('🧹 ProfileLocalDataSource: Cache cleared for $userId');
    } catch (e) {
      AppLogger.log('⚠️ ProfileLocalDataSource: Failed to clear cache: $e');
    }
  }
}
