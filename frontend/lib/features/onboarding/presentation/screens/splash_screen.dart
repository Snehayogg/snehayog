import 'package:flutter/material.dart';
import 'package:vayu/main.dart'; // Access to AuthWrapper
import 'package:vayu/features/onboarding/presentation/managers/app_initialization_manager.dart';
import 'package:vayu/shared/config/app_config.dart';

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
      duration: const Duration(milliseconds: 3000), // Default slow crawl
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
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Center Content: Vayu Text
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _opacityAnimation,
                  child: const Text(
                    'Vayu',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1.5,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Progress Bar and Status
                SizedBox(
                  width: 200,
                  child: Column(
                    children: [
                      // Status Text
                      ValueListenableBuilder<String>(
                        valueListenable: initManager.initializationStatus,
                        builder: (context, status, _) {
                          return Text(
                            status,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      
                      // Progress Indicator
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, _) {
                            return LinearProgressIndicator(
                              value: _progressController.value,
                              backgroundColor: Colors.white.withAlpha(30),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 3,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Version info at bottom (optional but professional)
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'v${AppConfig.kApiVersion}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 10,
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
