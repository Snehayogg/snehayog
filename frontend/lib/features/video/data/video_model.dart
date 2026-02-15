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
  bool isLiked;

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
    this.isLiked = false,
  });

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    try {

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

          Uploader uploader;
          if (json['uploader'] is Map<String, dynamic>) {
            final uploaderMap =
                Map<String, dynamic>.from(json['uploader'] as Map);
            uploader = Uploader.fromJson(uploaderMap);
          } else {
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
          } else {
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

            if (json['likedBy'] is List) {
              final likedByList = json['likedBy'] as List;
              final List<String> parsedLikedBy = <String>[];
              
              for (final dynamic item in likedByList) {
                if (item == null) continue;
                
                String idStr = "";
                if (item is String) {
                  idStr = item;
                } else if (item is Map && item.containsKey('\$oid')) {
                  idStr = item['\$oid'].toString();
                } else {
                  idStr = item.toString();
                }
                
                // **ROBUSTNESS: Strip MongoDB ObjectId(...) wrapper if present**
                if (idStr.contains('ObjectId("')) {
                  final start = idStr.indexOf('ObjectId("') + 10;
                  final end = idStr.indexOf('")', start);
                  if (end > start) {
                    idStr = idStr.substring(start, end);
                  }
                }
                
                if (idStr.isNotEmpty) {
                  parsedLikedBy.add(idStr);
                }
              }
              return parsedLikedBy;
            }

            return <String>[];
          } catch (e) {
            return <String>[];
          }
        }(),
        videoType: json['videoType']?.toString() ?? 'reel',
        aspectRatio: (json['aspectRatio'] is num)
            ? json['aspectRatio'].toDouble()
            : double.tryParse(json['aspectRatio']?.toString() ?? '0.5625') ??
                9 / 16,
        duration: Duration(
            seconds: (json['duration'] is num)
                ? (json['duration'] as num).toInt()
                : int.tryParse(json['duration']?.toString() ?? '0') ?? 0),
        link: () {

          // Try multiple possible field names for the link
          final possibleFields = ['link', 'externalLink', 'websiteUrl', 'url'];

          for (final field in possibleFields) {
            if (json.containsKey(field)) {
              final linkValue = json[field]?.toString().trim();
              if (linkValue?.isNotEmpty == true) {
                return linkValue;
              } else {
              }
            } else {
            }
          }

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
                }
              }
              return parsedVariants;
            }

            return null;
          } catch (e) {
            print('âš ï¸ VideoModel: Error parsing hlsVariants: $e');
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
        isLiked: json['isLiked'] == true,
      );
    } catch (e) {
      
      // Return a minimal valid VideoModel instead of crashing the whole feed
      return VideoModel(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? 'error_${DateTime.now().millisecondsSinceEpoch}',
        videoName: 'Content Unavailable',
        videoUrl: '',
        thumbnailUrl: '',
        likes: 0,
        views: 0,
        shares: 0,
        uploader: Uploader(id: 'system', name: 'Vayu', profilePic: ''),
        uploadedAt: DateTime.now(),
        likedBy: [],
        videoType: 'yog',
        aspectRatio: 9/16,
        duration: Duration.zero,
      );
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
      'link': link,
      'earnings': earnings, // **NEW: Include earnings in JSON**
      'hlsMasterPlaylistUrl': hlsMasterPlaylistUrl,
      'hlsPlaylistUrl': hlsPlaylistUrl,
      'hlsVariants': hlsVariants,
      'isHLSEncoded': isHLSEncoded,
      'lowQualityUrl': lowQualityUrl, // 480p URL
      'processingStatus': processingStatus,
      'processingProgress': processingProgress,
      'processingError': processingError,
      'videoHash': videoHash, // **NEW: Parse video hash**
      'episodes': episodes,
      'seriesId': seriesId,
      'episodeNumber': episodeNumber,
      'isLiked': isLiked,
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
    String? link,
    double? earnings, // **NEW: Add earnings to copyWith**
    // **CRITICAL FIX: Add HLS fields to copyWith**
    String? hlsMasterPlaylistUrl,
    String? hlsPlaylistUrl,
    List<Map<String, dynamic>>? hlsVariants,
    bool? isHLSEncoded,
    String? lowQualityUrl, // 480p URL
    String? processingStatus,
    int? processingProgress,
    String? processingError,
    String? videoHash, // **NEW: Add videoHash to copyWith**
    List<Map<String, dynamic>>? episodes,
    String? seriesId,
    int? episodeNumber,
    bool? isLiked,
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
      link: link ?? this.link,
      earnings:
          earnings ?? this.earnings, // **NEW: Handle earnings in copyWith**
      // **CRITICAL FIX: Handle HLS fields in copyWith**
      hlsMasterPlaylistUrl: hlsMasterPlaylistUrl ?? this.hlsMasterPlaylistUrl,
      hlsPlaylistUrl: hlsPlaylistUrl ?? this.hlsPlaylistUrl,
      hlsVariants: hlsVariants ?? this.hlsVariants,
      isHLSEncoded: isHLSEncoded ?? this.isHLSEncoded,
      lowQualityUrl: lowQualityUrl ?? this.lowQualityUrl, // 480p URL
      processingStatus: processingStatus ?? this.processingStatus,
      processingProgress: processingProgress ?? this.processingProgress,
      processingError: processingError ?? this.processingError,
      videoHash: videoHash ?? this.videoHash, // **NEW: Handle videoHash**
      episodes: episodes ?? this.episodes,
      seriesId: seriesId ?? this.seriesId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      isLiked: isLiked ?? this.isLiked,
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
  final String? mongoId; // **NEW: Raw MongoDB ObjectId for API calls**
  final int? totalVideos; // **NEW: Total video count from backend**
  final double? earnings; // **NEW: Total earnings from backend**

  Uploader({
    required this.id,
    required this.name,
    required this.profilePic,
    this.googleId,
    this.mongoId,
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

      // Extract raw MongoDB ObjectId
      final mongoId = json['_id']?.toString();

      return Uploader(
        id: resolvedId,
        name: json['name']?.toString() ?? '',
        profilePic: json['profilePic']?.toString() ?? '',
        googleId: resolvedGoogleId,
        mongoId: mongoId,
        totalVideos: json['totalVideos'] is int ? json['totalVideos'] : int.tryParse(json['totalVideos']?.toString() ?? ''),
        earnings: (json['earnings'] is num)
            ? json['earnings'].toDouble()
            : double.tryParse(json['earnings']?.toString() ?? '0.0') ?? 0.0,
      );
    } catch (e) {
      rethrow;
    }
  }

  Uploader copyWith({
    String? id,
    String? name,
    String? profilePic,
    String? googleId,
    String? mongoId,
    int? totalVideos,
    double? earnings,
  }) {
    return Uploader(
      id: id ?? this.id,
      name: name ?? this.name,
      profilePic: profilePic ?? this.profilePic,
      googleId: googleId ?? this.googleId,
      mongoId: mongoId ?? this.mongoId,
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
      if (mongoId != null) '_id': mongoId,
      if (totalVideos != null) 'totalVideos': totalVideos,
      if (earnings != null) 'earnings': earnings,
    };
  }
}



