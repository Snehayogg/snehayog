import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/services/video_screen_logger.dart';

/// Service to manage video banner ads
class VideoAdService {
  // AdMob banner ads
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  final Map<int, BannerAd> _videoBannerAds = {};
  final Map<int, bool> _videoAdLoaded = {};
  final Map<int, String> _videoAdUnitIds = {};

  // Getters
  BannerAd? get bannerAd => _bannerAd;
  bool get isBannerAdLoaded => _isBannerAdLoaded;
  Map<int, BannerAd> get videoBannerAds => _videoBannerAds;
  Map<int, bool> get videoAdLoaded => _videoAdLoaded;

  /// Initialize main banner ad
  Future<void> initializeBannerAd() async {
    try {
      VideoScreenLogger.logAdInit();

      // Create banner ad with custom listener
      _bannerAd = BannerAd(
        adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Test ad unit ID
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            VideoScreenLogger.logAdInitSuccess();
            _isBannerAdLoaded = true;
          },
          onAdFailedToLoad: (ad, error) {
            VideoScreenLogger.logAdInitError(error.message);
            _isBannerAdLoaded = false;
            // Retry after 5 seconds
            Future.delayed(const Duration(seconds: 5), () {
              if (!_isBannerAdLoaded) {
                refreshBannerAd();
              }
            });
          },
          onAdOpened: (ad) {
            VideoScreenLogger.logInfo('Banner ad opened');
          },
          onAdClosed: (ad) {
            VideoScreenLogger.logInfo('Banner ad closed');
          },
        ),
      );

