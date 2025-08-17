import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:snehayog/core/theme/app_theme.dart';
import 'package:snehayog/core/widgets/loading_button.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(60),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.video_library,
                  size: 60,
                  color: AppTheme.primaryColor,
                ),
              ),
              
              const SizedBox(height: 40),
              
              // App Title
              const Text(
                'Snehayog',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // App Subtitle
              const Text(
                'Share your moments with the world',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 60),
              
              // Google Sign In Button
              Consumer<GoogleSignInController>(
                builder: (context, controller, child) {
                  return LoadingButton(
                    onPressed: controller.isLoading ? null : controller.signIn,
                    isLoading: controller.isLoading,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/icons/google_icon.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.g_mobiledata,
                                size: 24,
                                color: AppTheme.primaryColor,
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Continue with Google',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 40),
              
              // Terms and Privacy
              const Text(
                'By continuing, you agree to our Terms of Service and Privacy Policy',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white60,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
