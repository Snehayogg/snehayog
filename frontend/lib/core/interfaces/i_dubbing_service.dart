import 'package:vayug/features/video/dubbing/data/models/dubbing_models.dart';

/// **Contract Layer — Interface for Video Dubbing Services.**
/// 
/// Decouples video dubbing engines (on-device FFmpeg vs. server-side task polling vs. disabled stubs)
/// from the video feed and player UI widgets.
abstract class IDubbingService {
  /// Cancels an ongoing dubbing job using the video's identifier.
  void cancelDubbing(String videoId, String videoUrl);

  /// Requests a dub/translation for a specific video.
  /// Emits stream progress updates from checking, audio extraction to mux completion.
  Stream<DubbingResult> dubVideo(
    String videoId,
    String videoUrl, {
    String targetLang = 'hindi',
  });
}
