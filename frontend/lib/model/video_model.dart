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
  final double earnings;
  // **NEW: Original video resolution (width x height)**
  final Map<String, dynamic>? originalResolution;
  // **NEW: Video content hash for duplicate detection**
  final String? videoHash;
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
  // **NEW: Related episodes for series**
  final List<Map<String, dynamic>>? episodes;
  // **NEW: Series Metadata**
  final String? seriesId;
  final int? episodeNumber;

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
    this.earnings = 0.0, // **NEW: Default earnings to 0.0**
    this.hlsMasterPlaylistUrl,
    this.hlsPlaylistUrl,
    this.hlsVariants,
    this.isHLSEncoded,
    this.lowQualityUrl, // 480p URL for all videos
    this.processingStatus =
        'completed', // Default to completed for backward compatibility
    this.processingProgress = 100,
    this.processingError,
    this.originalResolution, // **NEW: Original video resolution**
    this.videoHash, // **NEW: Video hash**
    this.episodes, // **NEW: Related episodes**
    this.seriesId,
    this.episodeNumber,
  }) : comments = comments; // **FIXED: Initialize the field**

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    try {
      print('Parsing video JSON: $json');

      return VideoModel(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
        videoName: () {
          final nameValue = json['videoName'];
          final name = nameValue != null ? nameValue.toString().trim() : '';
          return name.isEmpty ? 'Untitled Video' : name;
        }(),
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

          Uploader uploader;
          if (json['uploader'] is Map<String, dynamic>) {
            print('🔍 VideoModel: uploader is Map, calling Uploader.fromJson');
            final uploaderMap =
                Map<String, dynamic>.from(json['uploader'] as Map);
            uploader = Uploader.fromJson(uploaderMap);
            print('🔍 VideoModel: parsed uploader = ${uploader.toJson()}');
          } else {
            print(
                '🔍 VideoModel: uploader is not Map, creating default Uploader');
            uploader = Uploader(
              id: json['uploader']?.toString() ?? 'unknown',
              name: 'Unknown',
              profilePic: '',
            );
          }

          final uploaderMap = json['uploader'] is Map
              ? Map<String, dynamic>.from(json['uploader'] as Map)
              : <String, dynamic>{};

          final googleIdCandidates = [
            uploader.googleId,
            uploaderMap['googleId'],
            uploaderMap['google_id'],
            json['uploaderGoogleId'],
            json['googleId'],
            json['google_id'],
          ]
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();

          final resolvedGoogleId =
              googleIdCandidates.isNotEmpty ? googleIdCandidates.first : '';

          final fallbackIdCandidates = [
            resolvedGoogleId,
            uploaderMap['_id'],
            uploaderMap['id'],
            json['uploaderId'],
            json['uploader_id'],
            json['creatorId'],
            json['creator_id'],
            json['userId'],
            json['user_id'],
            uploader.id,
          ];

          final resolvedId = fallbackIdCandidates
              .whereType<String>()
              .map((value) => value.trim())
              .firstWhere(
                (value) => value.isNotEmpty,
                orElse: () => '',
              );

          if (resolvedId.isNotEmpty) {
            uploader = uploader.copyWith(
              id: resolvedId,
              googleId: resolvedGoogleId.isNotEmpty
                  ? resolvedGoogleId
                  : uploader.googleId,
            );
            print('🔍 VideoModel: Selected uploader ID: $resolvedId');
          } else {
            print(
              '⚠️ VideoModel: Unable to resolve uploader ID, defaulting to placeholder',
            );
          }

          return uploader;
        }(),
        uploadedAt: json['uploadedAt'] != null
            ? DateTime.tryParse(json['uploadedAt'].toString()) ?? DateTime(1970)
            : DateTime(1970),
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
        // **NEW: Parse earnings field**
        earnings: (json['earnings'] is num)
            ? json['earnings'].toDouble()
            : double.tryParse(json['earnings']?.toString() ?? '0.0') ?? 0.0,
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
        // **NEW: Parse original resolution from backend**
        originalResolution: () {
          try {
            if (json['originalResolution'] == null) {
              return null;
            }
            if (json['originalResolution'] is Map<String, dynamic>) {
              return Map<String, dynamic>.from(json['originalResolution']);
            }
            return null;
          } catch (e) {
            print('⚠️ VideoModel: Error parsing originalResolution: $e');
            return null;
          }
        }(),

        videoHash: json['videoHash']?.toString(), // **NEW: Parse video hash**
        episodes: () {
          if (json['episodes'] is List) {
            return (json['episodes'] as List).map((e) {
              final map = Map<String, dynamic>.from(e as Map);
              // Normalize id from _id if needed
              if (map['id'] == null && map['_id'] != null) {
                map['id'] = map['_id'].toString();
              }
              return map;
            }).toList();
          }
          return null;
        }(),
        seriesId: json['seriesId']?.toString(),
        episodeNumber: (json['episodeNumber'] is int)
            ? json['episodeNumber']
            : int.tryParse(json['episodeNumber']?.toString() ?? '0') ?? 0,
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
        if (uploader.googleId != null) 'googleId': uploader.googleId,
        // **FIX: Include totalVideos in persistence so profile stats are correct on cache load**
        if (uploader.totalVideos != null) 'totalVideos': uploader.totalVideos,
      },
      'uploadedAt': uploadedAt.toIso8601String(),
      'likedBy': likedBy,
      'videoType': videoType,
      'aspectRatio': aspectRatio,
      'duration': duration.inSeconds,
      'comments': comments.map((comment) => comment.toJson()).toList(),
      'link': link,
      'earnings': earnings, // **NEW: Include earnings in JSON**
      'hlsMasterPlaylistUrl': hlsMasterPlaylistUrl,
      'hlsPlaylistUrl': hlsPlaylistUrl,
      'hlsVariants': hlsVariants,
      'isHLSEncoded': isHLSEncoded,
      'lowQualityUrl': lowQualityUrl, // 480p URL
      'videoHash': videoHash, // **NEW: Parse video hash**
      'episodes': episodes,
      'seriesId': seriesId,
      'episodeNumber': episodeNumber,
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
    double? earnings, // **NEW: Add earnings to copyWith**
    // **CRITICAL FIX: Add HLS fields to copyWith**
    String? hlsMasterPlaylistUrl,
    String? hlsPlaylistUrl,
    List<Map<String, dynamic>>? hlsVariants,
    bool? isHLSEncoded,
    String? lowQualityUrl, // 480p URL
    String? videoHash, // **NEW: Add videoHash to copyWith**
    List<Map<String, dynamic>>? episodes,
    String? seriesId,
    int? episodeNumber,
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
      earnings:
          earnings ?? this.earnings, // **NEW: Handle earnings in copyWith**
      // **CRITICAL FIX: Handle HLS fields in copyWith**
      hlsMasterPlaylistUrl: hlsMasterPlaylistUrl ?? this.hlsMasterPlaylistUrl,
      hlsPlaylistUrl: hlsPlaylistUrl ?? this.hlsPlaylistUrl,
      hlsVariants: hlsVariants ?? this.hlsVariants,
      isHLSEncoded: isHLSEncoded ?? this.isHLSEncoded,
      lowQualityUrl: lowQualityUrl ?? this.lowQualityUrl, // 480p URL
      videoHash: videoHash ?? this.videoHash, // **NEW: Handle videoHash**
      episodes: episodes ?? this.episodes,
      seriesId: seriesId ?? this.seriesId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
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
    return lowQualityUrl?.isNotEmpty == true ? lowQualityUrl! : videoUrl;
  }
}

