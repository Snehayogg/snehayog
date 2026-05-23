
class GoogleSignInConfig {
  // Use official Flutter environment variables via String.fromEnvironment to avoid hardcoding credentials
  static const String platformClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com',
  );
  
  // **Tier 4: Google Web Client ID used as serverClientId to obtain serverAuthCode**
  static const String serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com',
  );
  
  static bool get isConfigured => platformClientId.isNotEmpty;
  static bool get isValidClientId => platformClientId.contains('.apps.googleusercontent.com');
  
  static String getConfigurationError() {
    if (platformClientId.isEmpty) return "Client ID is empty";
    if (!isValidClientId) return "Invalid Client ID format";
    return "";
  }

  static void printConfig() {
    print('🔑 GoogleSignInConfig: Client ID is ${isValidClientId ? 'VALID' : 'INVALID'}');
  }
}
