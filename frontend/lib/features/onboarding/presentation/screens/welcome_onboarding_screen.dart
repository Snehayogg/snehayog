import 'package:flutter/material.dart';
import 'package:vayu/features/onboarding/data/services/welcome_onboarding_service.dart';
import 'package:vayu/shared/services/app_remote_config_service.dart';

class WelcomeOnboardingScreen extends StatefulWidget {
  final VoidCallback onGetStarted;

  const WelcomeOnboardingScreen({
    Key? key,
    required this.onGetStarted,
  }) : super(key: key);

  @override
  State<WelcomeOnboardingScreen> createState() =>
      _WelcomeOnboardingScreenState();
}

class _WelcomeOnboardingScreenState extends State<WelcomeOnboardingScreen> {
  bool _isLoading = true;
  String _heading = '';
  final String _subheading = '';
  String _buttonText = '';

  @override
  void initState() {
    super.initState();
    _loadOnboardingContent();
  }

  /// Load onboarding content from backend (AppRemoteConfigService)
  /// Falls back to hardcoded values if backend fails
  Future<void> _loadOnboardingContent() async {
    try {
      // Ensure AppRemoteConfigService is initialized
      if (!AppRemoteConfigService.instance.isConfigAvailable) {
        await AppRemoteConfigService.instance.initialize();
      }

      final config = AppRemoteConfigService.instance.config;

      if (config != null) {
        // Fetch content from backend uiTexts
        setState(() {
          _heading = config.getText(
            'welcome_onboarding_heading',
            fallback:
                'Monetize Your Gaming Content',
          );
          _buttonText = config.getText(
            'welcome_onboarding_button',
            fallback: 'Get Started',
          );
          _isLoading = false;
        });
      } else {
        // Fallback to hardcoded values if config not available
        setState(() {
          _heading = 'Monetize Your Gaming Content';
          _buttonText = 'Get Started';
          _isLoading = false;
        });
      }
    } catch (e) {
      // Fallback to hardcoded values on error
      setState(() {
        _heading = 'Monetize Your Gaming Content';
        _buttonText = 'Get Started';
        _isLoading = false;
      });
    }
  }

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

              // Main heading text - Backend-driven
              if (_isLoading)
                const SizedBox(
                  height: 60,
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Text(
                  _heading,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A), // Dark black - primary
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                    letterSpacing: -0.3,
                  ),
                ),
              const SizedBox(height: 16),

              // Supporting text - Backend-driven
              if (!_isLoading)
                Text(
                  _subheading,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600], // Grey - secondary
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                  ),
                ),

              const Spacer(flex: 3),

              // Get Started Button - Backend-driven text
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          // Mark onboarding as shown
                          await WelcomeOnboardingService
                              .markWelcomeOnboardingShown();
                          // Navigate to main screen
                          widget.onGetStarted();
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
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          _buttonText,
                          style: const TextStyle(
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