class Uploader {
  final String id;
  final String name;
  final String profilePic;
  final String? googleId;
  final int? totalVideos; // **NEW: Total video count from backend**
  final double? earnings; // **NEW: Total earnings from backend**

  Uploader({
    required this.id,
    required this.name,
    required this.profilePic,
    this.googleId,
    this.totalVideos,
    this.earnings,
  });

  factory Uploader.fromJson(Map<String, dynamic> json) {
    try {
      final googleIdCandidates = [
        json['googleId'],
        json['google_id'],
        json['uploaderGoogleId'],
      ];

      String? resolvedGoogleId;
      for (final candidate in googleIdCandidates) {
        if (candidate == null) continue;
        final value = candidate.toString().trim();
        if (value.isNotEmpty) {
          resolvedGoogleId = value;
          break;
        }
      }

      final idCandidates = [
        resolvedGoogleId,
        json['_id'],
        json['id'],
        json['uploaderId'],
        json['uploader_id'],
        json['creatorId'],
        json['creator_id'],
        json['userId'],
        json['user_id'],
      ];

      String resolvedId = '';
      for (final candidate in idCandidates) {
        if (candidate == null) continue;
        final value = candidate.toString().trim();
        if (value.isNotEmpty) {
          resolvedId = value;
          break;
        }
      }

      return Uploader(
        id: resolvedId,
        name: json['name']?.toString() ?? '',
        profilePic: json['profilePic']?.toString() ?? '',
        googleId: resolvedGoogleId,
        totalVideos: json['totalVideos'] is int ? json['totalVideos'] : int.tryParse(json['totalVideos']?.toString() ?? ''),
        earnings: (json['earnings'] is num)
            ? json['earnings'].toDouble()
            : double.tryParse(json['earnings']?.toString() ?? '0.0') ?? 0.0,
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
    String? googleId,
    int? totalVideos,
    double? earnings,
  }) {
    return Uploader(
      id: id ?? this.id,
      name: name ?? this.name,
      profilePic: profilePic ?? this.profilePic,
      googleId: googleId ?? this.googleId,
      totalVideos: totalVideos ?? this.totalVideos,
      earnings: earnings ?? this.earnings,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'profilePic': profilePic,
      if (googleId != null) 'googleId': googleId,
      if (totalVideos != null) 'totalVideos': totalVideos,
      if (earnings != null) 'earnings': earnings,
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
        text: json['text']?.toString() ??
            json['content']?.toString() ??
            json['comment']?.toString() ??
            '',
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
