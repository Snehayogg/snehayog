import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vayug/features/onboarding/data/services/welcome_onboarding_service.dart';
import 'package:vayug/features/onboarding/presentation/screens/welcome_onboarding_screen.dart';

void main() {
  group('Welcome Onboarding Service Tests', () {
    setUp(() async {
      // 1. Always set mock values FIRST before SharedPreferences gets initialized
      SharedPreferences.setMockInitialValues({});
      // 2. Reset session evaluations
      await WelcomeOnboardingService.resetOnboardingState();
    });

    testWidgets('shouldShowWelcomeOnboarding returns true for a first-time user', (WidgetTester tester) async {
      final shouldShow = await WelcomeOnboardingService.shouldShowWelcomeOnboarding();
      expect(shouldShow, isTrue);
    });

    testWidgets('shouldShowWelcomeOnboarding returns false after markWelcomeOnboardingShown is called', (WidgetTester tester) async {
      await WelcomeOnboardingService.markWelcomeOnboardingShown();
      final shouldShow = await WelcomeOnboardingService.shouldShowWelcomeOnboarding();
      expect(shouldShow, isFalse);
    });
  });

  group('Welcome Onboarding Screen Widget Tests', () {
    testWidgets('renders WelcomeOnboardingScreen and handles step navigation', (WidgetTester tester) async {
      // Setup SharedPreferences mock
      SharedPreferences.setMockInitialValues({});
      await WelcomeOnboardingService.resetOnboardingState();

      bool getStartedCalled = false;

      // Pump WelcomeOnboardingScreen inside ScreenUtilInit wrapper to satisfy AppTypography requirements
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (context, child) => MaterialApp(
            home: WelcomeOnboardingScreen(
              onGetStarted: () {
                getStartedCalled = true;
              },
            ),
          ),
        ),
      );

      // Settle the initial ScreenUtil and widget build
      await tester.pumpAndSettle();

      // Verify the first onboarding step is rendered
      expect(find.text('No Interrupted Ads'), findsOneWidget);
      expect(find.text('Experience seamless streaming without any annoying ad interruptions.'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      // Tap Next to go to the second step
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Verify the second onboarding step is rendered
      expect(find.text('Share & Earn'), findsOneWidget);
      expect(find.text('Bas 2 friends ke saath share karein aur full access ke saath earning shuru karein.'), findsOneWidget);

      // Tap Next to go to the third step
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Verify the third onboarding step is rendered
      expect(find.text('UPI ID Setup karein (Setup billing button)'), findsOneWidget);
    });
  });
}
