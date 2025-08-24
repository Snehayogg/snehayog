import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/user_service.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/core/constants/profile_constants.dart';
import 'package:snehayog/core/providers/video_provider.dart';

class ProfileStateManager extends ChangeNotifier {
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  // BuildContext to access VideoProvider
  BuildContext? _context;

  // Set context when needed
  void setContext(BuildContext context) {
    _context = context;
  }

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
      print('🔄 ProfileStateManager: Loading user data for userId: $userId');

      final loggedInUser = await _authService.getUserData();
      print('🔄 ProfileStateManager: Logged in user: ${loggedInUser?['id']}');

      // Check if we have any authentication data
      if (loggedInUser == null) {
        print('❌ ProfileStateManager: No authentication data available');
        _isLoading = false;
        _error = 'No authentication data available. Please sign in.';
        notifyListeners();
        return;
      }

      final bool isMyProfile = userId == null || userId == loggedInUser?['id'];
      print('🔄 ProfileStateManager: Is my profile: $isMyProfile');

      Map<String, dynamic>? userData;
      if (isMyProfile) {
        // Load own profile data
        userData = loggedInUser;
        if (userData != null) {
          // Load saved profile data for the logged-in user
          final savedName = await _loadSavedName();
          final savedProfilePic = await _loadSavedProfilePic();
          userData['name'] = savedName ?? userData['name'];
          userData['profilePic'] = savedProfilePic ?? userData['profilePic'];
          print(
              '🔄 ProfileStateManager: Loaded own profile data: ${userData['name']}');
        }
      } else {
        // Fetch profile data for another user
        print(
            '🔄 ProfileStateManager: Fetching other user profile for ID: $userId');
        userData = await _userService.getUserById(userId);
        print(
            '🔄 ProfileStateManager: Other user profile loaded: ${userData?['name']}');
      }

