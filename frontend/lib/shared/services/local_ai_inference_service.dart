import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class LocalAiInferenceService {
  static final LocalAiInferenceService _instance = LocalAiInferenceService._internal();
  factory LocalAiInferenceService() => _instance;
  LocalAiInferenceService._internal();

  Whisper? _whisper;
  bool _isWhisperInit = false;
  OnDeviceTranslator? _translatorEnToHi;
  OnDeviceTranslator? _translatorHiToEn;

  Future<void> initializeModels(void Function(String, double)? onProgress) async {
    try {
      if (!_isWhisperInit) {
        onProgress?.call('Initializing AI Engine...', 0.2);
        // The Whisper package handles downloading the model itself via downloadHost and WhisperModel if not found
        _whisper = const Whisper(
          model: WhisperModel.tiny,
          downloadHost: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
        );
        _isWhisperInit = true;
        AppLogger.log('🧠 AI: Whisper engine initialized (model: tiny).');
      }

      onProgress?.call('Initializing AI Translator...', 0.35);
      final modelManager = OnDeviceTranslatorModelManager();
      
      final bool hasHindi = await modelManager.isModelDownloaded(TranslateLanguage.hindi.bcpCode);
      if (!hasHindi) {
         onProgress?.call('Downloading Translation Dictionary (~30MB)...', 0.45);
         await modelManager.downloadModel(TranslateLanguage.hindi.bcpCode);
      }
      
      _translatorEnToHi = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: TranslateLanguage.hindi,
      );
      
      _translatorHiToEn = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.hindi,
        targetLanguage: TranslateLanguage.english,
      );
      
      AppLogger.log('🧠 AI: ML Kit Translation models ready.');

    } catch (e) {
      AppLogger.log('❌ AI Init Error: $e');
      throw Exception('Failed to initialize local AI models: $e');
    }
  }

  Future<String> transcribeAudio(String audioPath) async {
    if (!_isWhisperInit || _whisper == null) {
      throw Exception('Whisper engine not initialized');
    }
    
    AppLogger.log('🧠 AI: Starting transcription for $audioPath');
    try {
      final WhisperTranscribeResponse transcription = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioPath,
          language: "auto",
          isTranslate: false, // We use google ml kit for better translation
          isNoTimestamps: true,
          splitOnWord: false,
        ),
      );
      
      final text = transcription.text;
      AppLogger.log('🧠 AI: Transcription Result: $text');
      return text;
    } catch (e) {
      AppLogger.log('❌ AI Transcription Error: $e');
      throw Exception('Failed to transcribe audio: $e');
    }
  }
  
  Future<String> translateText(String text, String targetLang) async {
    if (text.isEmpty) return text;
    
    AppLogger.log('🧠 AI: Starting translation to $targetLang');
    try {
      // Assuming original video is mostly English
      // If target is Hindi, translate English->Hindi
      // If target is English, we don't necessarily need to translate, but we could pass through if Whisper auto-detected Hindi
      // For now, we translate En -> Hi if target is hindi, and Hi -> En if target is english.
      // But we transcribed with 'auto', so text might be any language.
      // Google ML Kit translates from a known source to target. We'll assume Source is English for now.
      
      if (targetLang == 'hindi') {
         if (_translatorEnToHi == null) throw Exception('Translator not initialized');
         final result = await _translatorEnToHi!.translateText(text);
         AppLogger.log('🧠 AI: Translated to Hindi: $result');
         return result;
      } else {
         // if target is english, maybe it was already english, or it was hindi. 
         // For POC, return original text or attempt Hi->En if text has Hindi characters
         final hasHindiContent = RegExp(r'[\u0900-\u097F]').hasMatch(text);
         if (hasHindiContent) {
           if (_translatorHiToEn == null) throw Exception('Translator not initialized');
           final result = await _translatorHiToEn!.translateText(text);
           AppLogger.log('🧠 AI: Translated to English: $result');
           return result;
         }
         return text; // It's already english
      }
    } catch (e) {
      AppLogger.log('❌ AI Translation Error: $e');
      throw Exception('Failed to translate text: $e');
    }
  }
}
