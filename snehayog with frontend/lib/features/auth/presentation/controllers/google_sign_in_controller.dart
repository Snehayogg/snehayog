import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:snehayog/features/auth/domain/repositories/auth_repository.dart';
import 'package:snehayog/features/auth/domain/entities/user_entity.dart';
import 'package:snehayog/features/auth/data/repositories/auth_repository_impl.dart';

class GoogleSignInController extends ChangeNotifier {
  final AuthRepository _authRepository;
  final GoogleSignIn _googleSignIn;
  
  bool _isLoading = false;
  UserEntity? _currentUser;
  String? _errorMessage;

  GoogleSignInController({AuthRepository? authRepository})
      : _authRepository = authRepository ?? AuthRepositoryImpl(),
        _googleSignIn = GoogleSignIn(
          scopes: ['email', 'profile'],
        );

  // Getters
  bool get isLoading => _isLoading;
  UserEntity? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  bool get isSignedIn => _currentUser != null;

  // Sign in with Google
  Future<void> signIn() async {
    try {
      _setLoading(true);
      _clearError();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      final user = UserEntity(
        id: googleUser.id,
        name: googleUser.displayName ?? '',
        email: googleUser.email,
        profilePic: googleUser.photoUrl ?? '',
        googleId: googleUser.id,
      );

      // Save user to backend
      final savedUser = await _authRepository.signInWithGoogle(user);
      _currentUser = savedUser;
      
      _setLoading(false);
      notifyListeners();
      
    } catch (error) {
      _setError('Failed to sign in: ${error.toString()}');
      _setLoading(false);
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      _setLoading(true);
      
      await _googleSignIn.signOut();
      await _authRepository.signOut();
      
      _currentUser = null;
      _setLoading(false);
      notifyListeners();
      
    } catch (error) {
      _setError('Failed to sign out: ${error.toString()}');
      _setLoading(false);
    }
  }

  // Check if user is already signed in
  Future<void> checkSignInStatus() async {
    try {
      final user = await _authRepository.getCurrentUser();
      if (user != null) {
        _currentUser = user;
        notifyListeners();
      }
    } catch (error) {
      // User not signed in or error occurred
      _currentUser = null;
    }
  }

  // Clear current user (for testing or reset)
  void clearUser() {
    _currentUser = null;
    notifyListeners();
  }

  // Private methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

}
