import 'package:flutter/material.dart';
import 'package:vayu/main.dart'; // Access to AuthWrapper
import 'package:vayu/core/managers/app_initialization_manager.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
    // Increased duration for fade-in phase
      vsync: this,
      duration: const Duration(milliseconds: 2300), 
    );

    // Sequence:
    // 0.0 -> 0.3: Fade In (Opacity 0->1)
    // 0.3 -> 0.5: Breath In (Scale 1.0 -> 0.9)
    // 0.5 -> 1.0: Zoom Out (Scale 0.9 -> 80)
    
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30.0,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 70.0,
      ),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 30.0, // Wait for fade in
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.9)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.9, end: 100.0)
            .chain(CurveTween(curve: Curves.easeInExpo)),
        weight: 50.0,
      ),
    ]).animate(_controller);

    // Start animation immediately
    _controller.forward().then((_) async {
       // Wait for Stage 1 (Config) - Critical
       await AppInitializationManager.instance.initializeStage1();
       
       // Wait for Stage 2 (Content) - Critical for Video Loading
       // We revert to waiting here to ensure data is ready before Home screen mounts
       await AppInitializationManager.instance.initializeStage2(context);
       
       _navigateToHome();
    });
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
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacityAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            );
          },
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
