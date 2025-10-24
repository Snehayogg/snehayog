import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
import 'package:vayu/controller/main_controller.dart';
import 'package:vayu/core/providers/user_provider.dart';
import 'package:vayu/core/providers/video_provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/services/authservices.dart';

/// **FIXED: Centralized logout service to coordinate all state managers**
class LogoutService {
  static final LogoutService _instance = LogoutService._internal();
  factory LogoutService() => _instance;
  LogoutService._internal();

  /// **FIXED: Perform complete logout across all state managers**
  static Future<void> performCompleteLogout(BuildContext context) async {
    try {
      print('🚪 LogoutService: Starting complete logout process...');

      // **FIXED: Get all providers from context**
      final authController =
          Provider.of<GoogleSignInController>(context, listen: false);
      final mainController =
          Provider.of<MainController>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final videoProvider = Provider.of<VideoProvider>(context, listen: false);

      // **FIXED: Step 1: Sign out from AuthService (clears SharedPreferences)**
      print('🚪 LogoutService: Step 1 - Signing out from AuthService...');
      final authService = AuthService();
      await authService.signOut();

      // **FIXED: Step 2: Clear GoogleSignInController state**
      print('🚪 LogoutService: Step 2 - Clearing GoogleSignInController...');
      await authController.signOut();

      // **FIXED: Step 3: Clear MainController state**
      print('🚪 LogoutService: Step 3 - Clearing MainController...');
      await mainController.performLogout();

      // **FIXED: Step 4: Clear UserProvider caches**
      print('🚪 LogoutService: Step 4 - Clearing UserProvider...');
      userProvider.clearAllCaches();

      // **FIXED: Step 5: Clear VideoProvider state**
      print('🚪 LogoutService: Step 5 - Clearing VideoProvider...');
      videoProvider.clearAllVideos();

      // **FIXED: Step 6: Clear ProfileStateManager (if accessible)**
      print('🚪 LogoutService: Step 6 - Clearing ProfileStateManager...');
      try {
        final profileStateManager = ProfileStateManager();
        await profileStateManager.handleLogout();
      } catch (e) {
        print('⚠️ LogoutService: ProfileStateManager not accessible: $e');
      }

      print('✅ LogoutService: Complete logout successful - All state cleared');
    } catch (e) {
      print('❌ LogoutService: Error during complete logout: $e');
      rethrow;
    }
  }

  /// **FIXED: Force refresh all state after account switch**
  static Future<void> refreshAllState(BuildContext context) async {
    try {
      print('🔄 LogoutService: Refreshing all state after account switch...');

      // **FIXED: Get all providers from context**
      final authController =
          Provider.of<GoogleSignInController>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final videoProvider = Provider.of<VideoProvider>(context, listen: false);

      // **FIXED: Step 1: Refresh authentication state**
      print('🔄 LogoutService: Refreshing authentication state...');
      await authController.refreshAuthState();

      // **FIXED: Step 2: Clear and refresh user caches**
      print('🔄 LogoutService: Refreshing user caches...');
      userProvider.clearAllCaches();

      // **FIXED: Step 3: Clear and refresh video state**
      print('🔄 LogoutService: Refreshing video state...');
      videoProvider.clearAllVideos();

      print('✅ LogoutService: All state refreshed successfully');
    } catch (e) {
      print('❌ LogoutService: Error refreshing state: $e');
      rethrow;
    }
  }
}
