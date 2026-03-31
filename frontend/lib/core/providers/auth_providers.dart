import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/auth/presentation/controllers/google_sign_in_controller.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final googleSignInProvider = ChangeNotifierProvider<GoogleSignInController>((ref) {
  return GoogleSignInController();
});
