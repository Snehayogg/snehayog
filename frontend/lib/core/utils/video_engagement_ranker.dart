import 'dart:math' as math;

import 'package:vayu/model/video_model.dart';
import 'package:vayu/utils/app_logger.dart';

class VideoEngagementRanker {
  VideoEngagementRanker._();

  static final math.Random _random = math.Random();

  static List<VideoModel> rankVideos(List<VideoModel> videos) {
    if (videos.length <= 1) {
      return List<VideoModel>.from(videos);
    }

    final stats = _EngagementStats.fromVideos(videos);
    final ranked = <_RankedVideo>[];

    for (final video in videos) {
      final score = _computeEngagementScore(video, stats);
      final weight = score > 0 ? score : 1e-6;
      final randomValue = _random.nextDouble().clamp(1e-9, 0.999999999);
      final key = -math.log(randomValue) / weight;
      ranked.add(_RankedVideo(video: video, score: score, key: key));
    }

    ranked.sort((a, b) => a.key.compareTo(b.key));

    AppLogger.log(
        '🎯 VideoEngagementRanker: Ranked ${ranked.length} videos by engagement');
    for (var i = 0; i < ranked.length; i++) {
      final entry = ranked[i];
      AppLogger.log(
          '   ${i + 1}. ${entry.video.videoName} • score=${entry.score.toStringAsFixed(4)}');
    }

    return ranked.map((entry) => entry.video).toList();
  }

  static double _computeEngagementScore(
      VideoModel video, _EngagementStats stats) {
    final watchTimeValue = _estimateWatchTime(video);
    final interactionValue = _interactionCount(video);
    final shareValue = video.shares.toDouble().clamp(0.0, double.infinity);
    final adEngagementValue = video.earnings.clamp(0.0, double.infinity);

    final watchTimeScore = _normalize(watchTimeValue, stats.maxWatchTime);
    final interactionScore =
        _normalize(interactionValue, stats.maxInteractionCount);
    final shareScore = _normalize(shareValue, stats.maxShareCount);
    final adScore = _normalize(adEngagementValue, stats.maxAdEngagement);

    return (0.60 * watchTimeScore) +
        (0.10 * interactionScore) +
        (0.25 * shareScore) +
        (0.05 * adScore);
  }

  static double _estimateWatchTime(VideoModel video) {
    final durationSeconds = video.duration.inSeconds;
    final clampedDuration = durationSeconds.clamp(1, 60 * 60).toDouble();
    final views = video.views;
    final clampedViews = views.clamp(0, 1000000000).toDouble();
    return clampedDuration * clampedViews;
  }

  static double _interactionCount(VideoModel video) {
    final likes = video.likes.clamp(0, 1000000000).toDouble();
    final comments = video.comments.length.clamp(0, 1000000000).toDouble();
    return likes + comments;
  }

  static double _normalize(double value, double maxValue) {
    if (maxValue <= 0) return 0;
    return (value / maxValue).clamp(0.0, 1.0).toDouble();
  }
}

class _EngagementStats {
  final double maxWatchTime;
  final double maxInteractionCount;
  final double maxShareCount;
  final double maxAdEngagement;

  _EngagementStats({
    required this.maxWatchTime,
    required this.maxInteractionCount,
    required this.maxShareCount,
    required this.maxAdEngagement,
  });

  factory _EngagementStats.fromVideos(List<VideoModel> videos) {
    double maxWatch = 0;
    double maxInteraction = 0;
    double maxShare = 0;
    double maxAd = 0;

    for (final video in videos) {
      maxWatch =
          math.max(maxWatch, VideoEngagementRanker._estimateWatchTime(video));
      maxInteraction = math.max(
          maxInteraction, VideoEngagementRanker._interactionCount(video));
      maxShare = math.max(
          maxShare, video.shares.toDouble().clamp(0.0, double.infinity));
      maxAd = math.max(maxAd, video.earnings.clamp(0.0, double.infinity));
    }

    return _EngagementStats(
      maxWatchTime: maxWatch,
      maxInteractionCount: maxInteraction,
      maxShareCount: maxShare,
      maxAdEngagement: maxAd,
    );
  }
}

class _RankedVideo {
  final VideoModel video;
  final double score;
  final double key;

  _RankedVideo({
    required this.video,
    required this.score,
    required this.key,
  });
}
