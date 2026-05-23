import 'package:vayug/features/video/core/data/models/video_model.dart';

/// **IAdProvider**
/// Abstract contract defining the plug-and-play interface for Vayu's frontend ad formats.
abstract class IAdProvider {
  /// The unique type identifier of this ad format (e.g. 'banner', 'carousel')
  String get adType;

  /// Loads/fetches targeted ads of this format from the network or local caches.
  /// Optionally passes contextual signals from a target [VideoModel].
  Future<List<Map<String, dynamic>>> loadAds({VideoModel? video});

  /// Tracks a viewing impression for this ad format.
  Future<bool> trackImpression(String adId);

  /// Tracks a click engagement for this ad format.
  Future<bool> trackClick(String adId, {String? userId});
}
