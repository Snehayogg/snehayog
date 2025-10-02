/// Domain entity for video - represents the core business logic
class VideoEntity {
  final String id;
  final String title;
  final String description;
  final String videoUrl;
  final String thumbnailUrl;
  final String? originalVideoUrl;
  final String uploaderId;
  final String uploaderName;
  final DateTime uploadTime;
  final int views;
  final int likes;
  final int shares;
  final List<CommentEntity> comments;
  final String videoType;
  final String? link;
  final bool isLongVideo;

  const VideoEntity({
    required this.id,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.thumbnailUrl,
    this.originalVideoUrl,
    required this.uploaderId,
    required this.uploaderName,
    required this.uploadTime,
    required this.views,
    required this.likes,
    required this.shares,
    required this.comments,
    required this.videoType,
    this.link,
    required this.isLongVideo,
  });

  /// Creates a copy of this entity with updated values
  VideoEntity copyWith({
    String? id,
    String? title,
    String? description,
    String? videoUrl,
    String? thumbnailUrl,
    String? originalVideoUrl,
    String? uploaderId,
    String? uploaderName,
    DateTime? uploadTime,
    int? views,
    int? likes,
    int? shares,
    List<CommentEntity>? comments,
    String? videoType,
    String? link,
    bool? isLongVideo,
  }) {
    return VideoEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      originalVideoUrl: originalVideoUrl ?? this.originalVideoUrl,
      uploaderId: uploaderId ?? this.uploaderId,
      uploaderName: uploaderName ?? this.uploaderName,
      uploadTime: uploadTime ?? this.uploadTime,
      views: views ?? this.views,
      likes: likes ?? this.likes,
      shares: shares ?? this.shares,
      comments: comments ?? this.comments,
      videoType: videoType ?? this.videoType,
      link: link ?? this.link,
      isLongVideo: isLongVideo ?? this.isLongVideo,
    );
  }

  /// Checks if the video is liked by a specific user
  bool isLikedBy(String userId) {
    // This would typically check against a list of user IDs who liked the video
    // For now, we'll return false as the actual implementation depends on the data layer
    return false;
  }

  /// Gets the formatted upload time
  String get formattedUploadTime {
    final now = DateTime.now();
    final difference = now.difference(uploadTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  /// Gets the formatted view count
  String get formattedViewCount {
    if (views < 1000) return views.toString();
    if (views < 1000000) return '${(views / 1000).toStringAsFixed(1)}K';
    return '${(views / 1000000).toStringAsFixed(1)}M';
  }

  /// Gets the formatted like count
  String get formattedLikeCount {
    if (likes < 1000) return likes.toString();
    if (likes < 1000000) return '${(likes / 1000).toStringAsFixed(1)}K';
    return '${(likes / 1000000).toStringAsFixed(1)}M';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VideoEntity && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'VideoEntity(id: $id, title: $title, uploader: $uploaderName)';
  }
}

/// Domain entity for video comments
class CommentEntity {
  final String id;
  final String text;
  final String userId;
  final String userName;
  final DateTime createdAt;

  const CommentEntity({
    required this.id,
    required this.text,
    required this.userId,
    required this.userName,
    required this.createdAt,
  });

  /// Gets the formatted creation time
  String get formattedTime {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommentEntity && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
