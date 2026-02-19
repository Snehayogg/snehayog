import 'package:vayu/features/video/video_model.dart';

class ProfileLocalDataSource {
  /// **Cache User Data - DISABLED**
  Future<void> cacheUserData(String userId, Map<String, dynamic> data) async {
    // Persistent Hive caching disabled to prevent data mismatch bugs.
    return;
  }

  /// **Get Cached User Data - DISABLED**
  Future<Map<String, dynamic>?> getCachedUserData(String userId) async {
    // Persistent Hive caching disabled to prevent data mismatch bugs.
    return null;
  }

  /// **Cache User Videos - DISABLED**
  Future<void> cacheUserVideos(String userId, List<VideoModel> videos) async {
    // Persistent Hive caching disabled to prevent data mismatch bugs.
    return;
  }

  /// **Get Cached User Videos - DISABLED**
  Future<List<VideoModel>?> getCachedUserVideos(String userId) async {
    // Persistent Hive caching disabled to prevent data mismatch bugs.
    return null;
  }

  /// Clear cache for specific user - DISABLED
  Future<void> clearUserCache(String userId) async {
    // Hive interaction disabled.
    return;
  }
}
