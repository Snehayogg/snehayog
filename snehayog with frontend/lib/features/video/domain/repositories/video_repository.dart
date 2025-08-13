import '../entities/video_entity.dart';

/// Abstract repository interface for video operations
/// This defines the contract that any video data source must implement
abstract class VideoRepository {
  /// Fetches a paginated list of videos
  /// Returns a map containing videos and pagination info
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int limit = 10,
  });

  /// Fetches a specific video by its ID
  Future<VideoEntity> getVideoById(String id);

  /// Fetches all videos uploaded by a specific user
  Future<List<VideoEntity>> getUserVideos(String userId);

  /// Uploads a new video
  Future<Map<String, dynamic>> uploadVideo({
    required String videoPath,
    required String title,
    required String description,
    String? link,
    Function(double)? onProgress,
  });

  /// Toggles the like status of a video for a user
  Future<VideoEntity> toggleLike(String videoId, String userId);

  /// Adds a comment to a video
  Future<List<CommentEntity>> addComment({
    required String videoId,
    required String text,
    required String userId,
  });

  /// Shares a video
  Future<VideoEntity> shareVideo({
    required String videoId,
    required String videoUrl,
    required String description,
  });

  /// Deletes a video
  Future<bool> deleteVideo(String videoId);

  /// Checks if the server is healthy
  Future<bool> checkServerHealth();

  /// Checks if a video is considered long (more than 2 minutes)
  Future<bool> isLongVideo(String videoPath);
}
