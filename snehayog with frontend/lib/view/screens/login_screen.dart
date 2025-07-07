import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

Future<void> registerUserOnBackend(Map<String, dynamic> user) async {
  final response = await http.post(
    Uri.parse('https://snehayog-production.up.railway.app/api/users/register'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({
      'googleId': user['id'],
      'name': user['name'],
      'email': user['email'],
      'profilePic': user['photoUrl'],
    }),
  );

  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception('User registration failed: ${response.body}');
  }

  print('✅ User registered: ${response.body}');
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome to Snehayog',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Consumer<GoogleSignInController>(
              builder: (context, authController, _) {
                if (authController.isLoading) {
                  return const CircularProgressIndicator();
                }

                if (authController.error != null) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      authController.error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ElevatedButton.icon(
                  onPressed: () async {
                    final user = await authController
                        .signIn(); // returns Map<String, dynamic>?
                    if (user == null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to sign in with Google'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    try {
                      await registerUserOnBackend(
                          user!); // ✅ Register to Node.js backend
                      // Optional: Navigate to home screen
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/home');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('❌ Backend registration failed: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: Image.network(
                    'https://www.google.com/favicon.ico',
                    height: 24,
                  ),
                  label: const Text('Sign in with Google'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
