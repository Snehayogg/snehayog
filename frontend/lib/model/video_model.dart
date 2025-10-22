class VideoModel {
  final String id;
  final String videoName;
  final String videoUrl;
  final String thumbnailUrl;
  int likes;
  int views;
  int shares;
  final String? description; // Optional description field
  final Uploader uploader;
  final DateTime uploadedAt;
  final List<String> likedBy;
  final String videoType;
  final double aspectRatio;
  final Duration duration;
  List<Comment> comments;
  final String? link;
  // HLS Streaming fields
  final String? hlsMasterPlaylistUrl;
  final String? hlsPlaylistUrl;
  final List<Map<String, dynamic>>? hlsVariants;
  final bool? isHLSEncoded;

  // **SIMPLIFIED: Since all videos are 480p, we only need one quality URL**
  // Keeping lowQualityUrl for backward compatibility (will contain 480p URL)
  final String? lowQualityUrl; // 480p - the only quality we use

  // **NEW: Video processing status**
  final String processingStatus;
  final int processingProgress;
  final String? processingError;

  VideoModel({
    required this.id,
    required this.videoName,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.likes,
    required this.views,
    required this.shares,
    this.description,
    required this.uploader,
    required this.uploadedAt,
    required this.likedBy,
    required this.videoType,
    required this.aspectRatio,
    required this.duration,
    required List<Comment> comments, // **FIXED: Explicit type annotation**
    this.link,
    this.hlsMasterPlaylistUrl,
    this.hlsPlaylistUrl,
    this.hlsVariants,
    this.isHLSEncoded,
    this.lowQualityUrl, // 480p URL for all videos
    this.processingStatus =
        'completed', // Default to completed for backward compatibility
    this.processingProgress = 100,
    this.processingError,
  }) : comments = comments; // **FIXED: Initialize the field**

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    try {
      print('Parsing video JSON: $json');

      return VideoModel(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
        videoName: json['videoName']?.toString() ?? '',
        videoUrl: json['videoUrl']?.toString() ?? '',
        thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
        likes: (json['likes'] is int)
            ? json['likes']
            : int.tryParse(json['likes']?.toString() ?? '0') ?? 0,
        views: (json['views'] is int)
            ? json['views']
            : int.tryParse(json['views']?.toString() ?? '0') ?? 0,
        shares: (json['shares'] is int)
            ? json['shares']
            : int.tryParse(json['shares']?.toString() ?? '0') ?? 0,
        description: json['description']?.toString(), // Parse description field

        uploader: () {
          print('🔍 VideoModel: Parsing uploader data...');
          print('🔍 VideoModel: json["uploader"] = ${json['uploader']}');
          print(
              '🔍 VideoModel: json["uploader"] type = ${json['uploader']?.runtimeType}');

          if (json['uploader'] is Map<String, dynamic>) {
            print('🔍 VideoModel: uploader is Map, calling Uploader.fromJson');
            final uploader = Uploader.fromJson(json['uploader']);
            print('🔍 VideoModel: parsed uploader = ${uploader.toJson()}');
            return uploader;
          } else {
            print(
                '🔍 VideoModel: uploader is not Map, creating default Uploader');
            return Uploader(
                id: json['uploader']?.toString() ?? 'unknown',
                name: 'Unknown',
                profilePic: '');
          }
        }(),
        uploadedAt: json['uploadedAt'] != null
            ? DateTime.tryParse(json['uploadedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        likedBy: () {
          try {
            if (json['likedBy'] == null) {
              return <String>[];
            }

            // **FIXED: More explicit type checking and conversion**
            if (json['likedBy'] is List<dynamic>) {
              final likedByList = json['likedBy'] as List<dynamic>;
              if (likedByList.isEmpty) {
                return <String>[];
              }

              final List<String> parsedLikedBy = <String>[];
              for (final dynamic item in likedByList) {
                parsedLikedBy.add(item.toString());
              }
              return parsedLikedBy;
            }

            return <String>[];
          } catch (e) {
            print('⚠️ VideoModel: Error parsing likedBy: $e');
            return <String>[];
          }
        }(),
        videoType: json['videoType']?.toString() ?? 'reel',
        aspectRatio: (json['aspectRatio'] is num)
            ? json['aspectRatio'].toDouble()
            : double.tryParse(json['aspectRatio']?.toString() ?? '0.5625') ??
                9 / 16,
        duration: Duration(
            seconds: (json['duration'] is int)
                ? json['duration']
                : int.tryParse(json['duration']?.toString() ?? '0') ?? 0),
        comments: () {
          try {
            print('🔍 VideoModel: Parsing comments field...');
            print('🔍 VideoModel: json["comments"] = ${json['comments']}');
            print(
                '🔍 VideoModel: json["comments"] type = ${json['comments']?.runtimeType}');

            if (json['comments'] == null) {
              print('🔍 VideoModel: comments is null, returning empty list');
              return <Comment>[];
            }

            // **FIXED: More explicit type checking and conversion**
            if (json['comments'] is List<dynamic>) {
              final commentsList = json['comments'] as List<dynamic>;
              print(
                  '🔍 VideoModel: comments is List<dynamic> with ${commentsList.length} items');

              if (commentsList.isEmpty) {
                print(
                    '🔍 VideoModel: comments list is empty, returning empty list');
                return <Comment>[];
              }

              final List<Comment> parsedComments = <Comment>[];

              for (final dynamic comment in commentsList) {
                print(
                    '🔍 VideoModel: Processing comment: $comment (type: ${comment.runtimeType})');
                if (comment is Map<String, dynamic>) {
                  try {
                    final parsedComment = Comment.fromJson(comment);
                    print(
                        '🔍 VideoModel: Successfully parsed comment: ${parsedComment.toJson()}');
                    parsedComments.add(parsedComment);
                  } catch (e) {
                    print(
                        '⚠️ VideoModel: Error parsing individual comment: $e');
                    // Skip invalid comments
                  }
                } else {
                  print(
                      '⚠️ VideoModel: Skipping invalid comment (not Map): $comment');
                }
              }

              print(
                  '🔍 VideoModel: Successfully parsed ${parsedComments.length} comments');
              return parsedComments;
            }

            print(
                '🔍 VideoModel: comments is not a List<dynamic>, returning empty list');
            return <Comment>[];
          } catch (e) {
            print('❌ VideoModel: Error parsing comments: $e');
            print('❌ Stack trace: ${StackTrace.current}');
            return <Comment>[];
          }
        }(),
        link: () {
          print(
              '🔗 VideoModel: Parsing link field for video: ${json['videoName']}');
          print('🔗 VideoModel: Raw JSON data: $json');

          // Try multiple possible field names for the link
          final possibleFields = ['link', 'externalLink', 'websiteUrl', 'url'];

          for (final field in possibleFields) {
            print('🔗 VideoModel: Checking field "$field": ${json[field]}');
            if (json.containsKey(field)) {
              final linkValue = json[field]?.toString().trim();
              print('🔗 VideoModel: Field "$field" value: "$linkValue"');
              if (linkValue?.isNotEmpty == true) {
                print(
                    '✅ VideoModel: Found link in field "$field": "$linkValue"');
                return linkValue;
              } else {
                print('⚠️ VideoModel: Field "$field" is empty or null');
              }
            } else {
              print('❌ VideoModel: Field "$field" not found');
            }
          }

          print('❌ VideoModel: No link field found in video data');
          print('🔗 VideoModel: Available fields: ${json.keys.toList()}');
          return null;
        }(),
        // Parse HLS streaming fields
        hlsMasterPlaylistUrl: json['hlsMasterPlaylistUrl']?.toString(),
        hlsPlaylistUrl: json['hlsPlaylistUrl']?.toString(),
        hlsVariants: () {
          try {
            if (json['hlsVariants'] == null) {
              return null;
            }

            // **FIXED: More explicit type checking and conversion**
            if (json['hlsVariants'] is List<dynamic>) {
              final variantsList = json['hlsVariants'] as List<dynamic>;
              if (variantsList.isEmpty) {
                return null;
              }

              final List<Map<String, dynamic>> parsedVariants =
                  <Map<String, dynamic>>[];
              for (final dynamic variant in variantsList) {
                if (variant is Map<String, dynamic>) {
                  parsedVariants.add(variant);
                } else {
                  print('⚠️ VideoModel: Skipping invalid hlsVariant: $variant');
                }
              }
              return parsedVariants;
            }

            return null;
          } catch (e) {
            print('⚠️ VideoModel: Error parsing hlsVariants: $e');
            return null;
          }
        }(),
        isHLSEncoded: json['isHLSEncoded'] == true,
        lowQualityUrl: json['lowQualityUrl']?.toString(), // 480p URL
        // Parse processing status fields
        processingStatus: json['processingStatus']?.toString() ?? 'completed',
        processingProgress: (json['processingProgress'] is int)
            ? json['processingProgress']
            : int.tryParse(json['processingProgress']?.toString() ?? '100') ??
                100,
        processingError: json['processingError']?.toString(),
      );
    } catch (e, stackTrace) {
      print('❌ VideoModel.fromJson Error: $e');
      print('❌ Stack trace: $stackTrace');
      print('❌ JSON data: $json');
      rethrow;
    }
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
      'description': description, // Include description in JSON
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
      'link': link,
      'hlsMasterPlaylistUrl': hlsMasterPlaylistUrl,
      'hlsPlaylistUrl': hlsPlaylistUrl,
      'hlsVariants': hlsVariants,
      'isHLSEncoded': isHLSEncoded,
      'lowQualityUrl': lowQualityUrl, // 480p URL
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
    String? description, // Add description parameter
    Uploader? uploader,
    DateTime? uploadedAt,
    List<String>? likedBy,
    String? videoType,
    double? aspectRatio,
    Duration? duration,
    List<Comment>? comments,
    String? link,
    // **CRITICAL FIX: Add HLS fields to copyWith**
    String? hlsMasterPlaylistUrl,
    String? hlsPlaylistUrl,
    List<Map<String, dynamic>>? hlsVariants,
    bool? isHLSEncoded,
    String? lowQualityUrl, // 480p URL
  }) {
    return VideoModel(
      id: id ?? this.id,
      videoName: videoName ?? this.videoName,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      likes: likes ?? this.likes,
      views: views ?? this.views,
      shares: shares ?? this.shares,
      description:
          description ?? this.description, // Handle description in copyWith
      uploader: uploader ?? this.uploader,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      likedBy: likedBy ?? this.likedBy,
      videoType: videoType ?? this.videoType,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      duration: duration ?? this.duration,
      comments: comments ?? this.comments,
      link: link ?? this.link,
      // **CRITICAL FIX: Handle HLS fields in copyWith**
      hlsMasterPlaylistUrl: hlsMasterPlaylistUrl ?? this.hlsMasterPlaylistUrl,
      hlsPlaylistUrl: hlsPlaylistUrl ?? this.hlsPlaylistUrl,
      hlsVariants: hlsVariants ?? this.hlsVariants,
      isHLSEncoded: isHLSEncoded ?? this.isHLSEncoded,
      lowQualityUrl: lowQualityUrl ?? this.lowQualityUrl, // 480p URL
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

  /// Get 480p quality URL (standardized for all videos)
  String get480pUrl() {
    // Always use 480p quality for consistent streaming
    return lowQualityUrl ?? videoUrl;
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
    try {
      return Uploader(
        id: json['googleId']?.toString() ??
            json['_id']?.toString() ??
            json['id']?.toString() ??
            '',
        name: json['name']?.toString() ?? '',
        profilePic: json['profilePic']?.toString() ?? '',
      );
    } catch (e, stackTrace) {
      print('❌ Uploader.fromJson Error: $e');
      print('❌ Stack trace: $stackTrace');
      print('❌ Uploader JSON data: $json');
      rethrow;
    }
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'profilePic': profilePic,
    };
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
    try {
      print('🔍 Comment.fromJson: Parsing comment data: $json');

      return Comment(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
        userId: json['userId']?.toString() ??
            json['user']?['_id']?.toString() ??
            json['user']?['googleId']?.toString() ??
            '',
        userName: json['userName']?.toString() ??
            json['user']?['name']?.toString() ??
            'User',
        userProfilePic: json['userProfilePic']?.toString() ??
            json['user']?['profilePic']?.toString() ??
            '',
        text: json['text']?.toString() ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
    } catch (e, stackTrace) {
      print('❌ Comment.fromJson Error: $e');
      print('❌ Stack trace: $stackTrace');
      print('❌ Comment JSON data: $json');
      rethrow;
    }
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
