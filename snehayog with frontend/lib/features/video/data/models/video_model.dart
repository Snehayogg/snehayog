import '../../domain/entities/video_entity.dart';
import 'comment_model.dart';

/// Data model for video - extends the domain entity
/// This model handles JSON serialization/deserialization
class VideoModel extends VideoEntity {
  const VideoModel({
    required super.id,
    required super.title,
    required super.description,
    required super.videoUrl,
    required super.thumbnailUrl,
    super.originalVideoUrl,
    required super.uploaderId,
    required super.uploaderName,
    required super.uploadTime,
    required super.views,
    required super.likes,
    required super.shares,
    required super.comments,
    required super.videoType,
    super.link,
    required super.isLongVideo,
  });

  /// Creates a VideoModel from JSON data
  factory VideoModel.fromJson(Map<String, dynamic> json) {
    return VideoModel(
      id: json['_id'] ?? json['id'] ?? '',
      title: json['videoName'] ?? json['title'] ?? '',
      description: json['description'] ?? '',
      videoUrl: json['videoUrl'] ?? '',
      thumbnailUrl: json['thumbnailUrl'] ?? json['thumbnail'] ?? '',
      originalVideoUrl: json['originalVideoUrl'],
      uploaderId: json['uploaderId'] ?? json['googleId'] ?? '',
      uploaderName: json['uploaderName'] ?? json['uploader'] ?? '',
      uploadTime: json['uploadTime'] != null
          ? DateTime.parse(json['uploadTime'])
          : DateTime.now(),
      views: json['views'] ?? 0,
      likes: json['likes'] ?? 0,
      shares: json['shares'] ?? 0,
      comments: json['comments'] != null
          ? (json['comments'] as List)
              .map((comment) => CommentModel.fromJson(comment))
              .toList()
          : [],
      videoType: json['videoType'] ?? 'sneha',
      link: json['link'],
      isLongVideo: json['isLongVideo'] ?? false,
    );
  }

  /// Converts the VideoModel to JSON
  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'videoName': title,
      'description': description,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'originalVideoUrl': originalVideoUrl,
      'uploaderId': uploaderId,
      'uploaderName': uploaderName,
      'uploadTime': uploadTime.toIso8601String(),
      'views': views,
      'likes': likes,
      'shares': shares,
      'comments': comments.map((comment) {
        // Ensure we're working with CommentModel objects that have toJson()
        if (comment is CommentModel) {
          return comment.toJson();
        } else {
          // Convert CommentEntity to CommentModel first
          return CommentModel.fromEntity(comment).toJson();
        }
      }).toList(),
      'videoType': videoType,
      'link': link,
      'isLongVideo': isLongVideo,
    };
  }

  /// Creates a copy of this model with updated values
  @override
  VideoModel copyWith({
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
    return VideoModel(
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

  /// Converts the domain entity to a data model
  factory VideoModel.fromEntity(VideoEntity entity) {
    return VideoModel(
      id: entity.id,
      title: entity.title,
      description: entity.description,
      videoUrl: entity.videoUrl,
      thumbnailUrl: entity.thumbnailUrl,
      originalVideoUrl: entity.originalVideoUrl,
      uploaderId: entity.uploaderId,
      uploaderName: entity.uploaderName,
      uploadTime: entity.uploadTime,
      views: entity.views,
      likes: entity.likes,
      shares: entity.shares,
      comments: entity.comments
          .map((comment) => CommentModel.fromEntity(comment))
          .toList(),
      videoType: entity.videoType,
      link: entity.link,
      isLongVideo: entity.isLongVideo,
    );
  }

  /// Converts the data model to a domain entity
  VideoEntity toEntity() {
    return VideoEntity(
      id: id,
      title: title,
      description: description,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      originalVideoUrl: originalVideoUrl,
      uploaderId: uploaderId,
      uploaderName: uploaderName,
      uploadTime: uploadTime,
      views: views,
      likes: likes,
      shares: shares,
      comments: comments
          .map((comment) => CommentEntity(
                id: comment.id,
                text: comment.text,
                userId: comment.userId,
                userName: comment.userName,
                createdAt: comment.createdAt,
              ))
          .toList(),
      videoType: videoType,
      link: link,
      isLongVideo: isLongVideo,
    );
  }
}
