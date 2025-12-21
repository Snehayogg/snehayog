import 'package:flutter/material.dart';
import 'package:vayu/services/welcome_onboarding_service.dart';

class WelcomeOnboardingScreen extends StatelessWidget {
  final VoidCallback onGetStarted;

  const WelcomeOnboardingScreen({
    Key? key,
    required this.onGetStarted,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.video_camera_front_rounded,
                  size: 64,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 32),

              // Main heading text
              const Text(
                'Create short videos. Get views. Earn 80% ad revenue',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1A1A1A), // Dark black - primary
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 16),

              // Supporting text
              Text(
                'Start earning from day one',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600], // Grey - secondary
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),

              const Spacer(flex: 3),

              // Get Started Button - always visible at bottom
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    // Mark onboarding as shown
                    await WelcomeOnboardingService.markWelcomeOnboardingShown();
                    // Navigate to main screen
                    onGetStarted();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF1A1A1A), // Dark black button
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
