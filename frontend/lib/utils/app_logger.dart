import 'package:flutter/foundation.dart';

/// Centralized logging utility that only logs in debug mode.
/// Use this instead of print() to avoid performance overhead in production.
class AppLogger {
  static const bool _debugMode = kDebugMode; // Use kDebugMode from foundation

  /// [isError] can be used by callers to flag important / error logs.
  /// For now we just prefix the message, but this keeps the API flexible.
  static void log(String message, {bool isError = false}) {
    if (!_debugMode) return;

    final formatted = isError ? '❌ [ERROR] $message' : message;

    // Use debugPrint to avoid long line truncation issues in some tools.
    debugPrint(formatted);
  }
}
