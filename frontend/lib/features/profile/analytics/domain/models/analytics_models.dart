class CreatorAnalytics {
  final CoreAnalytics core;
  final List<VideoPerformance> topVideos;
  final List<DailyStat> dailyPerformance;
  final AudienceInsights audience;

  CreatorAnalytics({
    required this.core,
    required this.topVideos,
    required this.dailyPerformance,
    required this.audience,
  });

  factory CreatorAnalytics.fromJson(Map<String, dynamic> json) {
    return CreatorAnalytics(
      core: CoreAnalytics.fromJson(json['core'] ?? {}),
      topVideos: (json['topVideos'] as List? ?? [])
          .map((v) => VideoPerformance.fromJson(v))
          .toList(),
      dailyPerformance: (json['dailyPerformance'] as List? ?? [])
          .map((d) => DailyStat.fromJson(d))
          .toList(),
      audience: AudienceInsights.fromJson(json['audience'] ?? {}),
    );
  }
}

class CoreAnalytics {
  final int totalViews;
  final int totalShares;
  final double totalWatchTime; // in minutes
  final int avgWatchDuration; // in seconds
  final double skipRate;
  final int viewsGrowth;
  final int watchTimeGrowth;

  CoreAnalytics({
    required this.totalViews,
    required this.totalShares,
    required this.totalWatchTime,
    required this.avgWatchDuration,
    required this.skipRate,
    required this.viewsGrowth,
    required this.watchTimeGrowth,
  });

  factory CoreAnalytics.fromJson(Map<String, dynamic> json) {
    return CoreAnalytics(
      totalViews: (json['totalViews'] as num?)?.toInt() ?? 0,
      totalShares: (json['totalShares'] as num?)?.toInt() ?? 0,
      totalWatchTime: (json['totalWatchTime'] as num?)?.toDouble() ?? 0.0,
      avgWatchDuration: (json['avgWatchDuration'] as num?)?.toInt() ?? 0,
      skipRate: (json['skipRate'] as num?)?.toDouble() ?? 0.0,
      viewsGrowth: (json['viewsGrowth'] as num?)?.toInt() ?? 0,
      watchTimeGrowth: (json['watchTimeGrowth'] as num?)?.toInt() ?? 0,
    );
  }
}

class VideoPerformance {
  final String id;
  final String title;
  final int views;
  final int shares;
  final double watchTime;

  VideoPerformance({
    required this.id,
    required this.title,
    required this.views,
    required this.shares,
    required this.watchTime,
  });

  factory VideoPerformance.fromJson(Map<String, dynamic> json) {
    return VideoPerformance(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      views: (json['views'] as num?)?.toInt() ?? 0,
      shares: (json['shares'] as num?)?.toInt() ?? 0,
      watchTime: (json['watchTime'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class DailyStat {
  final String date;
  final int views;
  final double watchTime;

  DailyStat({
    required this.date,
    required this.views,
    required this.watchTime,
  });

  factory DailyStat.fromJson(Map<String, dynamic> json) {
    return DailyStat(
      date: json['date'] ?? '',
      views: (json['views'] as num?)?.toInt() ?? 0,
      watchTime: (json['watchTime'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AudienceInsights {
  final List<LocationStat> topLocations;
  final List<ActiveTimeStat> activeTimes;
  final NewVsReturning newVsReturning;

  AudienceInsights({
    required this.topLocations,
    required this.activeTimes,
    required this.newVsReturning,
  });

  factory AudienceInsights.fromJson(Map<String, dynamic> json) {
    return AudienceInsights(
      topLocations: (json['topLocations'] as List? ?? [])
          .map((l) => LocationStat.fromJson(l))
          .toList(),
      activeTimes: (json['activeTimes'] as List? ?? [])
          .map((a) => ActiveTimeStat.fromJson(a))
          .toList(),
      newVsReturning: NewVsReturning.fromJson(json['newVsReturning'] ?? {}),
    );
  }
}

class LocationStat {
  final String name;
  final int value;

  LocationStat({required this.name, required this.value});

  factory LocationStat.fromJson(Map<String, dynamic> json) {
    return LocationStat(
      name: json['name'] ?? '',
      value: (json['value'] as num?)?.toInt() ?? 0,
    );
  }
}

class ActiveTimeStat {
  final int hour;
  final int count;

  ActiveTimeStat({required this.hour, required this.count});

  factory ActiveTimeStat.fromJson(Map<String, dynamic> json) {
    return ActiveTimeStat(
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class NewVsReturning {
  final int newValue;
  final int returning;

  NewVsReturning({required this.newValue, required this.returning});

  factory NewVsReturning.fromJson(Map<String, dynamic> json) {
    return NewVsReturning(
      newValue: (json['new'] as num?)?.toInt() ?? 0,
      returning: (json['returning'] as num?)?.toInt() ?? 0,
    );
  }
}

class RemovedVideo {
  final String id;
  final String videoName;
  final String thumbnailUrl;
  final String reason;
  final DateTime removedAt;
  final DateTime expiresAt;

  RemovedVideo({
    required this.id,
    required this.videoName,
    required this.thumbnailUrl,
    required this.reason,
    required this.removedAt,
    required this.expiresAt,
  });

  factory RemovedVideo.fromJson(Map<String, dynamic> json) {
    return RemovedVideo(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      videoName: json['videoName'] ?? 'Unnamed Video',
      thumbnailUrl: json['thumbnailUrl'] ?? '',
      reason: json['reason'] ?? 'Violation of Guidelines',
      removedAt: json['removedAt'] != null 
          ? DateTime.parse(json['removedAt']) 
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null 
          ? DateTime.parse(json['expiresAt']) 
          : DateTime.now().add(const Duration(days: 3)),
    );
  }

  int get daysLeft {
    final difference = expiresAt.difference(DateTime.now()).inDays;
    return difference < 0 ? 0 : difference;
  }
}
