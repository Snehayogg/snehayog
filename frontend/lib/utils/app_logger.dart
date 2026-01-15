import 'package:flutter/foundation.dart';

/// Centralized logging utility that only logs in debug mode.
/// Use this instead of print() to avoid performance overhead in production.
///
/// **WEB NOTE**: On web, logs appear in the browser's Developer Console (F12),
/// not in the IDE's debug console. Open Chrome DevTools to see logs.
class AppLogger {
  static const bool _debugMode = kDebugMode; // Use kDebugMode from foundation

  /// [isError] can be used by callers to flag important / error logs.
  /// For now we just prefix the message, but this keeps the API flexible.
  static void log(String message, {bool isError = false}) {
    if (!_debugMode) return;

    final formatted = isError ? '❌ [ERROR] $message' : message;

    // Use debugPrint to avoid long line truncation issues in some tools.
    // On web, this outputs to browser console (F12 → Console tab)
    debugPrint(formatted);

    // **WEB FIX: Also use print() for web to ensure logs appear in browser console**
    // debugPrint might not always work on web, so we add print() as fallback
    if (kIsWeb) {
      // ignore: avoid_print
      print(formatted);
    }
  }
}
