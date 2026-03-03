import 'package:flutter/foundation.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Centralized logging utility that only logs in debug mode.
/// Uses Talker for structured, searchable, in-app viewable logs.
///
/// **PRODUCTION SAFE**: TalkerScreen is only accessible in debug mode.
/// In release builds, logging is completely disabled.
class AppLogger {
  static final Talker _talker = Talker(
    settings: TalkerSettings(
      enabled: kDebugMode, // ⚡ Completely disabled in production
      useConsoleLogs: kDebugMode,
    ),
  );

  /// Access the Talker instance (for TalkerScreen in debug mode)
  static Talker get talker => _talker;

  /// Whether we're in debug mode
  static bool get isDebugMode => kDebugMode;

  /// Standard log message
  static void log(String message, {bool isError = false}) {
    if (!kDebugMode) return;

    // Use debugPrint for guaranteed console visibility
    debugPrint(isError ? '❌ ERROR: $message' : 'ℹ️ INFO: $message');

    if (isError) {
      _talker.error('❌ $message');
    } else {
      _talker.info(message);
    }
  }

  /// Debug level log
  static void debug(String message) {
    if (!kDebugMode) return;
    debugPrint('🐛 DEBUG: $message');
    _talker.debug(message);
  }

  /// Warning level log
  static void warning(String message) {
    if (!kDebugMode) return;
    debugPrint('⚠️ WARNING: $message');
    _talker.warning(message);
  }

  /// Error with optional exception and stack trace
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('❌ ERROR: $message ${error ?? ""}');
      _talker.error(message, error, stackTrace);
    } else {
      // In production, send to Crashlytics
      try {
        if (Firebase.apps.isNotEmpty) {
          FirebaseCrashlytics.instance.recordError(
            error ?? message,
            stackTrace,
            reason: message,
            fatal: false, // Non-fatal by default for handled errors
          );
        }
      } catch (e) {
        // Silently fail if Crashlytics isn't ready
      }
    }
  }

  /// Critical/handle exception
  static void handle(Object error, [StackTrace? stackTrace, String? message]) {
    if (kDebugMode) {
      _talker.handle(error, stackTrace, message);
    } else {
      // In production, send to Crashlytics
      try {
        if (Firebase.apps.isNotEmpty) {
          FirebaseCrashlytics.instance.recordError(
            error,
            stackTrace,
            reason: message,
            fatal: true, // Mark as fatal for critical exceptions
          );
        }
      } catch (e) {
        // Silently fail
      }
    }
  }
}
