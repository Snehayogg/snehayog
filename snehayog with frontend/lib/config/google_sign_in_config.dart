import 'dart:io';

class GoogleSignInConfig {
  // ✅ ANDROID OAuth 2.0 Client ID (from google-services.json)
  static const String clientId =
      '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com';

  // ✅ iOS Client ID (from GoogleService-Info.plist)
  static const String iosClientId =
      '406195883653-f4ejmoq2e0v9tnquvout06uu305bb4eh.apps.googleusercontent.com';

  // ✅ Platform-specific client ID getter (Android & iOS only)
  static String get platformClientId {
    try {
      if (Platform.isAndroid) return clientId;
      if (Platform.isIOS) return iosClientId;
    } catch (e) {
      // Web platform - use Android client ID as default
      print('🌐 Web platform detected, using Android client ID');
    }
    return clientId;
  }

  static const List<String> scopes = ['email', 'profile'];

  // ✅ Check if configuration is valid
  static bool get isConfigured => clientId.isNotEmpty && iosClientId.isNotEmpty;

  // ✅ Validate OAuth 2.0 Client ID format
  static bool get isValidClientId {
    final androidValid = clientId.contains('apps.googleusercontent.com') &&
        clientId.contains('406195883653');
    final iosValid = iosClientId.contains('apps.googleusercontent.com') &&
        iosClientId.contains('406195883653');
    return androidValid && iosValid;
  }

  // ✅ Debug information with OAuth 2.0 validation (Web-safe)
  static void printConfig() {
    print('🔧 Google Sign-In Configuration:');
    print('   📱 Android Client ID: $clientId');
    print('   🍎 iOS Client ID: $iosClientId');
    print('   📦 Package Name: com.example.snehayog');
    print('   🎯 Scopes: ${scopes.join(', ')}');

    // Safe platform detection
    String platformInfo = 'Unknown';
    try {
      platformInfo = Platform.operatingSystem;
    } catch (e) {
      platformInfo = 'Web Browser';
    }
    print('   🌐 Platform: $platformInfo');

    print('   🌐 Using Client ID: $platformClientId');

    if (isConfigured) {
      print('   ✅ Configuration is present');
    } else {
      print('   ❌ Configuration is missing');
    }

    if (isValidClientId) {
      print('   ✅ OAuth 2.0 Client ID format is valid');
    } else {
      print('   ❌ OAuth 2.0 Client ID format is invalid');
      print('   🔧 Please check your Firebase Console configuration');
    }

    // Additional OAuth 2.0 validation
    print('   🔐 OAuth 2.0 Validation:');
    print(
        '      - Android: ${clientId.contains('apps.googleusercontent.com') ? '✅' : '❌'}');
    print(
        '      - iOS: ${iosClientId.contains('apps.googleusercontent.com') ? '✅' : '❌'}');
    print(
        '      - Project ID Match: ${clientId.contains('406195883653') ? '✅' : '❌'}');
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
