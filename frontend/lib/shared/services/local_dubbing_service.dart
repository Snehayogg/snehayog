import 'package:vayu/shared/utils/app_logger.dart';

class LocalDubbingService {
  static final LocalDubbingService instance = LocalDubbingService._internal();
  LocalDubbingService._internal();

  bool isDeviceCapable() {
    AppLogger.log('Dubbing is disabled in Fast Profile');
    return false;
  }

  Future<String?> processDubbing({
    required String videoPath,
    required String videoId,
    required String targetLang,
    Function(String, double)? onProgress,
  }) async {
    throw Exception('Dubbing is disabled in fast profile mode');
  }
}

final localDubbingService = LocalDubbingService.instance;
