import 'package:shared_preferences/shared_preferences.dart';

class WelcomeOnboardingService {
  static const String _welcomeOnboardingShownKey = 'welcome_onboarding_shown';

  // **SESSION GUARD: Prevents re-evaluating or re-showing within the same app run**
  static bool? _sessionEvaluation;

  /// Check if welcome onboarding should be shown
  static Future<bool> shouldShowWelcomeOnboarding() async {
    // 1. Check session cache first for instant response and better reliability
    if (_sessionEvaluation != null) {
      return _sessionEvaluation!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final hasShownOnboarding =
          prefs.getBool(_welcomeOnboardingShownKey) ?? false;

      // 2. Cache the result for this session
      _sessionEvaluation = !hasShownOnboarding;

      print('🔍 WelcomeOnboarding: shouldShowOnboarding = $_sessionEvaluation');
      return _sessionEvaluation!;
    } catch (e) {
      print('❌ WelcomeOnboarding: Error checking onboarding status: $e');
      return true; // Show onboarding on error
    }
  }

  /// Mark welcome onboarding as shown
  static Future<void> markWelcomeOnboardingShown() async {
    try {
      // 1. Update session cache immediately to prevent re-shows in same run
      _sessionEvaluation = false;

      final prefs = await SharedPreferences.getInstance();
      // 2. Use await to ensure it's written before we continue
      final success = await prefs.setBool(_welcomeOnboardingShownKey, true);

      if (success) {
        print('✅ WelcomeOnboarding: Marked onboarding as shown and persisted');
      } else {
        print('⚠️ WelcomeOnboarding: Failed to persist onboarding status');
      }
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

