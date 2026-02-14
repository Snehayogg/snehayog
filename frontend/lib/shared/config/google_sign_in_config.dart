
class GoogleSignInConfig {
  static const String platformClientId = '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com';
  
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
