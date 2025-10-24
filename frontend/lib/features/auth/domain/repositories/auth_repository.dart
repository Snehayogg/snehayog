import 'package:vayu/features/auth/domain/entities/user_entity.dart';

abstract class AuthRepository {
  /// Sign in with Google
  Future<UserEntity> signInWithGoogle(UserEntity user);
  
  /// Sign out user
  Future<void> signOut();
  
  /// Get current user
  Future<UserEntity?> getCurrentUser();
  
  /// Check if user is authenticated
  Future<bool> isAuthenticated();
  
  /// Refresh user token
  Future<UserEntity> refreshToken();
  
  /// Delete user account
  Future<void> deleteAccount();
}
