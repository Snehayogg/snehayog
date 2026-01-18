import 'package:vayu/model/video_model.dart';

class ProfileLocalDataSource {
  // Hive Removed upon user request

  // Hive Removed upon user request
  // ignore: unused_element
  Future<void> _getBox() async {}

  /// Cache User Data (No-op)
  Future<void> cacheUserData(String userId, Map<String, dynamic> data) async {
    // No-op
  }

  /// Get Cached User Data (Always returns null)
  Future<Map<String, dynamic>?> getCachedUserData(String userId) async {
    return null; 
  }

  /// Cache User Videos (No-op)
  Future<void> cacheUserVideos(String userId, List<VideoModel> videos) async {
    // No-op
  }

  /// Get Cached User Videos (Always returns null)
  Future<List<VideoModel>?> getCachedUserVideos(String userId) async {
    return null;
  }

  /// Clear cache for specific user (No-op)
  Future<void> clearUserCache(String userId) async {
    // No-op
  }
}
