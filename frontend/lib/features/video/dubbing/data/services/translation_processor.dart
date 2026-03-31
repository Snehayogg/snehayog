import 'dart:convert';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Handles context-based translation and text normalization for on-device dubbing.
class TranslationProcessor {
  final OnDeviceTranslator _translator;

  TranslationProcessor(this._translator);

  /// Cleans the raw transcription text by removing filler words and hallucinations.
  String normalizeText(String text) {
    if (text.isEmpty) return '';

    String cleaned = text;

    // 1. Remove common English filler words
    final englishFillers = [
      RegExp(r'\b(um|uh|ah|oh|hmm|uhh|umm|like)\b', caseSensitive: false),
      RegExp(r'\byou know\b', caseSensitive: false),
      RegExp(r'\bi mean\b', caseSensitive: false),
    ];

    // 2. Remove common Hindi filler words (often transcribed in Roman script)
    final hindiFillers = [
      RegExp(r'\b(matlab|toh|na|ya|ki|hai na)\b', caseSensitive: false),
      RegExp(r'\b(um|uh|hnn)\b', caseSensitive: false),
    ];

    for (var regex in [...englishFillers, ...hindiFillers]) {
      cleaned = cleaned.replaceAll(regex, '');
    }

    // 3. Remove excessive repeated words (e.g., "bhai bhai bhai" -> "bhai")
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\b(\w+)(?:\s+\1\b){2,}', caseSensitive: false),
      (match) => match.group(1)!,
    );

    // 4. Remove duplicate whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned;
  }

  /// Detects if text contains Devanagari characters (Hindi script).
  bool _hasDevanagari(String text) {
    if (text.isEmpty) return false;
    // Unicode range for Devanagari is \u0900-\u097F
    return RegExp(r'[\u0900-\u097F]').hasMatch(text);
  }

  Future<Map<String, String>> translateContextBlock(String text, {String? targetLang}) async {
    if (text.isEmpty) return {'text': '', 'targetLang': targetLang ?? 'english', 'sourceLang': 'unknown'};
    
    // Step 1: Clean filler words
    final normalized = normalizeText(text);
    if (normalized.isEmpty) return {'text': '', 'targetLang': targetLang ?? 'english', 'sourceLang': 'unknown'};
    
    // **NEW: HEURISTIC DETECTION**
    final bool isLikelyHindi = _hasDevanagari(normalized);
    final String heuristicSource = isLikelyHindi ? 'hindi' : 'unknown';

    try {
      // Step 2: Initialize Gemini
      const apiKey = 'AIzaSyCC_NgwBKYXWizHPh0V0H216mdSMm1LcXc'; 
      
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
      );
      
      // Step 3: Create a contextual prompt
      // We explicitly tell Gemini about our heuristic if we found Devanagari
      final detectionHint = isLikelyHindi 
          ? "The input contains Devanagari script (Hindi)." 
          : "The input script is Latin (English or Hinglish-in-Roman).";

      final prompt = '''
You are an expert movie and social media translator.
ACT AS A BI-DIRECTIONAL LANGUAGE SWAPPER.

CONTEXT: $detectionHint
INPUT TEXT: "$normalized"

DUBBING RULES:
1. If the input is English -> Translate to "Smart Hinglish":
   - IMPORTANT: Use DEVANAGARI script for the Hindi base (e.g., "यह", "देखो", "सब्सक्राइब").
   - Use LATIN script ONLY for technical terms, modern slang, and high-impact English words (e.g., "cool", "bro", "link", "video", "amazing", "channel").
   - This prevents bad pronunciation of English words in Hindi TTS while keeping the tone natural.
   
EXAMPLES for English to Smart Hinglish:
- Input: "Hey bro, check out this link." -> Output: "Hey bro, यह link check करो।"
- Input: "Don't forget to subscribe to my channel." -> Output: "मेरे channel को subscribe करना मत भूलना।"
- Input: "This video is really amazing." -> Output: "यह video सच में amazing है।"

2. If the input is Hindi or Hinglish -> Translate to natural, modern English.

OUTPUT FORMAT:
Your response MUST be a JSON object with three keys:
1. "sourceLang": either "hindi" or "english"
2. "translatedText": the result of the translation.
3. "isSuitable": boolean, false if the input is nonsense, pure background noise, or repetitive hallucinations.

Do not add any extra commentary, just return the JSON.
''';
      AppLogger.log('🚀 Sending text to Gemini API. [Heuristic: $heuristicSource]...');
      
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      
      if (response.text != null && response.text!.isNotEmpty) {
        AppLogger.log('✅ Gemini Translation Success!');
        
        try {
          // Clean the response
          String rawJson = response.text!.trim();
          if (rawJson.contains('```')) {
            final start = rawJson.indexOf('{');
            final end = rawJson.lastIndexOf('}');
            if (start != -1 && end != -1) {
              rawJson = rawJson.substring(start, end + 1);
            }
          }
          
          final Map<String, dynamic> data = jsonDecode(rawJson);
          String source = data['sourceLang'] ?? 'unknown';
          
          // **SYNC: If our heuristic detected Hindi but Gemini says English, trust Gemini UNLESS heuristic is high confidence**
          // (Actually, if it has Devanagari, it's definitely NOT pure English)
          if (isLikelyHindi && source == 'english') {
            source = 'hindi'; // Force hindi if Devanagari was found
          }

          final bool isSuitable = data['isSuitable'] ?? true;
          final String translation = data['translatedText'] ?? '';
          final String finalTarget = (source == 'hindi') ? 'english' : 'hindi';
          
          AppLogger.log('🎙️ Result: Source=$source -> Target=$finalTarget (Suitable: $isSuitable)');

          return {
            'text': translation,
            'targetLang': finalTarget,
            'sourceLang': source,
            'isSuitable': isSuitable.toString(),
          };
        } catch (e) {
          AppLogger.log('⚠️ Failed to parse Gemini JSON: $e');
          return {
            'text': response.text!.trim(),
            'targetLang': targetLang ?? 'english',
            'sourceLang': heuristicSource,
          };
        }
      } else {
        throw Exception('Empty response from Gemini');
      }
      
    } catch (e) {
      AppLogger.log('❌ Gemini Translation Failed: $e');
      // Fallback to ML Kit
      AppLogger.log('⚠️ Falling back to local ML Kit...');
      final fallbackTarget = targetLang ?? 'english';
      final translation = await _translator.translateText(normalized);
      return {
        'text': translation,
        'targetLang': fallbackTarget,
        'sourceLang': heuristicSource,
      };
    }
  }
}
