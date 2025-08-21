import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/user_service.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/core/constants/profile_constants.dart';

class ProfileStateManager extends ChangeNotifier {
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  // State variables
  List<VideoModel> _userVideos = [];
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _userData;
  bool _isEditing = false;
  bool _isSelecting = false;
  final Set<String> _selectedVideoIds = {};

  // Controllers
  final TextEditingController nameController = TextEditingController();

  // Getters
  List<VideoModel> get userVideos => _userVideos;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get userData => _userData;
  bool get isEditing => _isEditing;
  bool get isSelecting => _isSelecting;
  Set<String> get selectedVideoIds => _selectedVideoIds;
  bool get hasSelectedVideos => _selectedVideoIds.isNotEmpty;

  // Profile management
  Future<void> loadUserData(String? userId) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile = userId == null || userId == loggedInUser?['id'];

      Map<String, dynamic>? userData;
      if (isMyProfile) {
        userData = loggedInUser;
        // Load saved profile data for the logged-in user
        final savedName = await _loadSavedName();
        final savedProfilePic = await _loadSavedProfilePic();
        if (userData != null) {
          userData['name'] = savedName ?? userData['name'];
          userData['profilePic'] = savedProfilePic ?? userData['profilePic'];
        }
      } else {
        // Fetch profile data for another user
        userData = await _userService.getUserById(userId);
      }

      if (userData != null) {
        setState(() {
          _userData = userData;
          _isLoading = false;
        });
        await loadUserVideos(userId);
      } else {
        setState(() {
          _isLoading = false;
          _error = ProfileConstants.errorLoadingData;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading user data: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> loadUserVideos(String? userId) async {
    try {
      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile = userId == null || userId == loggedInUser?['id'];

      if (isMyProfile) {
        final videos =
            await _videoService.getUserVideos(loggedInUser?['id'] ?? '');
        setState(() {
          _userVideos = videos;
        });
      } else {
        final videos = await _videoService.getUserVideos(userId!);
        setState(() {
          _userVideos = videos;
        });
      }
    } catch (e) {
      setState(() {
        _error = '${ProfileConstants.errorLoadingVideos}${e.toString()}';
      });
    }
  }

  // Profile editing
  void startEditing() {
    if (_userData != null) {
      _isEditing = true;
      nameController.text = _userData!['name'] ?? '';
      notifyListeners();
    }
  }

  void cancelEditing() {
    _isEditing = false;
    nameController.clear();
    notifyListeners();
  }

  Future<void> saveProfile() async {
    if (_userData != null && nameController.text.isNotEmpty) {
      try {
        final newName = nameController.text.trim();
        await _saveProfileData(newName, _userData!['profilePic']);

        setState(() {
          _userData!['name'] = newName;
          _isEditing = false;
        });

        nameController.clear();
        notifyListeners();
      } catch (e) {
        setState(() {
          _error = 'Failed to save profile: ${e.toString()}';
        });
      }
    }
  }

  Future<void> updateProfilePhoto(String? profilePic) async {
    if (_userData != null) {
      await _saveProfileData(_userData!['name'], profilePic);
      setState(() {
        _userData!['profilePic'] = profilePic;
      });
      notifyListeners();
    }
  }

  // Video selection management
  void toggleVideoSelection(String videoId) {
    print('🔍 toggleVideoSelection called with videoId: $videoId');
    print('🔍 Current selectedVideoIds: $_selectedVideoIds');

    if (_selectedVideoIds.contains(videoId)) {
      _selectedVideoIds.remove(videoId);
      print('🔍 Removed videoId: $videoId');
    } else {
      _selectedVideoIds.add(videoId);
      print('🔍 Added videoId: $videoId');
    }

    print('🔍 Updated selectedVideoIds: $_selectedVideoIds');
    notifyListeners();
  }

  void clearSelection() {
    print('🔍 clearSelection called');
    _selectedVideoIds.clear();
    notifyListeners();
  }

  void exitSelectionMode() {
    print('🔍 exitSelectionMode called');
    _isSelecting = false;
    _selectedVideoIds.clear();
    notifyListeners();
  }

  void enterSelectionMode() {
    print('🔍 enterSelectionMode called');
    _isSelecting = true;
    notifyListeners();
  }

  Future<void> deleteSelectedVideos() async {
    if (_selectedVideoIds.isEmpty) return;

    try {
      // Delete videos logic here
      // await _videoService.deleteVideos(_selectedVideoIds.toList());

      // Remove deleted videos from the list
      _userVideos.removeWhere((video) => _selectedVideoIds.contains(video.id));

      // Clear selection and exit selection mode
      exitSelectionMode();

      notifyListeners();
    } catch (e) {
      setState(() {
        _error = 'Failed to delete videos: ${e.toString()}';
      });
    }
  }

  // Utility methods
  Future<String?> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name');
  }

  Future<String?> _loadSavedProfilePic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_profile_pic');
  }

  Future<void> _saveProfileData(String name, String? profilePic) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    if (profilePic != null) {
      await prefs.setString('user_profile_pic', profilePic);
    }
  }

  void setState(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  // Error handling
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Authentication methods
  Future<void> handleLogout() async {
    try {
      await _authService.signOut();
      setState(() {
        _userData = null;
        _userVideos = [];
        _isEditing = false;
        _isSelecting = false;
        _selectedVideoIds.clear();
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to logout: ${e.toString()}';
      });
    }
  }

  Future<Map<String, dynamic>?> handleGoogleSignIn() async {
    try {
      final userData = await _authService.signInWithGoogle();
      if (userData != null) {
        setState(() {
          _userData = userData;
          _isLoading = false;
          _error = null;
        });
        await loadUserVideos(null); // Load videos for the signed-in user
      }
      return userData;
    } catch (e) {
      setState(() {
        _error = 'Failed to sign in: ${e.toString()}';
      });
      return null;
    }
  }

  // Getter for user data
  Map<String, dynamic>? getUserData() => _userData;

  // Cleanup
  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }
}
