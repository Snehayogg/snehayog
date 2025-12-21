import 'package:shared_preferences/shared_preferences.dart';

class WelcomeOnboardingService {
  static const String _welcomeOnboardingShownKey = 'welcome_onboarding_shown';

  /// Check if welcome onboarding should be shown
  static Future<bool> shouldShowWelcomeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasShownOnboarding =
          prefs.getBool(_welcomeOnboardingShownKey) ?? false;

      print('🔍 WelcomeOnboarding: shouldShowOnboarding = ${!hasShownOnboarding}');
      print('   - Has shown onboarding: $hasShownOnboarding');

      // Show onboarding if user hasn't seen it yet
      return !hasShownOnboarding;
    } catch (e) {
      print('❌ WelcomeOnboarding: Error checking onboarding status: $e');
      return true; // Show onboarding on error
    }
  }

  /// Mark welcome onboarding as shown
  static Future<void> markWelcomeOnboardingShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_welcomeOnboardingShownKey, true);
      print('✅ WelcomeOnboarding: Marked onboarding as shown');
    } catch (e) {
      print('❌ WelcomeOnboarding: Error marking onboarding shown: $e');
    }
  }

  /// Reset onboarding state (for testing)
  static Future<void> resetOnboardingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_welcomeOnboardingShownKey);
      print('🔄 WelcomeOnboarding: Reset onboarding state');
    } catch (e) {
      print('❌ WelcomeOnboarding: Error resetting state: $e');
    }
  }
}

