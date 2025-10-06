class FeedbackModel {
  final String id;
  final String userId;
  final String userName;
  final String userProfilePic;
  final String type;
  final String category;
  final String title;
  final String description;
  final String priority;
  final String status;
  final int rating;
  final DeviceInfo? deviceInfo;
  final List<Screenshot> screenshots;
  final String? relatedVideoId;
  final String? relatedVideoTitle;
  final String? relatedUserId;
  final String? relatedUserName;
  final List<String> tags;
  final String? adminNotes;
  final String? assignedToId;
  final String? assignedToName;
  final String? resolution;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  FeedbackModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userProfilePic,
    required this.type,
    required this.category,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.rating,
    this.deviceInfo,
    required this.screenshots,
    this.relatedVideoId,
    this.relatedVideoTitle,
    this.relatedUserId,
    this.relatedUserName,
    required this.tags,
    this.adminNotes,
    this.assignedToId,
    this.assignedToName,
    this.resolution,
    this.resolvedAt,
    this.closedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FeedbackModel.fromJson(Map<String, dynamic> json) {
    try {
      return FeedbackModel(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
        userId: json['user']?['_id']?.toString() ??
            json['user']?['googleId']?.toString() ??
            json['user']?['id']?.toString() ??
            '',
        userName: json['user']?['name']?.toString() ?? '',
        userProfilePic: json['user']?['profilePic']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        priority: json['priority']?.toString() ?? 'medium',
        status: json['status']?.toString() ?? 'open',
        rating: (json['rating'] is int)
            ? json['rating']
            : int.tryParse(json['rating']?.toString() ?? '0') ?? 0,
        deviceInfo: json['deviceInfo'] != null
            ? DeviceInfo.fromJson(json['deviceInfo'])
            : null,
        screenshots: (json['screenshots'] as List<dynamic>?)
                ?.map((s) => Screenshot.fromJson(s))
                .toList() ??
            [],
        relatedVideoId: json['relatedVideo']?['_id']?.toString(),
        relatedVideoTitle: json['relatedVideo']?['title']?.toString(),
        relatedUserId: json['relatedUser']?['_id']?.toString(),
        relatedUserName: json['relatedUser']?['name']?.toString(),
        tags: (json['tags'] as List<dynamic>?)
                ?.map((tag) => tag.toString())
                .toList() ??
            [],
        adminNotes: json['adminNotes']?.toString(),
        assignedToId: json['assignedTo']?['_id']?.toString(),
        assignedToName: json['assignedTo']?['name']?.toString(),
        resolution: json['resolution']?.toString(),
        resolvedAt: json['resolvedAt'] != null
            ? DateTime.tryParse(json['resolvedAt'].toString())
            : null,
        closedAt: json['closedAt'] != null
            ? DateTime.tryParse(json['closedAt'].toString())
            : null,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
    } catch (e) {
      print('❌ FeedbackModel.fromJson Error: $e');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userProfilePic': userProfilePic,
      'type': type,
      'category': category,
      'title': title,
      'description': description,
      'priority': priority,
      'status': status,
      'rating': rating,
      'deviceInfo': deviceInfo?.toJson(),
      'screenshots': screenshots.map((s) => s.toJson()).toList(),
      'relatedVideoId': relatedVideoId,
      'relatedVideoTitle': relatedVideoTitle,
      'relatedUserId': relatedUserId,
      'relatedUserName': relatedUserName,
      'tags': tags,
      'adminNotes': adminNotes,
      'assignedToId': assignedToId,
      'assignedToName': assignedToName,
      'resolution': resolution,
      'resolvedAt': resolvedAt?.toIso8601String(),
      'closedAt': closedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  FeedbackModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userProfilePic,
    String? type,
    String? category,
    String? title,
    String? description,
    String? priority,
    String? status,
    int? rating,
    DeviceInfo? deviceInfo,
    List<Screenshot>? screenshots,
    String? relatedVideoId,
    String? relatedVideoTitle,
    String? relatedUserId,
    String? relatedUserName,
    List<String>? tags,
    String? adminNotes,
    String? assignedToId,
    String? assignedToName,
    String? resolution,
    DateTime? resolvedAt,
    DateTime? closedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FeedbackModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userProfilePic: userProfilePic ?? this.userProfilePic,
      type: type ?? this.type,
      category: category ?? this.category,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      rating: rating ?? this.rating,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      screenshots: screenshots ?? this.screenshots,
      relatedVideoId: relatedVideoId ?? this.relatedVideoId,
      relatedVideoTitle: relatedVideoTitle ?? this.relatedVideoTitle,
      relatedUserId: relatedUserId ?? this.relatedUserId,
      relatedUserName: relatedUserName ?? this.relatedUserName,
      tags: tags ?? this.tags,
      adminNotes: adminNotes ?? this.adminNotes,
      assignedToId: assignedToId ?? this.assignedToId,
      assignedToName: assignedToName ?? this.assignedToName,
      resolution: resolution ?? this.resolution,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      closedAt: closedAt ?? this.closedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper methods
  String get formattedCreatedAt => _formatDate(createdAt);
  String get formattedResolvedAt =>
      resolvedAt != null ? _formatDate(resolvedAt!) : '';

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String get statusDisplayName {
    switch (status) {
      case 'open':
        return 'Open';
      case 'in_progress':
        return 'In Progress';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      case 'duplicate':
        return 'Duplicate';
      default:
        return status;
    }
  }

  String get priorityDisplayName {
    switch (priority) {
      case 'low':
        return 'Low';
      case 'medium':
        return 'Medium';
      case 'high':
        return 'High';
      case 'critical':
        return 'Critical';
      default:
        return priority;
    }
  }

  String get typeDisplayName {
    switch (type) {
      case 'bug_report':
        return 'Bug Report';
      case 'feature_request':
        return 'Feature Request';
      case 'general_feedback':
        return 'General Feedback';
      case 'user_experience':
        return 'User Experience';
      case 'content_issue':
        return 'Content Issue';
      default:
        return type;
    }
  }

  String get categoryDisplayName {
    switch (category) {
      case 'video_playback':
        return 'Video Playback';
      case 'upload_issues':
        return 'Upload Issues';
      case 'ui_ux':
        return 'UI/UX';
      case 'performance':
        return 'Performance';
      case 'monetization':
        return 'Monetization';
      case 'social_features':
        return 'Social Features';
      case 'other':
        return 'Other';
      default:
        return category;
    }
  }
}

class DeviceInfo {
  final String? platform;
  final String? version;
  final String? model;
  final String? appVersion;

  DeviceInfo({
    this.platform,
    this.version,
    this.model,
    this.appVersion,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      platform: json['platform']?.toString(),
      version: json['version']?.toString(),
      model: json['model']?.toString(),
      appVersion: json['appVersion']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'platform': platform,
      'version': version,
      'model': model,
      'appVersion': appVersion,
    };
  }
}

class Screenshot {
  final String url;
  final String? caption;

  Screenshot({
    required this.url,
    this.caption,
  });

  factory Screenshot.fromJson(Map<String, dynamic> json) {
    return Screenshot(
      url: json['type']?.toString() ?? json['url']?.toString() ?? '',
      caption: json['caption']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': url,
      'caption': caption,
    };
  }
}

// Feedback creation request model
class FeedbackCreationRequest {
  final String type;
  final String category;
  final String title;
  final String description;
  final int rating;
  final String? priority;
  final String? relatedVideoId;
  final String? relatedUserId;
  final DeviceInfo? deviceInfo;
  final List<String> tags;

  FeedbackCreationRequest({
    required this.type,
    required this.category,
    required this.title,
    required this.description,
    required this.rating,
    this.priority,
    this.relatedVideoId,
    this.relatedUserId,
    this.deviceInfo,
    required this.tags,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'category': category,
      'title': title,
      'description': description,
      'rating': rating,
      if (priority != null) 'priority': priority,
      if (relatedVideoId != null) 'relatedVideo': relatedVideoId,
      if (relatedUserId != null) 'relatedUser': relatedUserId,
      if (deviceInfo != null) 'deviceInfo': deviceInfo!.toJson(),
      'tags': tags,
    };
  }
}

// Feedback stats model
class FeedbackStats {
  final int total;
  final int open;
  final int inProgress;
  final int resolved;
  final double averageRating;
  final List<TypeStat> byType;
  final List<CategoryStat> byCategory;

  FeedbackStats({
    required this.total,
    required this.open,
    required this.inProgress,
    required this.resolved,
    required this.averageRating,
    required this.byType,
    required this.byCategory,
  });

  factory FeedbackStats.fromJson(Map<String, dynamic> json) {
    return FeedbackStats(
      total: json['total'] ?? 0,
      open: json['open'] ?? 0,
      inProgress: json['inProgress'] ?? 0,
      resolved: json['resolved'] ?? 0,
      averageRating: (json['averageRating'] ?? 0.0).toDouble(),
      byType: (json['byType'] as List<dynamic>?)
              ?.map((item) => TypeStat.fromJson(item))
              .toList() ??
          [],
      byCategory: (json['byCategory'] as List<dynamic>?)
              ?.map((item) => CategoryStat.fromJson(item))
              .toList() ??
          [],
    );
  }
}

class TypeStat {
  final String type;
  final int count;

  TypeStat({
    required this.type,
    required this.count,
  });

  factory TypeStat.fromJson(Map<String, dynamic> json) {
    return TypeStat(
      type: json['_id']?.toString() ?? '',
      count: json['count'] ?? 0,
    );
  }
}

class CategoryStat {
  final String category;
  final int count;

  CategoryStat({
    required this.category,
    required this.count,
  });

  factory CategoryStat.fromJson(Map<String, dynamic> json) {
    return CategoryStat(
      category: json['_id']?.toString() ?? '',
      count: json['count'] ?? 0,
    );
  }
}
