import 'dart:async';
import 'package:vayug/core/interfaces/i_dubbing_service.dart';
import 'package:vayug/features/video/dubbing/data/models/dubbing_models.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class DisabledDubbingServiceImpl implements IDubbingService {

  @override
  void cancelDubbing(String videoId, String videoUrl) {}

  @override
  Stream<DubbingResult> dubVideo(
    String videoId,
    String videoUrl, {
    String targetLang = 'hindi',
  }) async* {
    AppLogger.log('⚠️ Fast Profile: Dubbing is disabled in this build mode.');
    yield const DubbingResult(
      status: DubbingStatus.failed,
      error: 'Dubbing is disabled in Fast Profile mode. Use toggle_fast_profile.dart enable to restore.'
    );
  }
}
