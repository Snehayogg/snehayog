import 'package:flutter/foundation.dart';

/// Centralized logging utility that only logs in debug mode.
/// Use this instead of print() to avoid performance overhead in production.
class AppLogger {
  static const bool _debugMode = kDebugMode; // Use kDebugMode from foundation

  static void log(String message) {
    if (_debugMode) print(message);
  }
}
