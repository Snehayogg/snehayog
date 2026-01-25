import 'dart:math' as math;

import 'package:vayu/model/video_model.dart';
import 'package:vayu/utils/app_logger.dart';

class VideoEngagementRanker {
  VideoEngagementRanker._();

  static List<VideoModel> rankVideos(List<VideoModel> videos) {
    if (videos.length <= 1) {
      return List<VideoModel>.from(videos);
    }

    final stats = _EngagementStats.fromVideos(videos);
    final recencyStats = _RecencyStats.fromVideos(videos);
    final ranked = <_RankedVideo>[];

    for (final video in videos) {
      final engagementScore = _computeEngagementScore(video, stats);
      final recencyScore = _computeRecencyScore(video, recencyStats);

      ranked.add(
        _RankedVideo(
          video: video,
          score: 0.0, // Not used in new algorithm
          engagementScore: engagementScore,
          recencyScore: recencyScore,
          key: 0.0, // Not used in new algorithm
        ),
      );
    }

    // **FIXED: FIRST PRIORITY = LATEST VIDEOS**
    // Sort by recency first (newest first), then use engagement as tie-breaker
    ranked.sort((a, b) {
      // Primary sort: by recency (newest first) - this is FIRST PRIORITY
      final recencyCompare = b.recencyScore.compareTo(a.recencyScore);
      if (recencyCompare != 0) {
        return recencyCompare;
      }

      // Secondary sort: by engagement (higher engagement first) - tie-breaker for same recency
      return b.engagementScore.compareTo(a.engagementScore);
    });

    AppLogger.log(
        '🎯 VideoEngagementRanker: Ranked ${ranked.length} videos (FIRST PRIORITY: Latest videos)');
    for (var i = 0; i < ranked.length; i++) {
      final entry = ranked[i];
      final videoAge = DateTime.now().difference(entry.video.uploadedAt);
      AppLogger.log(
          '   ${i + 1}. ${entry.video.videoName} • age=${videoAge.inHours}h • recency=${entry.recencyScore.toStringAsFixed(3)} • engagement=${entry.engagementScore.toStringAsFixed(3)}');
    }

    return ranked.map((entry) => entry.video).toList();
  }

  static double _computeEngagementScore(
    VideoModel video,
    _EngagementStats stats,
  ) {
    final watchTimeValue = _estimateWatchTime(video);
    final likesValue = video.likes.clamp(0, 1000000000).toDouble();
    final sharesValue = video.shares.toDouble().clamp(0.0, double.infinity);

    final watchTimeScore = _normalize(watchTimeValue, stats.maxWatchTime);
    final likeScore = _normalize(likesValue, stats.maxLikes);
    final shareScore = _normalize(sharesValue, stats.maxShares);

    // **NEW WEIGHTS (requested):**
    // 50% watch time, 20% shares, 30% likes
    return (0.50 * watchTimeScore) +
        (0.20 * shareScore) +
        (0.30 * likeScore);
  }

  static double _estimateWatchTime(VideoModel video) {
    // **SIMPLIFIED: Use only duration as a proxy for watch potential.**
    // We intentionally do NOT multiply by views here to avoid over‑boosting
    // already-popular videos; views can be used separately if needed.
    final durationSeconds = video.duration.inSeconds;
    final clampedDuration = durationSeconds.clamp(1, 60 * 60).toDouble();
    return clampedDuration;
  }

  /// **RECENCY SCORE: 0 (oldest) → 1 (newest)**
  static double _computeRecencyScore(
    VideoModel video,
    _RecencyStats stats,
  ) {
    if (stats.maxMillis <= stats.minMillis) {
      // All videos have same timestamp; treat them as equally recent
      return 1.0;
    }

    final millis = video.uploadedAt.millisecondsSinceEpoch.toDouble();
    final clampedMillis = millis.clamp(stats.minMillis, stats.maxMillis);
    final span = stats.maxMillis - stats.minMillis;
    return ((clampedMillis - stats.minMillis) / span)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static double _normalize(double value, double maxValue) {
    if (maxValue <= 0) return 0;
    return (value / maxValue).clamp(0.0, 1.0).toDouble();
  }
}

class _EngagementStats {
  final double maxWatchTime;
  final double maxLikes;
  final double maxShares;

  _EngagementStats({
    required this.maxWatchTime,
    required this.maxLikes,
    required this.maxShares,
  });

  factory _EngagementStats.fromVideos(List<VideoModel> videos) {
    double maxWatch = 0;
    double maxLikes = 0;
    double maxShares = 0;

    for (final video in videos) {
      maxWatch =
          math.max(maxWatch, VideoEngagementRanker._estimateWatchTime(video));
      maxLikes =
          math.max(maxLikes, video.likes.clamp(0, 1000000000).toDouble());
      maxShares = math.max(
          maxShares, video.shares.toDouble().clamp(0.0, double.infinity));
    }

    return _EngagementStats(
      maxWatchTime: maxWatch,
      maxLikes: maxLikes,
      maxShares: maxShares,
    );
  }
}

class _RankedVideo {
  final VideoModel video;
  final double score;
  final double engagementScore;
  final double recencyScore;
  final double key;

  _RankedVideo({
    required this.video,
    required this.score,
    required this.engagementScore,
    required this.recencyScore,
    required this.key,
  });
}

/// **Recency stats: track min/max upload timestamps for normalization**
class _RecencyStats {
  final double minMillis;
  final double maxMillis;

  _RecencyStats({
    required this.minMillis,
    required this.maxMillis,
  });

  factory _RecencyStats.fromVideos(List<VideoModel> videos) {
    if (videos.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch.toDouble();
      return _RecencyStats(minMillis: now, maxMillis: now);
    }

    double minMillis = double.maxFinite;
    double maxMillis = 0;

    for (final video in videos) {
      final millis = video.uploadedAt.millisecondsSinceEpoch.toDouble();
      if (millis < minMillis) minMillis = millis;
      if (millis > maxMillis) maxMillis = millis;
    }

    if (minMillis == double.maxFinite) {
      final now = DateTime.now().millisecondsSinceEpoch.toDouble();
      minMillis = now;
      maxMillis = now;
    }

    return _RecencyStats(minMillis: minMillis, maxMillis: maxMillis);
  }
}
