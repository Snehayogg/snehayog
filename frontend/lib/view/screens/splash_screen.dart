import 'package:flutter/material.dart';
import 'package:vayu/main.dart'; // Access to AuthWrapper
import 'package:vayu/core/managers/app_initialization_manager.dart';
import 'package:vayu/config/app_config.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1), // Simple 1 second duration
    );

    // Simple Fade In
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    // Start animation immediately
    _controller.forward().then((_) {
      _checkAndNavigate();
    });

    // Fire initialization in background
    _startBackgroundInitialization();
  }

  Future<void> _startBackgroundInitialization() async {
    if (mounted) {
      await AppInitializationManager.instance.initializeStage2(context);
      _checkAndNavigate();
    }
  }

  void _checkAndNavigate() {
    if (!mounted) return;

    // Condition: Animation MUST be done AND Init MUST be done
    if (_controller.isCompleted &&
        AppInitializationManager.instance.isStage2Complete) {
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
    _controller.dispose();
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
                        child: ValueListenableBuilder<double>(
                          valueListenable: initManager.initializationProgress,
                          builder: (context, progress, _) {
                            return TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.fastOutSlowIn,
                              tween: Tween<double>(begin: 0, end: progress),
                              builder: (context, value, _) {
                                return LinearProgressIndicator(
                                  value: value,
                                  backgroundColor: Colors.white.withAlpha(30),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                  minHeight: 3,
                                );
                              },
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
