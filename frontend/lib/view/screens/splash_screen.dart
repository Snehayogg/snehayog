import 'package:flutter/material.dart';
import 'package:vayu/main.dart'; // Access to AuthWrapper
import 'package:vayu/core/managers/app_initialization_manager.dart';

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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: FadeTransition(
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
      ),
    );
  }
}
