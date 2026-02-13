import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class GalleryPermissionService {
  static const String _galleryOnboardingShownKey = 'gallery_onboarding_shown';

  /// Check if gallery permission should be requested
  static Future<bool> shouldShowGalleryOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasShownOnboarding = prefs.getBool(_galleryOnboardingShownKey) ?? false;
      
      // Check current permission status
      final PermissionState ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(),
      );
      final hasPermission = ps.isAuth || ps == PermissionState.limited;

      AppLogger.log('🔍 GalleryPermission: shouldShowOnboarding = ${!hasShownOnboarding && !hasPermission}');
      AppLogger.log('   - Has shown onboarding: $hasShownOnboarding');
      AppLogger.log('   - Has permission: $hasPermission');

      // Only show if we haven't asked yet and don't have permission
      return !hasShownOnboarding && !hasPermission;
    } catch (e) {
      AppLogger.log('❌ GalleryPermission: Error checking onboarding status: $e');
      return true; // Err on the side of caution
    }
  }

  /// Request gallery permission using native system dialog
  static Future<bool> requestGalleryPermission() async {
    try {
      AppLogger.log('🚀 GalleryPermission: Requesting native gallery permission');
      
      // photo_manager handles the underlying complex permission logic for different OS versions
      final PermissionState ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(),
      );
      
      AppLogger.log('🎞️ GalleryPermission: Permission state result: $ps');
      
      // Mark onboarding as shown regardless of result
      await _markOnboardingShown();
      
      return ps.isAuth || ps == PermissionState.limited;
    } catch (e) {
      AppLogger.log('❌ GalleryPermission: Error requesting permission: $e');
      await _markOnboardingShown();
      return false;
    }
  }

  /// Check if gallery permission is currently granted
  static Future<bool> isGalleryPermissionGranted() async {
    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(),
      );
      return ps.isAuth || ps == PermissionState.limited;
    } catch (e) {
      AppLogger.log('❌ GalleryPermission: Error checking permission: $e');
      return false;
    }
  }

  static Future<void> _markOnboardingShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_galleryOnboardingShownKey, true);
      AppLogger.log('✅ GalleryPermission: Marked onboarding as shown');
    } catch (e) {
      AppLogger.log('❌ GalleryPermission: Error marking onboarding shown: $e');
    }
  }
}
