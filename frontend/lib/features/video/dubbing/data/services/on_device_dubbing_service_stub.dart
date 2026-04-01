import 'dart:async';
import 'package:vayug/features/video/dubbing/data/models/dubbing_models.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class OnDeviceDubbingService {
  final dynamic _tts = null;
  dynamic _translator = null;
  dynamic _processor = null;

  void cancelDubbing(String videoUrl) {}

  Stream<DubbingResult> dubLocalVideo(String videoPath, {String targetLang = 'english'}) async* {
    AppLogger.log('⚠️ Fast Profile: Dubbing is disabled in this build mode.');
    yield const DubbingResult(
      status: DubbingStatus.failed,
      error: 'Dubbing is disabled in Fast Profile mode. Use toggle_fast_profile.dart enable to restore.'
    );
  }
}
