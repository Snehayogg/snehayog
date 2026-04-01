import 'package:vayug/shared/utils/app_logger.dart';

class TranslationProcessor {
  final dynamic _translator;
  TranslationProcessor(this._translator);

  String normalizeText(String text) => text;

  Future<Map<String, String>> translateContextBlock(String text, {String? targetLang}) async {
    AppLogger.log('ℹ️ Fast Profile: Translation skipped (Stub active)');
    return {
      'text': text,
      'targetLang': targetLang ?? 'english',
      'sourceLang': 'unknown',
      'isSuitable': 'true'
    };
  }
}
