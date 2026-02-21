import 'package:flutter/material.dart';
import 'package:vayu/main.dart'; // Access to AuthWrapper
import 'package:vayu/features/onboarding/presentation/managers/app_initialization_manager.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/shared/theme/app_theme.dart';
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

    // If logic is 100% complete, finish the bar quickly
    if (realProgress >= 1.0) {
      _finishProgressBar();
    }
  }

  void _finishProgressBar() {
    if (!mounted || _isNavigating) return;
    
    _progressController.animateTo(
      1.0, 
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    ).then((_) => _checkAndNavigate());
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
    
    // **FINAL GATE: Only navigate if logic is ready AND bar is at 100%**
    if (initManager.isStage2Complete && _progressController.value >= 1.0) {
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
      backgroundColor: AppTheme.backgroundPrimary,
      body: Stack(
        children: [
          // Center Content: Vayu Text
          Center(
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: const VayuLogo(
                fontSize: 48,
                textColor: AppTheme.white, // White logo on dark splash
              ),
            ),
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
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary.withOpacity(0.6),
                            letterSpacing: 0.5,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Progress Indicator - THICKER & PROFESSIONAL
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedBuilder(
                        animation: _progressController,
                        builder: (context, _) {
                          return LinearProgressIndicator(
                            value: _progressController.value,
                            backgroundColor: AppTheme.white.withOpacity(0.1),
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                            minHeight: 6, // Increased from 3
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
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textTertiary.withOpacity(0.3),
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
