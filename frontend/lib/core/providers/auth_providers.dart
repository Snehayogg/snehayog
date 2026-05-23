import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';

final authServiceProvider = Provider<IAuthService>((ref) {
  return AuthService();
});

final googleSignInProvider = ChangeNotifierProvider<GoogleSignInController>((ref) {
  final authService = ref.watch(authServiceProvider);
  return GoogleSignInController(authService: authService);
});
