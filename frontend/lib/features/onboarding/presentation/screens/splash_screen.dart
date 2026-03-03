import 'package:flutter/material.dart';
import 'package:vayu/main.dart'; // Access to AuthWrapper
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/features/onboarding/presentation/managers/app_initialization_manager.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/core/design/radius.dart';
import 'package:vayu/core/design/spacing.dart';
import 'package:vayu/shared/widgets/vayu_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _opacityAnimation;
  
  // **SMART PROGRESS: Dedicated controller for the progress bar**
  late AnimationController _progressController;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    
    // Fade controller for the Vayu text
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    // **SMART PROGRESS: Adaptive Controller**
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // Fast crawl to match quick auth
    );

    // 1. Start Fade
    _fadeController.forward();

    // 2. Start slow "Predictive Crawl" (Bar moves to 70% even if network is slow)
    // This gives a "Professional" active feel immediately.
    _progressController.animateTo(0.7, curve: Curves.easeOutCubic);

    // 3. Listen to real logic progress
    AppInitializationManager.instance.initializationProgress.addListener(_syncProgress);
    
    // 4. Fire initialization
    _startBackgroundInitialization();
  }

  /// **SMART SYNC: Bridge Logic Progress to UI Animation**
  void _syncProgress() {
    if (!mounted) return;
    
    final realProgress = AppInitializationManager.instance.initializationProgress.value;
    
    // If logic is ahead of our crawl, surge forward to catch up
    if (realProgress > _progressController.value) {
      // Use faster surge animation
      _progressController.animateTo(
        realProgress, 
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutQuad,
      );
    }

    // If logic is 100% complete, finish the bar quickly and navigate
    if (realProgress >= 1.0) {
      _isNavigating = true; 
      _navigateToHome(); // Direct navigation for maximum speed
    }
  }



  Future<void> _startBackgroundInitialization() async {
    if (mounted) {
      await AppInitializationManager.instance.initializeStage2(context);
      _checkAndNavigate();
    }
  }

  void _checkAndNavigate() {
    if (!mounted || _isNavigating) return;

    final initManager = AppInitializationManager.instance;
    
    // **FINAL GATE: Only navigate if logic stage 2 is complete**
    // Decoupled from progress bar animation for maximum speed
    if (initManager.isStage2Complete) {
      _isNavigating = true;
      _navigateToHome();
    }
  }

  void _navigateToHome() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AuthWrapper(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  void dispose() {
    AppInitializationManager.instance.initializationProgress.removeListener(_syncProgress);
    _fadeController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initManager = AppInitializationManager.instance;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Stack(
        children: [
          // Center Content: Vayu Text
          Center(
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: const VayuLogo(
                fontSize: 48,
                textColor: AppColors.white, // White logo on dark splash
              ),
            ),
          ),
          
          // **NEW: Force Update Dialog Overlay**
          ValueListenableBuilder<bool>(
            valueListenable: initManager.isUpdateRequired,
            builder: (context, isUpdateRequired, child) {
              if (!isUpdateRequired) return const SizedBox.shrink();

              // Stop the progress animation
              _progressController.stop();

              return Container(
                color: AppColors.backgroundPrimary.withValues(alpha: 0.8),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSecondary,
                      borderRadius: AppRadius.borderRadiusLG,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.system_update,
                          color: AppColors.primary,
                          size: 48,
                        ),
                        AppSpacing.vSpace16,
                        Text(
                          'Update Required',
                          style: AppTypography.headlineMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: AppTypography.weightBold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        AppSpacing.vSpace12,
                        Text(
                          'A new version of Vayu is required to continue. Please update the app to access the latest features and improvements.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        AppSpacing.vSpace24,
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () async {
                              // Replace with your actual Play Store URL or App ID
                              final url = Uri.parse('market://details?id=com.vayu.app');
                              final fallbackUrl = Uri.parse('https://play.google.com/store/apps/details?id=com.vayu.app');
                              
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url);
                              } else {
                                await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.borderRadiusMD,
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'UPDATE NOW',
                              style: AppTypography.labelLarge.copyWith(
                                color: Colors.white,
                                fontWeight: AppTypography.weightBold,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          
          // Bottom Content: Progress Bar and Status
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status Text - FILTERED: Only show if contains "Ready"
                    ValueListenableBuilder<String>(
                      valueListenable: initManager.initializationStatus,
                      builder: (context, status, _) {
                        final displayStatus = status.toLowerCase().contains('ready') ? status : '';
                        return Text(
                          displayStatus,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textSecondary.withValues(alpha: 0.6),
                            letterSpacing: 0.5,
                          ),
                        );
                      },
                    ),
                    SizedBox(height: 16),
                    
                    // Progress Indicator - THICKER & PROFESSIONAL
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedBuilder(
                        animation: _progressController,
                        builder: (context, _) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: initManager.isUpdateRequired,
                            builder: (context, isUpdateRequired, _) {
                              // Hide progress bar if update is required
                              if (isUpdateRequired) return const SizedBox.shrink();
                              return LinearProgressIndicator(
                                value: _progressController.value,
                                backgroundColor: AppColors.white.withValues(alpha: 0.1),
                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                minHeight: 6, // Increased from 3
                              );
                            }
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Version info at bottom
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'v${AppConfig.kApiVersion}',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textTertiary.withValues(alpha: 0.3),
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
