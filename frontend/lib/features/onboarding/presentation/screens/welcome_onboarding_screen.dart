import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/features/onboarding/data/services/welcome_onboarding_service.dart';
import 'package:vayu/shared/services/app_remote_config_service.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/shared/widgets/app_button.dart';

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
                'World First Ad-free Video Streaming app',
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
          _heading = 'World First Ad-free Video Streaming app';
          _buttonText = 'Get Started';
          _isLoading = false;
        });
      }
    } catch (e) {
      // Fallback to hardcoded values on error
      setState(() {
        _heading = 'World First Ad-free Video Streaming app';
        _buttonText = 'Get Started';
        _isLoading = false;
      });
    }
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Icon
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.video_camera_front_rounded,
                  size: 64,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 32),

              // Main heading text - Backend-driven
              if (_isLoading)
                SizedBox(
                  height: 60,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else
                Text(
                  _heading,
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              SizedBox(height: 16),

              // Supporting text - Backend-driven
              if (!_isLoading && _subheading.isNotEmpty)
                Text(
                  _subheading,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),

              const Spacer(flex: 3),

              // Get Started Button - Backend-driven text
              AppButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        // Mark onboarding as shown
                        await WelcomeOnboardingService
                            .markWelcomeOnboardingShown();
                        // Navigate to main screen
                        widget.onGetStarted();
                      },
                label: _buttonText,
                variant: AppButtonVariant.primary,
                isLoading: _isLoading,
                isFullWidth: true,
                size: AppButtonSize.large,
              ),
              SizedBox(height: 24),
              // Legal Disclosure
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'By continuing, you agree to our '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: TextStyle(
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _launchURL('https://snehayog.site/terms.html'),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _launchURL('https://snehayog.site/privacy.html'),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
