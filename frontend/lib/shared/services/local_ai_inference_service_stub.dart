import 'package:vayu/shared/utils/app_logger.dart';

class LocalAiInferenceService {
  static final LocalAiInferenceService _instance = LocalAiInferenceService._internal();
  factory LocalAiInferenceService() => _instance;
  LocalAiInferenceService._internal();

  Future<void> initializeModels(void Function(String, double)? onProgress) async {
    AppLogger.log('AI Inference is disabled in Fast Profile');
  }

  Future<String> transcribeAudio(String audioPath) async {
    throw Exception('AI Inference Engine not available in fast profile mode');
  }
  
  Future<String> translateText(String text, String targetLang) async {
    return text;
  }
}
