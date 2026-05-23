abstract class IAuthService {
  String? get currentUserId;
  Future<Map<String, dynamic>?> getUserData({bool skipTokenRefresh = false, bool forceRefresh = false});
  Future<void> signOut();
  Future<bool> isSignedIn();
  Future<Map<String, dynamic>?> signInWithGoogle({bool forceAccountPicker = true});
  void clearMemoryCache();
  Future<bool> isLoggedIn();
  Future<String?> refreshAccessToken();
}
