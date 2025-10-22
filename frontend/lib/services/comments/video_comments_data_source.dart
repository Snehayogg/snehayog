import 'package:snehayog/services/comments/comments_data_source.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/authservices.dart';

class VideoCommentsDataSource implements CommentsDataSource {
  final String videoId;
  final VideoService videoService;

  VideoCommentsDataSource({required this.videoId, required this.videoService});

  @override
  String get targetId => videoId;

  @override
  String get targetType => 'video';

  @override
  Future<(List<Map<String, dynamic>>, bool)> fetchComments(
      {int page = 1, int limit = 20}) async {
    try {
      final comments = await videoService.getComments(
        videoId,
        page: page,
        limit: limit,
      );

      // Convert Comment objects to Map<String, dynamic>
      final commentsList = comments.map((comment) => comment.toJson()).toList();

      // For now, assume there are more comments if we got the full limit
      final hasNext = comments.length == limit;

      return (commentsList, hasNext);
    } catch (e) {
      // Log error for debugging
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> postComment({required String content}) async {
    try {
      // Get current user data for userId
      final authService = AuthService();
      final userData = await authService.getUserData();

      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final userId = userData['googleId'] ?? userData['id'] ?? '';
      if (userId.isEmpty) {
        throw Exception('User ID not found');
      }

      final comments = await videoService.addComment(
        videoId,
        content,
        userId,
      );

      // Return the first comment (newly created)
      if (comments.isNotEmpty) {
        return comments.first.toJson();
      } else {
        throw Exception('Failed to create comment');
      }
    } catch (e) {
      // Log error for debugging
      rethrow;
    }
  }

  @override
  Future<void> deleteComment({required String commentId}) async {
    try {
      await videoService.deleteComment(videoId, commentId);
    } catch (e) {
      // Log error for debugging
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> toggleLikeOnComment(
      {required String commentId}) async {
    try {
      final updatedComment = await videoService.likeComment(videoId, commentId);
      return updatedComment.toJson();
    } catch (e) {
      // Log error for debugging
      rethrow;
    }
  }

  @override
  Map<String, dynamic> normalize(Map<String, dynamic> raw) {
    return raw;
  }
}
