import 'package:vayu/features/auth/domain/entities/user_entity.dart';
import 'package:vayu/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  UserEntity? _currentUser;

  @override
  Future<UserEntity> signInWithGoogle(UserEntity user) async {
    // Simulate API call delay
    await Future.delayed(const Duration(milliseconds: 500));

    _currentUser = user;
    return user;
  }

  @override
  Future<void> signOut() async {
    // Simulate API call delay
    await Future.delayed(const Duration(milliseconds: 300));

    _currentUser = null;
  }

  @override
  Future<UserEntity?> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _currentUser;
  }

  @override
  Future<bool> isAuthenticated() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _currentUser != null;
  }

  @override
  Future<UserEntity> refreshToken() async {
    // Simulate API call delay
    await Future.delayed(const Duration(milliseconds: 400));
    
    if (_currentUser == null) {
      throw Exception('No user to refresh token for');
    }
    
    return _currentUser!;
  }

  @override
  Future<void> deleteAccount() async {
    // Simulate API call delay
    await Future.delayed(const Duration(milliseconds: 600));
    
    // Clear local user
    _currentUser = null;
  }
}
