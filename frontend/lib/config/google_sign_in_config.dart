import 'dart:io';
import 'package:flutter/foundation.dart';

class GoogleSignInConfig {
  // ✅ ANDROID OAuth 2.0 Client ID (from google-services.json)
  static const String clientId =
      '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com';

  // ✅ iOS Client ID (from GoogleService-Info.plist)
  static const String iosClientId =
      '406195883653-f4ejmoq2e0v9tnquvout06uu305bb4eh.apps.googleusercontent.com';

  static const String webClientId =
      '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com';

  // ✅ Platform-specific client ID getter (Android, iOS & Web)
  static String get platformClientId {
    // Check for web platform first (kIsWeb works on all platforms)
    if (kIsWeb) {

      return webClientId;
    }

    // For native platforms, use Platform checks
    try {
      if (Platform.isAndroid) return clientId;
      if (Platform.isIOS) return iosClientId;
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {

        return webClientId;
      }
    } catch (e) {
      // Fallback for web if Platform check fails

      return webClientId;
    }
    return webClientId;
  }

  static const List<String> scopes = ['email', 'profile'];

  // ✅ Check if configuration is valid
  static bool get isConfigured =>
      clientId.isNotEmpty && iosClientId.isNotEmpty && webClientId.isNotEmpty;

  // ✅ Validate OAuth 2.0 Client ID format
  static bool get isValidClientId {
    final androidValid = clientId.contains('apps.googleusercontent.com') &&
        clientId.contains('406195883653');
    final iosValid = iosClientId.contains('apps.googleusercontent.com') &&
        iosClientId.contains('406195883653');
    final webValid = webClientId.contains('apps.googleusercontent.com') &&
        webClientId.contains('406195883653');
    return androidValid && iosValid && webValid;
  }

  static void printConfig() {

  }

  // ✅ Get detailed error information
  static String? getConfigurationError() {
    if (!isConfigured) {
      return 'OAuth 2.0 Client IDs are missing in configuration';
    }
    if (!isValidClientId) {
      return 'OAuth 2.0 Client ID format is invalid. Please check Firebase Console.';
    }
    return null;
  }
}
