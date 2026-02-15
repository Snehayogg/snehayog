import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/features/video/presentation/managers/main_controller.dart';
import 'package:vayu/shared/providers/user_provider.dart';
import 'package:vayu/features/video/presentation/managers/video_provider.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';

/// **FIXED: Centralized logout service to coordinate all state managers**
class LogoutService {
  static final LogoutService _instance = LogoutService._internal();
  factory LogoutService() => _instance;
  LogoutService._internal();

  static T? _readProvider<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  /// **FIXED: Perform complete logout across all state managers**
  static Future<void> performCompleteLogout(BuildContext context) async {
    try {
      print('🚪 LogoutService: Starting complete logout process...');

      final authController = _readProvider<GoogleSignInController>(context);
      final mainController = _readProvider<MainController>(context);
      final userProvider = _readProvider<UserProvider>(context);
      final videoProvider = _readProvider<VideoProvider>(context);
      final profileStateManager = _readProvider<ProfileStateManager>(context);

      // **OPTIMIZED: parallelized logout for speed**
      await Future.wait([
        // Step 1: Sign out via controller (falls back to direct service if unavailable)
        (() async {
          print('🚪 LogoutService: Signing out via GoogleSignInController...');
          if (authController != null) {
            await authController.signOut();
          } else {
            print('⚠️ LogoutService: Falling back to AuthService directly');
            await AuthService().signOut();
          }
        })(),

        // Step 2: Reset MainController navigation state
        (() async {
          if (mainController != null) {
            print('🚪 LogoutService: Clearing MainController...');
            await mainController.performLogout(resetIndex: false);
          }
        })(),

        // Providers are synchronous but we wrap them for consistency in parallel flow
        Future.microtask(() {
          if (userProvider != null) {
            print('🚪 LogoutService: Clearing UserProvider...');
            userProvider.clearAllCaches();
          }
        }),

        Future.microtask(() {
          if (videoProvider != null) {
            print('🚪 LogoutService: Clearing VideoProvider...');
            videoProvider.clearAllVideos();
          }
        }),

        Future.microtask(() {
          if (profileStateManager != null) {
            print('🚪 LogoutService: Clearing ProfileStateManager...');
            profileStateManager.clearData();
          }
        }),
      ]);

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

      final authController = _readProvider<GoogleSignInController>(context);
      final userProvider = _readProvider<UserProvider>(context);
      final videoProvider = _readProvider<VideoProvider>(context);
      final profileStateManager = _readProvider<ProfileStateManager>(context);

      // **OPTIMIZED: parallelized refresh for speed**
      await Future.wait([
        (() async {
          if (authController != null) {
            print('🔄 LogoutService: Refreshing authentication state...');
            await authController.refreshAuthState();
          }
        })(),

        Future.microtask(() {
          if (userProvider != null) {
            print('🔄 LogoutService: Refreshing user caches...');
            userProvider.clearAllCaches();
          }
        }),

        Future.microtask(() {
          if (videoProvider != null) {
            print('🔄 LogoutService: Refreshing video state...');
            videoProvider.clearAllVideos();
          }
        }),

        Future.microtask(() {
          if (profileStateManager != null) {
            print('🔄 LogoutService: Resetting ProfileStateManager cached data...');
            profileStateManager.clearData();
          }
        }),
      ]);

      print('✅ LogoutService: All state refreshed successfully');
    } catch (e) {
      print('❌ LogoutService: Error refreshing state: $e');
      rethrow;
    }
  }
}