      // Load the ad
      await _bannerAd!.load();
    } catch (e) {
      VideoScreenLogger.logAdInitError(e.toString());
      // Retry after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isBannerAdLoaded) {
          refreshBannerAd();
        }
      });
    }
  }

  /// Initialize per-video banner ad for specific video index
  Future<void> initializeVideoBannerAd(int videoIndex, VideoModel video) async {
    try {
      // Skip if already initialized
      if (_videoBannerAds.containsKey(videoIndex)) {
        return;
      }

      VideoScreenLogger.logVideoAdInit(
        videoIndex: videoIndex,
        videoName: video.videoName,
      );

      // Generate unique ad unit ID for this video (in production, use real ad unit IDs)
      final adUnitId = _generateAdUnitIdForVideo(videoIndex, video);
      _videoAdUnitIds[videoIndex] = adUnitId;

      // Create banner ad for this specific video
      final bannerAd = BannerAd(
        adUnitId: adUnitId,
        size: AdSize.banner,
        request: AdRequest(
          // Add video-specific targeting
          keywords: [
            video.videoName,
            if (video.description != null) video.description!,
            video.uploader.name,
          ].where((keyword) => keyword.isNotEmpty).toList(),
        ),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            VideoScreenLogger.logVideoAdInitSuccess(videoIndex: videoIndex);
            _videoAdLoaded[videoIndex] = true;
          },
          onAdFailedToLoad: (ad, error) {
            VideoScreenLogger.logVideoAdInitError(
              videoIndex: videoIndex,
              error: error.message,
            );
            _videoAdLoaded[videoIndex] = false;
            // Retry after 3 seconds
            Future.delayed(const Duration(seconds: 3), () {
              if (!(_videoAdLoaded[videoIndex] ?? false)) {
                retryVideoBannerAd(videoIndex, video);
              }
            });
          },
          onAdOpened: (ad) {
            VideoScreenLogger.logInfo('Video $videoIndex: Banner ad opened');
          },
          onAdClosed: (ad) {
            VideoScreenLogger.logInfo('Video $videoIndex: Banner ad closed');
          },
          onAdImpression: (ad) {
            VideoScreenLogger.logInfo('Video $videoIndex: Banner ad impression');
          },
        ),
      );

      // Store the banner ad
      _videoBannerAds[videoIndex] = bannerAd;
      _videoAdLoaded[videoIndex] = false;

      // Load the ad
      await bannerAd.load();

      VideoScreenLogger.logInfo('Banner ad initialization started for video $videoIndex');
    } catch (e) {
      VideoScreenLogger.logVideoAdInitError(
        videoIndex: videoIndex,
        error: e.toString(),
      );
      _videoAdLoaded[videoIndex] = false;
    }
  }

  /// Generate unique ad unit ID for video (in production, use real ad unit IDs)
  String _generateAdUnitIdForVideo(int videoIndex, VideoModel video) {
    // For testing, use different test ad unit IDs
    // In production, you would have different real ad unit IDs for different video categories
    final testAdUnitIds = [
      'ca-app-pub-3940256099942544/6300978111', // Test Banner 1
      'ca-app-pub-3940256099942544/6300978112', // Test Banner 2 (if available)
      'ca-app-pub-3940256099942544/6300978113', // Test Banner 3 (if available)
    ];

    // Use video index to cycle through different ad unit IDs
    final adUnitIndex = videoIndex % testAdUnitIds.length;
    return testAdUnitIds[adUnitIndex];
  }

  /// Retry loading banner ad for specific video
  Future<void> retryVideoBannerAd(int videoIndex, VideoModel video) async {
    try {
      VideoScreenLogger.logAdRefresh();

      // Dispose old ad if exists
      _videoBannerAds[videoIndex]?.dispose();

      // Reinitialize
      await initializeVideoBannerAd(videoIndex, video);
    } catch (e) {
      VideoScreenLogger.logError('Error retrying video banner ad for index $videoIndex: $e');
    }
  }

  /// Refresh main banner ad
  Future<void> refreshBannerAd() async {
    if (_bannerAd != null) {
      _bannerAd!.dispose();
      _bannerAd = null;
    }

    _isBannerAdLoaded = false;

    await Future.delayed(const Duration(milliseconds: 500));
    await initializeBannerAd();
  }

  /// Get banner ad for specific video
  BannerAd? getVideoBannerAd(int videoIndex) {
    return _videoBannerAds[videoIndex];
  }

  /// Check if video banner ad is loaded
  bool isVideoBannerAdLoaded(int videoIndex) {
    return _videoAdLoaded[videoIndex] ?? false;
  }

  /// Get ad unit ID for video
  String? getAdUnitId(int videoIndex) {
    return _videoAdUnitIds[videoIndex];
  }

  /// Dispose all ads
  void dispose() {
    _bannerAd?.dispose();
    for (var ad in _videoBannerAds.values) {
      ad.dispose();
    }
    _videoBannerAds.clear();
    _videoAdLoaded.clear();
    _videoAdUnitIds.clear();
    VideoScreenLogger.logInfo('All video banner ads disposed');
  }

  /// Get revenue analytics for a specific video
  Map<String, dynamic> getVideoRevenueAnalytics(int videoIndex, VideoModel video) {
    try {
      final adUnitId = _videoAdUnitIds[videoIndex];
      final isAdLoaded = _videoAdLoaded[videoIndex] ?? false;

      return {
        'video_id': video.id,
        'video_name': video.videoName,
        'video_index': videoIndex,
        'uploader_id': video.uploader.id,
        'uploader_name': video.uploader.name,
        'ad_unit_id': adUnitId,
        'ad_status': isAdLoaded ? 'loaded' : 'not_loaded',
        'ad_loaded_at': isAdLoaded ? DateTime.now().toIso8601String() : null,
        'estimated_revenue': _calculateEstimatedRevenue(videoIndex, video),
        'analytics_timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      VideoScreenLogger.logError('Error getting video revenue analytics: $e');
      return {};
    }
  }

  /// Calculate estimated revenue for a video based on AD IMPRESSIONS
  double _calculateEstimatedRevenue(int videoIndex, VideoModel video) {
    try {
      // Revenue is based on AD IMPRESSIONS, not video views
      // CPM (Cost Per Mille) = Revenue per 1000 ad impressions
      // Using weighted average CPM: 80% carousel/video feed ads (₹30), 20% banner ads (₹10)
      const weightedCpm = 26.0; // ₹26 per 1000 ad impressions (weighted average)

      // Get ad impressions for this video
      final adImpressions = _getAdImpressionsForVideo(videoIndex, video);

      // Calculate revenue: (Ad Impressions / 1000) × CPM
      double revenue = (adImpressions / 1000.0) * weightedCpm;

      // Apply ad performance multipliers
      final adPerformanceMultiplier = _calculateAdPerformanceMultiplier(video);
      revenue *= adPerformanceMultiplier;

      return revenue;
    } catch (e) {
      VideoScreenLogger.logError('Error calculating estimated revenue: $e');
      return 0.0;
    }
  }

  /// Get ad impressions for a specific video
  int _getAdImpressionsForVideo(int videoIndex, VideoModel video) {
    try {
      // This should come from your ad analytics backend
      // For now, we'll simulate based on video engagement

      // Base impressions = video views
      int baseImpressions = video.views ?? 0;

      // Ad impressions are typically higher than video views
      // because ads can be shown multiple times per video view
      const adImpressionsMultiplier = 1.5; // 50% more ad impressions than video views

      // Calculate estimated ad impressions
      final estimatedAdImpressions = (baseImpressions * adImpressionsMultiplier).round();

      VideoScreenLogger.logInfo(
          'Video ${video.videoName}: ${video.views} views → $estimatedAdImpressions estimated ad impressions');

      return estimatedAdImpressions;
    } catch (e) {
      VideoScreenLogger.logError('Error getting ad impressions: $e');
      return 0;
    }
  }

  /// Calculate ad performance multiplier based on engagement
  double _calculateAdPerformanceMultiplier(VideoModel video) {
    try {
      double multiplier = 1.0;

      // Higher engagement = better ad performance = higher revenue

      // Likes factor: +0.1 for every 100 likes
      if (video.likes > 0) {
        multiplier += (video.likes / 100.0) * 0.1;
      }

      // Comments factor: +0.05 for every 10 comments
      if (video.comments.isNotEmpty) {
        multiplier += (video.comments.length / 10.0) * 0.05;
      }

      // Video completion rate factor
      // Higher completion rate = better ad retention
      if (video.views > 0) {
        const estimatedCompletionRate = 0.7;
        if (estimatedCompletionRate > 0.7) {
          multiplier += (estimatedCompletionRate - 0.7) * 0.5;
        }
      }

      // Cap multiplier to reasonable bounds
      return multiplier.clamp(0.5, 2.0);
    } catch (e) {
      VideoScreenLogger.logError('Error calculating ad performance multiplier: $e');
      return 1.0;
    }
  }
}
