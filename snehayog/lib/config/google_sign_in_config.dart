class GoogleSignInConfig {
  // Replace with your actual client ID from Google Cloud Console
  // To get this:
  // 1. Go to https://console.cloud.google.com/
  // 2. Create a new project or select existing one
  // 3. Enable Google Sign-In API
  // 4. Go to Credentials
  // 5. Create OAuth 2.0 Client ID
  // 6. Choose Android application
  // 7. Enter your package name (com.example.snehayog)
  // 8. Get SHA-1 fingerprint from your debug keystore
  // 9. Copy the client ID from the created credential
  static const String clientId =
      '406195883653-1j2f5ilp46376ndqs8gd0trkto8n727d.apps.googleusercontent.com';

  // Web client ID (if you're also supporting web platform)
  // To get this:
  // 1. In the same Google Cloud Console project
  // 2. Create another OAuth 2.0 Client ID
  // 3. Choose Web application
  // 4. Add authorized JavaScript origins (http://localhost:3000 for development)
  // 5. Add authorized redirect URIs (http://localhost:3000/auth/google/callback)
  // 6. Copy the client ID from the created credential
  // static const String webClientId =
  //     '406195883653-1j2f5ilp46376ndqs8gd0trkto8n727d.apps.googleusercontent.com';

  // Scopes required for the application
  static const List<String> scopes = ['email', 'profile'];
}
