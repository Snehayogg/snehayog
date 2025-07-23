import 'dart:convert';

class VideoModel {
  final String id;
  final String videoName;
  final String videoUrl;
  final String thumbnailUrl;
  int likes;
  int views;
  int shares;
  final String description;
  final Uploader uploader;
  final DateTime uploadedAt;
  final List<String> likedBy;
  final String videoType;
  final double aspectRatio;
  final Duration duration;
  List<Comment> comments;

  VideoModel({
    required this.id,
    required this.videoName,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.likes,
    required this.views,
    required this.shares,
    required this.description,
    required this.uploader,
    required this.uploadedAt,
    required this.likedBy,
    required this.videoType,
    required this.aspectRatio,
    required this.duration,
    required this.comments,
  });

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    print('Parsing video JSON: $json');
    return VideoModel(
      id: json['_id'] ?? json['id'],
      videoName: json['videoName'] ?? '',
      videoUrl: json['videoUrl'] ?? '',
      thumbnailUrl: json['thumbnailUrl'] ?? '',
      likes: json['likes'] ?? 0,
      views: json['views'] ?? 0,
      shares: json['shares'] ?? 0,
      description: json['description'] ?? '',
      uploader: (json['uploader'] is Map<String, dynamic>)
          ? Uploader.fromJson(json['uploader'])
          : Uploader(
              id: json['uploader'].toString(), name: 'Unknown', profilePic: ''),
      uploadedAt: json['uploadedAt'] != null
          ? DateTime.parse(json['uploadedAt'])
          : DateTime.now(),
      likedBy: List<String>.from(json['likedBy'] ?? []),
      videoType: json['videoType'] ?? 'reel',
      aspectRatio: (json['aspectRatio'] ?? 9 / 16).toDouble(),
      duration: Duration(seconds: json['duration'] ?? 0),
      comments: (json['comments'] as List<dynamic>?)
              ?.map((comment) => Comment.fromJson(comment))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'videoName': videoName,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'likes': likes,
      'views': views,
      'shares': shares,
      'description': description,
      'uploader': {
        '_id': uploader.id,
        'name': uploader.name,
        'profilePic': uploader.profilePic,
      },
      'uploadedAt': uploadedAt.toIso8601String(),
      'likedBy': likedBy,
      'videoType': videoType,
      'aspectRatio': aspectRatio,
      'duration': duration.inSeconds,
      'comments': comments.map((comment) => comment.toJson()).toList(),
    };
  }

  VideoModel copyWith({
    String? id,
    String? videoName,
    String? videoUrl,
    String? thumbnailUrl,
    int? likes,
    int? views,
    int? shares,
    String? description,
    Uploader? uploader,
    DateTime? uploadedAt,
    List<String>? likedBy,
    String? videoType,
    double? aspectRatio,
    Duration? duration,
    List<Comment>? comments,
  }) {
    return VideoModel(
      id: id ?? this.id,
      videoName: videoName ?? this.videoName,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      likes: likes ?? this.likes,
      views: views ?? this.views,
      shares: shares ?? this.shares,
      description: description ?? this.description,
      uploader: uploader ?? this.uploader,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      likedBy: likedBy ?? this.likedBy,
      videoType: videoType ?? this.videoType,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      duration: duration ?? this.duration,
      comments: comments ?? this.comments,
    );
  }

  bool isLikedBy(String userId) => likedBy.contains(userId);

  VideoModel toggleLike(String userId) {
    final updatedLikedBy = List<String>.from(likedBy);
    int updatedLikes = likes;

    if (isLikedBy(userId)) {
      updatedLikedBy.remove(userId);
      updatedLikes--;
    } else {
      updatedLikedBy.add(userId);
      updatedLikes++;
    }

    return copyWith(
      likedBy: updatedLikedBy,
      likes: updatedLikes,
    );
  }
}

class Uploader {
  final String id;
  final String name;
  final String profilePic;

  Uploader({
    required this.id,
    required this.name,
    required this.profilePic,
  });

  factory Uploader.fromJson(Map<String, dynamic> json) {
    return Uploader(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      profilePic: json['profilePic'] ?? '',
    );
  }

  Uploader copyWith({
    String? id,
    String? name,
    String? profilePic,
  }) {
    return Uploader(
      id: id ?? this.id,
      name: name ?? this.name,
      profilePic: profilePic ?? this.profilePic,
    );
  }
}

class Comment {
  final String id;
  final String userId;
  final String userName;
  final String userProfilePic;
  final String text;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userProfilePic,
    required this.text,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['_id'] ?? json['id'] ?? '',
      userId: json['user']?['_id'] ?? json['userId'] ?? '',
      userName: json['user']?['name'] ?? json['userName'] ?? '',
      userProfilePic:
          json['user']?['profilePic'] ?? json['userProfilePic'] ?? '',
      text: json['text'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userProfilePic': userProfilePic,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
