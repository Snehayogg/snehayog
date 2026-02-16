import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/features/onboarding/data/services/location_onboarding_service.dart';
import 'package:vayu/features/video/presentation/managers/main_controller.dart';
import 'dart:async';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/widgets/vayu_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLocalLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<GoogleSignInController>(
        builder: (context, authController, _) {
          final bool showOverlay = authController.isLoading || _isLocalLoading;
          return Stack(
            children: [
              // Main Content
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                ),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: VayuLogo(
                                fontSize: 32,
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Welcome Text
                          const Text(
                            'Welcome to Vayu',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          Column(
                            children: [
                              const Text(
                                'Create • Video • Earn',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.verified,
                                      color: Colors.green[300],
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'No Monetization Criteria',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green[800],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 48),

                          // Sign In Section
                          if (authController.error != null) ...[
                            Column(children: [
                              Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.red[50]!,
                                        Colors.red[100]!,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.red[200]!,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.withOpacity(0.1),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      // **Error Icon with Animation**
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Colors.red[100],
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.wifi_off_rounded,
                                          color: Colors.red[600],
                                          size: 30,
                                        ),
                                      ),

                                      const SizedBox(height: 16),
                                      Text(
                                        'Connection Failed',
                                        style: TextStyle(
                                          color: Colors.red[800],
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),

                                      const SizedBox(height: 8),

                                      // **Error Message**
                                      Text(
                                        authController.error!,
                                        style: TextStyle(
                                          color: Colors.red[700],
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),

                                      const SizedBox(height: 20),

                                      // **Horizontal Button Layout**
                                      Row(
                                        children: [
                                          // Skip Button
                                          Expanded(
                                            flex: 2,
                                            child: SizedBox(
                                              height: 50,
                                              child: ElevatedButton.icon(
                                                onPressed: () async {
                                                  // Skip sign-in and go to home even during error
                                                  // Clear error state and set skip flag
                                                  authController.clearError();
                                                  final prefs =
                                                      await SharedPreferences
                                                          .getInstance();
                                                  await prefs.setBool(
                                                      'auth_skip_login', true);
                                                  if (context.mounted) {
                                                    Navigator
                                                        .pushReplacementNamed(
                                                            context, '/home');
                                                  }
                                                },
                                                icon: const Icon(
                                                  Icons.arrow_forward_ios,
                                                  color: Colors.black87,
                                                  size: 16,
                                                ),
                                                label: const Text(
                                                  'Skip',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.white,
                                                  foregroundColor:
                                                      Colors.black87,
                                                  elevation: 0,
                                                  shadowColor:
                                                      Colors.transparent,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    side: const BorderSide(
                                                      color: Colors.black87,
                                                      width: 1.2,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),

                                          const SizedBox(width: 12),

                                          // Retry Button
                                          Expanded(
                                            flex: 3,
                                            child: SizedBox(
                                              height: 50,
                                              child: ElevatedButton.icon(
                                                onPressed: () async {
                                                  // Clear error and retry
                                                  authController.clearError();
                                                  final user =
                                                      await authController
                                                          .signIn();
                                                  if (user != null &&
                                                      context.mounted) {
                                                    // Show location permission dialog for new user
                                                    final result =
                                                        await LocationOnboardingService
                                                            .showLocationOnboarding(
                                                                context);
                                                    if (result) {
                                                      AppLogger.log(
                                                          '✅ User granted location permission');
                                                    } else {
                                                      AppLogger.log(
                                                          '❌ User denied location permission');
                                                    }

                                                    Navigator
                                                        .pushReplacementNamed(
                                                            context, '/home');
                                                  }
                                                },
                                                icon: const Icon(
                                                  Icons.refresh_rounded,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                  'Retry Connection',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                style:
                                                    ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.red[600],
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  shadowColor:
                                                      Colors.transparent,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 12),

                                      // **Additional Help Text**
                                      Text(
                                        'Check your internet connection and try again',
                                        style: TextStyle(
                                          color: Colors.red[600],
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ))
                            ])
                          ] else ...[
                            Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 45,
                                  child: ElevatedButton.icon(
                                    onPressed: authController.isLoading
                                        ? null
                                        : () async {
                                            final prefs =
                                                await SharedPreferences
                                                    .getInstance();
                                            await prefs.setBool(
                                                'auth_skip_login', true);
                                            Navigator.pushReplacementNamed(
                                                context, '/home');
                                          },
                                    icon: const Icon(
                                      Icons.arrow_forward_ios,
                                      color: Colors.black87,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Skip',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black87,
                                      elevation: 0,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(
                                          color: Colors.black87,
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // Google Sign-In Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: authController.isLoading
                                        ? null
                                        : () async {
                                            final user =
                                                await authController.signIn();
                                            if (user != null &&
                                                context.mounted) {
                                              final result =
                                                  await LocationOnboardingService
                                                      .showLocationOnboarding(
                                                          context);
                                              if (result) {
                                                AppLogger.log(
                                                    '✅ User granted location permission');
                                              } else {
                                                AppLogger.log(
                                                    '❌ User denied location permission');
                                              }

                                               // **OPTIMIZED: Parallel state refresh and pre-fetch**
                                               if (context.mounted) {
                                                 setState(() => _isLocalLoading = true);
                                                 final mainController =
                                                     Provider.of<MainController>(
                                                         context,
                                                         listen: false);
                                                 await mainController
                                                     .refreshAppStateAfterSwitch(
                                                         context);
                                               }

                                               if (context.mounted) {
                                                 Navigator.pushReplacementNamed(
                                                     context, '/home');
                                               }
                                            }
                                          },
                                    icon: Image.network(
                                      'https://www.google.com/favicon.ico',
                                      height: 24,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Image.asset(
                                        'assets/icons/google_logo.png',
                                        width: 24,
                                        height: 24,
                                      ),
                                    ),
                                    label: const Text(
                                      'Sign in with Google',
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey[700],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(
                                            color: Colors.grey[600]!),
                                      ),
                                      elevation: 2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Help Text
                          const Text(
                            'By signing in, you agree to our Terms of Service and Privacy Policy',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Loading Overlay
              if (showOverlay)
                Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Signing in...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

