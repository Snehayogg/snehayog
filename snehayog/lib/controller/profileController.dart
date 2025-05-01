import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/usermodel.dart';
import 'package:snehayog/utils/constant.dart';

class ProfileController extends ChangeNotifier {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'], 
  );

  UserModel? user;
  bool isLoading = false;
  String? error;

  ProfileController() {
    _initializeGoogleSignIn();
  }

  Future<void> _initializeGoogleSignIn() async {
    try {
      print('Initializing Google Sign-In...');
      if (await _googleSignIn.isSignedIn()) {
        print('User is already signed in');
        final account = await _googleSignIn.signInSilently();
        if (account != null) {
          print('Successfully signed in silently with email: ${account.email}');
          await _fetchUserData(account);
        }
      } else {
        print('No user is currently signed in');
      }
    } catch (e, stackTrace) {
      print("Initialization error: $e");
      print("Stack trace: $stackTrace");
      if (e is PlatformException) {
        print("Platform exception code: ${e.code}");
        print("Platform exception message: ${e.message}");
        print("Platform exception details: ${e.details}");
        if (e.code == 'sign_in_failed') {
          error = "Google Sign-In failed. Please check your configuration. Error details: ${e.message}";
        } else if (e.code == 'network_error') {
          error = "Network error. Please check your internet connection.";
        } else {
          error = "Sign in error: ${e.message}";
        }
      } else {
        error = "Unexpected error: $e";
      }
      notifyListeners();
    }
  }

  Future<void> _fetchUserData(GoogleSignInAccount account) async {
    try {
      print('Fetching authentication token...');
      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        error = "Failed to get ID token from Google. Please try signing in again.";
        print('ID token is null');
        return;
      }

      print('ID token obtained successfully');
      print('Attempting to fetch user data with ID token');

      final res = await http.post(
        Uri.parse("$BASE_URL/api/auth"),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({"idToken": idToken}),
      );

      print('Server response status: ${res.statusCode}');
      print('Server response body: ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        user = UserModel.fromJson(data['user']);
        error = null;
        print('User data fetched successfully');
      } else {
        error = "Failed to fetch user data: ${res.statusCode}\n${res.body}";
        print("Server error: ${res.body}");
      }
    } catch (e) {
      error = "Error fetching user data: $e";
      print("User data fetch error: $e");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      isLoading = true;
      error = null;
      notifyListeners();

      print('Starting Google Sign-In process...');

      if (await _googleSignIn.isSignedIn()) {
        print('User is already signed in, signing out first...');
        await _googleSignIn.signOut();
      }

      print('Initiating Google Sign-In...');
      final account = await _googleSignIn.signIn();

      if (account == null) {
        error = "Sign in cancelled by user";
        print('Sign in was cancelled by user');
        isLoading = false;
        notifyListeners();
        return;
      }

      print('Google Sign-In successful with email: ${account.email}');
      await _fetchUserData(account);
    } on PlatformException catch (e) {
      print('Platform exception during sign in: $e');
      if (e.code == 'sign_in_failed') {
        error = "Google Sign-In failed. Please check your configuration.";
      } else if (e.code == 'network_error') {
        error = "Network error. Please check your internet connection.";
      } else {
        error = "Sign in error: ${e.message}";
      }
      isLoading = false;
      notifyListeners();
    } catch (e) {
      print('Unexpected error during sign in: $e');
      error = "Sign in error: $e";
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      isLoading = true;
      notifyListeners();

      print('Logging out...');
      await _googleSignIn.signOut();
      user = null;
      error = null;
      print('Logout successful');
    } catch (e) {
      print('Error during logout: $e');
      error = "Logout error: $e";
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
