import 'package:flutter/material.dart';

/// A minimal, reusable interface for comments across different targets (video, ad, etc.)
abstract class CommentsDataSource {
  /// Unique target identifier (e.g., videoId or adId)
  String get targetId;

  /// Human-readable target kind, used for analytics/logs if needed (e.g., 'video', 'ad')
  String get targetType;

  /// Load paginated comments. Returns a tuple of (comments, hasNextPage)
  Future<(List<Map<String, dynamic>>, bool)> fetchComments(
      {int page = 1, int limit = 20});

  /// Post a comment. Returns the newly created comment (as map)
  Future<Map<String, dynamic>> postComment({required String content});

  /// Delete a comment by id
  Future<void> deleteComment({required String commentId});

  /// Toggle like on a comment and return the updated comment
  Future<Map<String, dynamic>> toggleLikeOnComment({required String commentId});

  /// Optional: resolve display fields for a comment map
  @mustCallSuper
  Map<String, dynamic> normalize(Map<String, dynamic> raw) {
    return raw;
  }
}
