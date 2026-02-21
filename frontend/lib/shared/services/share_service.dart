import 'package:share_plus/share_plus.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/ads/data/carousel_ad_model.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class ShareService {
  final VideoService _videoService = VideoService();

  Future<void> shareVideo(VideoModel video) async {
    try {
      final shareText = _generateVideoShareText(video);
      await Share.share(shareText);
      await _incrementVideoShareCount(video.id);
    } catch (e) {
      AppLogger.log('❌ ShareService: Error sharing video: $e');
    }
  }

  Future<void> shareAd(CarouselAdModel ad) async {
    try {
      final shareText = _generateAdShareText(ad);
      await Share.share(shareText);
      // Ads might track shares differently or not at all in the same way as videos
      // For now, we'll assume ad share tracking is handled by the caller or not needed here
      // If needed, we can inject a service to track ad shares.
    } catch (e) {
      AppLogger.log('❌ ShareService: Error sharing ad: $e');
    }
  }

  String _generateVideoShareText(VideoModel video) {
    final appDeepLink = 'snehayog://video/${video.id}';
    final webLink = 'https://snehayog.site/video/${video.id}';
        return 'This isn’t just another video app.\n'
    'Vayug lets creators earn rewards from day one 💰\n'
    'And viewers enjoy smooth, ad-free watching.\n\n'
    'Discover it here: $webLink\n'
    'Open instantly: $appDeepLink\n\n'
    'Early creators build the biggest empires.';
  }

  String _generateAdShareText(CarouselAdModel ad) {
    // Basic share text for ads if needed, though typically users share content not ads
    // But since the current implementation allows sharing ads, we preserve it.
    // The previous implementation used a mock video model for sharing ads.
    // We will extract the link if available.
    final link = ad.callToActionUrl;
    return 'Check out this ad on Vayu: ${ad.slides.firstOrNull?.title ?? "Great content"} \n$link';
  }

  Future<void> _incrementVideoShareCount(String videoId) async {
    try {
      await _videoService.incrementShares(videoId);
      AppLogger.log('✅ Share count updated for video: $videoId');
    } catch (e) {
      AppLogger.log('❌ ShareService: Failed to update share count: $e');
    }
  }
}
