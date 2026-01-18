import 'package:vayu/model/video_model.dart';

class FeedLocalDataSource {
  // Hive Removed as per optimization plan

  // Hive Removed as per optimization plan
  // ignore: unused_element
  Future<void> _getBox() async {}

  /// Cache Feed Page (No-op)
  Future<void> cacheFeed(int page, String? videoType, List<VideoModel> videos) async {
    // No-op: Caching disabled to improve performance
  }

  /// Get Cached Feed Page (Always returns null)
  Future<List<VideoModel>?> getCachedFeed(int page, String? videoType) async {
    return null; // Force network fetch
  }

  /// Clear entire feed cache (No-op)
  Future<void> clearFeedCache() async {
    // No-op
  }
}
