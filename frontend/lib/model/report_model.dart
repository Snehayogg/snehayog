class ReportModel {
  final String id;
  final String reporterId;
  final String reporterName;
  final String reporterProfilePic;
  final String? reportedUserId;
  final String? reportedUserName;
  final String? reportedUserProfilePic;
  final String? reportedVideoId;
  final String? reportedVideoTitle;
  final String? reportedCommentId;
  final String? reportedCommentContent;
  final String type;
  final String reason;
  final String description;
  final String priority;
  final String severity;
  final String status;
  final List<Evidence> evidence;
  final String? assignedModeratorId;
  final String? assignedModeratorName;
  final String? moderatorNotes;
  final String? actionTaken;
  final String? resolution;
  final DateTime? reviewedAt;
  final DateTime? resolvedAt;
  final bool isRepeatReport;
  final List<String> relatedReportIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  ReportModel({
    required this.id,
    required this.reporterId,
    required this.reporterName,
    required this.reporterProfilePic,
    this.reportedUserId,
    this.reportedUserName,
    this.reportedUserProfilePic,
    this.reportedVideoId,
    this.reportedVideoTitle,
    this.reportedCommentId,
    this.reportedCommentContent,
    required this.type,
    required this.reason,
    required this.description,
    required this.priority,
    required this.severity,
    required this.status,
    required this.evidence,
    this.assignedModeratorId,
    this.assignedModeratorName,
    this.moderatorNotes,
    this.actionTaken,
    this.resolution,
    this.reviewedAt,
    this.resolvedAt,
    required this.isRepeatReport,
    required this.relatedReportIds,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    try {
      return ReportModel(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
        reporterId: json['reporter']?['_id']?.toString() ??
            json['reporter']?['googleId']?.toString() ??
            '',
        reporterName: json['reporter']?['name']?.toString() ?? '',
        reporterProfilePic: json['reporter']?['profilePic']?.toString() ?? '',
        reportedUserId: json['reportedUser']?['_id']?.toString(),
        reportedUserName: json['reportedUser']?['name']?.toString(),
        reportedUserProfilePic: json['reportedUser']?['profilePic']?.toString(),
        reportedVideoId: json['reportedVideo']?['_id']?.toString(),
        reportedVideoTitle: json['reportedVideo']?['title']?.toString(),
        reportedCommentId: json['reportedComment']?['_id']?.toString(),
        reportedCommentContent: json['reportedComment']?['content']?.toString(),
        type: json['type']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        priority: json['priority']?.toString() ?? 'medium',
        severity: json['severity']?.toString() ?? 'moderate',
        status: json['status']?.toString() ?? 'pending',
        evidence: (json['evidence'] as List<dynamic>?)
                ?.map((e) => Evidence.fromJson(e))
                .toList() ??
            [],
        assignedModeratorId: json['assignedModerator']?['_id']?.toString(),
        assignedModeratorName: json['assignedModerator']?['name']?.toString(),
        moderatorNotes: json['moderatorNotes']?.toString(),
        actionTaken: json['actionTaken']?.toString(),
        resolution: json['resolution']?.toString(),
        reviewedAt: json['reviewedAt'] != null
            ? DateTime.tryParse(json['reviewedAt'].toString())
            : null,
        resolvedAt: json['resolvedAt'] != null
            ? DateTime.tryParse(json['resolvedAt'].toString())
            : null,
        isRepeatReport: json['isRepeatReport'] ?? false,
        relatedReportIds: (json['relatedReports'] as List<dynamic>?)
                ?.map((id) => id.toString())
                .toList() ??
            [],
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
    } catch (e) {
      print('❌ ReportModel.fromJson Error: $e');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reporterId': reporterId,
      'reporterName': reporterName,
      'reporterProfilePic': reporterProfilePic,
      'reportedUserId': reportedUserId,
      'reportedUserName': reportedUserName,
      'reportedUserProfilePic': reportedUserProfilePic,
      'reportedVideoId': reportedVideoId,
      'reportedVideoTitle': reportedVideoTitle,
      'reportedCommentId': reportedCommentId,
      'reportedCommentContent': reportedCommentContent,
      'type': type,
      'reason': reason,
      'description': description,
      'priority': priority,
      'severity': severity,
      'status': status,
      'evidence': evidence.map((e) => e.toJson()).toList(),
      'assignedModeratorId': assignedModeratorId,
      'assignedModeratorName': assignedModeratorName,
      'moderatorNotes': moderatorNotes,
      'actionTaken': actionTaken,
      'resolution': resolution,
      'reviewedAt': reviewedAt?.toIso8601String(),
      'resolvedAt': resolvedAt?.toIso8601String(),
      'isRepeatReport': isRepeatReport,
      'relatedReportIds': relatedReportIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  ReportModel copyWith({
    String? id,
    String? reporterId,
    String? reporterName,
    String? reporterProfilePic,
    String? reportedUserId,
    String? reportedUserName,
    String? reportedUserProfilePic,
    String? reportedVideoId,
    String? reportedVideoTitle,
    String? reportedCommentId,
    String? reportedCommentContent,
    String? type,
    String? reason,
    String? description,
    String? priority,
    String? severity,
    String? status,
    List<Evidence>? evidence,
    String? assignedModeratorId,
    String? assignedModeratorName,
    String? moderatorNotes,
    String? actionTaken,
    String? resolution,
    DateTime? reviewedAt,
    DateTime? resolvedAt,
    bool? isRepeatReport,
    List<String>? relatedReportIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReportModel(
      id: id ?? this.id,
      reporterId: reporterId ?? this.reporterId,
      reporterName: reporterName ?? this.reporterName,
      reporterProfilePic: reporterProfilePic ?? this.reporterProfilePic,
      reportedUserId: reportedUserId ?? this.reportedUserId,
      reportedUserName: reportedUserName ?? this.reportedUserName,
      reportedUserProfilePic:
          reportedUserProfilePic ?? this.reportedUserProfilePic,
      reportedVideoId: reportedVideoId ?? this.reportedVideoId,
      reportedVideoTitle: reportedVideoTitle ?? this.reportedVideoTitle,
      reportedCommentId: reportedCommentId ?? this.reportedCommentId,
      reportedCommentContent:
          reportedCommentContent ?? this.reportedCommentContent,
      type: type ?? this.type,
      reason: reason ?? this.reason,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      evidence: evidence ?? this.evidence,
      assignedModeratorId: assignedModeratorId ?? this.assignedModeratorId,
      assignedModeratorName:
          assignedModeratorName ?? this.assignedModeratorName,
      moderatorNotes: moderatorNotes ?? this.moderatorNotes,
      actionTaken: actionTaken ?? this.actionTaken,
      resolution: resolution ?? this.resolution,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      isRepeatReport: isRepeatReport ?? this.isRepeatReport,
      relatedReportIds: relatedReportIds ?? this.relatedReportIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper methods
  String get formattedCreatedAt => _formatDate(createdAt);
  String get formattedReviewedAt =>
      reviewedAt != null ? _formatDate(reviewedAt!) : '';
  String get formattedResolvedAt =>
      resolvedAt != null ? _formatDate(resolvedAt!) : '';

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String get statusDisplayName {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'under_review':
        return 'Under Review';
      case 'resolved':
        return 'Resolved';
      case 'dismissed':
        return 'Dismissed';
      case 'escalated':
        return 'Escalated';
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
      case 'urgent':
        return 'Urgent';
      default:
        return priority;
    }
  }

  String get severityDisplayName {
    switch (severity) {
      case 'minor':
        return 'Minor';
      case 'moderate':
        return 'Moderate';
      case 'severe':
        return 'Severe';
      case 'critical':
        return 'Critical';
      default:
        return severity;
    }
  }

  String get typeDisplayName {
    switch (type) {
      case 'spam':
        return 'Spam';
      case 'harassment':
        return 'Harassment';
      case 'hate_speech':
        return 'Hate Speech';
      case 'inappropriate_content':
        return 'Inappropriate Content';
      case 'violence':
        return 'Violence';
      case 'nudity':
        return 'Nudity';
      case 'copyright_violation':
        return 'Copyright Violation';
      case 'fake_account':
        return 'Fake Account';
      case 'scam':
        return 'Scam';
      case 'underage_user':
        return 'Underage User';
      case 'other':
        return 'Other';
      default:
        return type;
    }
  }

  String get actionTakenDisplayName {
    switch (actionTaken) {
      case 'no_action':
        return 'No Action';
      case 'warning_issued':
        return 'Warning Issued';
      case 'content_removed':
        return 'Content Removed';
      case 'user_suspended':
        return 'User Suspended';
      case 'user_banned':
        return 'User Banned';
      case 'account_restricted':
        return 'Account Restricted';
      case 'content_hidden':
        return 'Content Hidden';
      case 'escalated_to_legal':
        return 'Escalated to Legal';
      default:
        return actionTaken ?? '';
    }
  }

  // Get what was reported (for display purposes)
  String get reportedContent {
    if (reportedVideoTitle != null) {
      return 'Video: $reportedVideoTitle';
    } else if (reportedUserName != null) {
      return 'User: $reportedUserName';
    } else if (reportedCommentContent != null) {
      return 'Comment: ${reportedCommentContent!.substring(0, 50)}...';
    }
    return 'Unknown content';
  }
}

class Evidence {
  final String url;
  final String? description;

  Evidence({
    required this.url,
    this.description,
  });

  factory Evidence.fromJson(Map<String, dynamic> json) {
    return Evidence(
      url: json['type']?.toString() ?? json['url']?.toString() ?? '',
      description: json['description']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': url,
      'description': description,
    };
  }
}

// Report creation request model
class ReportCreationRequest {
  final String type;
  final String reason;
  final String description;
  final String? priority;
  final String? severity;
  final String? reportedUserId;
  final String? reportedVideoId;
  final String? reportedCommentId;
  final List<Evidence> evidence;

  ReportCreationRequest({
    required this.type,
    required this.reason,
    required this.description,
    this.priority,
    this.severity,
    this.reportedUserId,
    this.reportedVideoId,
    this.reportedCommentId,
    required this.evidence,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'reason': reason,
      'description': description,
      if (priority != null) 'priority': priority,
      if (severity != null) 'severity': severity,
      if (reportedUserId != null) 'reportedUser': reportedUserId,
      if (reportedVideoId != null) 'reportedVideo': reportedVideoId,
      if (reportedCommentId != null) 'reportedComment': reportedCommentId,
      'evidence': evidence.map((e) => e.toJson()).toList(),
    };
  }
}

// Report stats model
class ReportStats {
  final int total;
  final int pending;
  final int underReview;
  final int resolved;
  final int dismissed;
  final List<TypeStat> byType;
  final List<PriorityStat> byPriority;
  final List<SeverityStat> bySeverity;

  ReportStats({
    required this.total,
    required this.pending,
    required this.underReview,
    required this.resolved,
    required this.dismissed,
    required this.byType,
    required this.byPriority,
    required this.bySeverity,
  });

  factory ReportStats.fromJson(Map<String, dynamic> json) {
    return ReportStats(
      total: json['total'] ?? 0,
      pending: json['pending'] ?? 0,
      underReview: json['underReview'] ?? 0,
      resolved: json['resolved'] ?? 0,
      dismissed: json['dismissed'] ?? 0,
      byType: (json['byType'] as List<dynamic>?)
              ?.map((item) => TypeStat.fromJson(item))
              .toList() ??
          [],
      byPriority: (json['byPriority'] as List<dynamic>?)
              ?.map((item) => PriorityStat.fromJson(item))
              .toList() ??
          [],
      bySeverity: (json['bySeverity'] as List<dynamic>?)
              ?.map((item) => SeverityStat.fromJson(item))
              .toList() ??
          [],
    );
  }
}

class PriorityStat {
  final String priority;
  final int count;

  PriorityStat({
    required this.priority,
    required this.count,
  });

  factory PriorityStat.fromJson(Map<String, dynamic> json) {
    return PriorityStat(
      priority: json['_id']?.toString() ?? '',
      count: json['count'] ?? 0,
    );
  }
}

class SeverityStat {
  final String severity;
  final int count;

  SeverityStat({
    required this.severity,
    required this.count,
  });

  factory SeverityStat.fromJson(Map<String, dynamic> json) {
    return SeverityStat(
      severity: json['_id']?.toString() ?? '',
      count: json['count'] ?? 0,
    );
  }
}

// Reuse TypeStat from feedback model
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