      if (userData != null) {
        _userData = userData;
        _isLoading = false;
        notifyListeners();
        print(
            '🔄 ProfileStateManager: User data loaded successfully, now loading videos');
        await loadUserVideos(userId);
      } else {
        _isLoading = false;
        _error = ProfileConstants.errorLoadingData;
        notifyListeners();
        print('❌ ProfileStateManager: Failed to load user data');
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error loading user data: $e');
      _error = 'Error loading user data: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadUserVideos(String? userId) async {
    try {
      print('🔄 ProfileStateManager: Loading videos for userId: $userId');

      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile = userId == null || userId == loggedInUser?['id'];

      print(
          '🔄 ProfileStateManager: Loading videos - isMyProfile: $isMyProfile');

      String targetUserId;
      if (isMyProfile) {
        targetUserId = loggedInUser?['id'] ?? '';
        print(
            '🔄 ProfileStateManager: Loading own videos with ID: $targetUserId');
      } else {
        targetUserId = userId ?? '';
        print(
            '🔄 ProfileStateManager: Loading other user videos with ID: $targetUserId');
      }

      if (targetUserId.isNotEmpty) {
        final videos = await _videoService.getUserVideos(targetUserId);
        print(
            '🔄 ProfileStateManager: Loaded ${videos.length} videos for user: $targetUserId');

        _userVideos = videos;
        notifyListeners();
      } else {
        print('⚠️ ProfileStateManager: No valid user ID for video loading');
        _userVideos = [];
        notifyListeners();
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error loading user videos: $e');
      _error = '${ProfileConstants.errorLoadingVideos}${e.toString()}';
      _userVideos = [];
      notifyListeners();
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
      print(
          '🗑️ ProfileStateManager: Starting deletion of ${_selectedVideoIds.length} videos');

      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Create a copy of selected IDs for processing
      final videoIdsToDelete = List<String>.from(_selectedVideoIds);

      // Attempt to delete videos from the backend
      final deletionSuccess =
          await _videoService.deleteVideos(videoIdsToDelete);

      if (deletionSuccess) {
        print(
            '✅ ProfileStateManager: All videos deleted successfully from backend');

        // Remove deleted videos from local list
        _userVideos.removeWhere((video) => videoIdsToDelete.contains(video.id));

        // Clear selection and exit selection mode
        exitSelectionMode();

        setState(() {
          _isLoading = false;
        });

        // Notify VideoProvider to update the main video feed
        if (_context != null) {
          try {
            final videoProvider =
                Provider.of<VideoProvider>(_context!, listen: false);
            videoProvider.removeVideosFromList(videoIdsToDelete);
            print(
                '✅ ProfileStateManager: Notified VideoProvider of deleted videos');
          } catch (e) {
            print('⚠️ ProfileStateManager: Could not notify VideoProvider: $e');
          }
        }

        print(
            '✅ ProfileStateManager: Local state updated after successful deletion');
      } else {
        throw Exception('Backend deletion failed');
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error deleting videos: $e');

      setState(() {
        _isLoading = false;
        _error = _getUserFriendlyErrorMessage(e);
      });

      // Don't exit selection mode on error - let user retry
      notifyListeners();
    }
  }

  /// Deletes a single video with enhanced error handling
  Future<bool> deleteSingleVideo(String videoId) async {
    try {
      print('🗑️ ProfileStateManager: Deleting single video: $videoId');

      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Delete from backend
      final deletionSuccess = await _videoService.deleteVideo(videoId);

      if (deletionSuccess) {
        print('✅ ProfileStateManager: Single video deleted successfully');

        // Remove from local list
        _userVideos.removeWhere((video) => video.id == videoId);

        setState(() {
          _isLoading = false;
        });

        // Notify VideoProvider to update the main video feed
        if (_context != null) {
          try {
            final videoProvider =
                Provider.of<VideoProvider>(_context!, listen: false);
            videoProvider.removeVideoFromList(videoId);
            print(
                '✅ ProfileStateManager: Notified VideoProvider of deleted video');
          } catch (e) {
            print('⚠️ ProfileStateManager: Could not notify VideoProvider: $e');
          }
        }

        return true;
      } else {
        throw Exception('Backend deletion failed');
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error deleting single video: $e');

      setState(() {
        _isLoading = false;
        _error = _getUserFriendlyErrorMessage(e);
      });

      return false;
    }
  }

  /// Converts technical error messages to user-friendly messages
  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('timeout')) {
      return 'Request timed out. Please check your connection and try again.';
    } else if (errorString.contains('network')) {
      return 'Network error. Please check your internet connection.';
    } else if (errorString.contains('unauthorized') ||
        errorString.contains('sign in')) {
      return 'Please sign in again to delete videos.';
    } else if (errorString.contains('permission') ||
        errorString.contains('forbidden')) {
      return 'You do not have permission to delete these videos.';
    } else if (errorString.contains('not found')) {
      return 'One or more videos were not found.';
    } else if (errorString.contains('conflict')) {
      return 'Videos cannot be deleted at this time. Please try again later.';
    } else {
      return 'Failed to delete videos. Please try again.';
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

  /// Refreshes user data and videos
  Future<void> refreshData() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Get the current user ID from userData or logged in user
      String? targetUserId;
      if (_userData != null && _userData!['id'] != null) {
        targetUserId = _userData!['id'];
        print(
            '🔄 ProfileStateManager: Refreshing data for user: $targetUserId');
      } else {
        final loggedInUser = await _authService.getUserData();
        targetUserId = loggedInUser?['id'];
        print(
            '🔄 ProfileStateManager: Refreshing data for logged in user: $targetUserId');
      }

      // Reload user data and videos
      await loadUserData(targetUserId);

      _isLoading = false;
      notifyListeners();

      print('✅ ProfileStateManager: Data refreshed successfully');
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to refresh data: ${e.toString()}';
      notifyListeners();
      print('❌ ProfileStateManager: Error refreshing data: $e');
    }
  }

  /// Force refresh videos only (for when new videos are uploaded)
  Future<void> refreshVideosOnly() async {
    try {
      print('🔄 ProfileStateManager: Force refreshing user videos...');

      // Get the current user ID from userData or logged in user
      String? targetUserId;
      if (_userData != null && _userData!['id'] != null) {
        targetUserId = _userData!['id'];
        print(
            '🔄 ProfileStateManager: Refreshing videos for user: $targetUserId');
      } else {
        final loggedInUser = await _authService.getUserData();
        targetUserId = loggedInUser?['id'];
        print(
            '🔄 ProfileStateManager: Refreshing videos for logged in user: $targetUserId');
      }

      if (targetUserId != null && targetUserId.isNotEmpty) {
        final videos = await _videoService.getUserVideos(targetUserId);
        _userVideos = videos;
        notifyListeners();
        print(
            '✅ ProfileStateManager: Videos refreshed successfully. Count: ${videos.length}');
      } else {
        print('⚠️ ProfileStateManager: No valid user ID for video refresh');
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error refreshing videos: $e');
      _error = 'Failed to refresh videos: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Add a new video to the profile (called after successful upload)
  void addNewVideo(VideoModel video) {
    print(
        '➕ ProfileStateManager: Adding new video to profile: ${video.videoName}');
    _userVideos.insert(0, video); // Add to the beginning of the list
    notifyListeners();
  }

  /// Remove a video from the profile
  void removeVideo(String videoId) {
    print('➖ ProfileStateManager: Removing video from profile: $videoId');
    _userVideos.removeWhere((video) => video.id == videoId);
    notifyListeners();
  }

  // Cleanup
  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }
}
