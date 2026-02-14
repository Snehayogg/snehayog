import 'package:flutter/material.dart';
import 'package:vayu/features/video/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayu/features/video/presentation/managers/video_controller_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainController extends ChangeNotifier {
  int _currentIndex = 0;
  final List<String> _routes = ['/yug', '/vayu', '/games', '/upload', '/profile'];
  bool _isAppInForeground = true;
  bool _isMediaPickerActive = false;
  DateTime? _lastPickerReturnAt;

  static const String _lastTabIndexKey = 'last_tab_index';
  static const String _lastTabTimestampKey = 'last_tab_timestamp';

  // Add a callback function to pause videos
  VoidCallback? _pauseVideosCallback;
  VoidCallback? _resumeVideosCallback;

  /// **NEW: Register video pause callback from VideoFeedAdvanced**
  void registerVideoPauseCallback(VoidCallback callback) {
    _pauseVideosCallback = callback;

  }

  /// **NEW: Register video resume callback from VideoFeedAdvanced**
  void registerVideoResumeCallback(VoidCallback callback) {
    _resumeVideosCallback = callback;

  }

  int get currentIndex => _currentIndex;
  String get currentRoute => _routes[_currentIndex];
  bool get isAppInForeground => _isAppInForeground;
  bool get isMediaPickerActive => _isMediaPickerActive;

  /// Change the current index and handle video control
  void changeIndex(int index) {
    if (_currentIndex == index) return; // No change needed



    _handleIndexChangeFallback(index);

    // **CRITICAL FIX: Add delay before updating index to ensure proper state transition**
    Future.delayed(const Duration(milliseconds: 100), () {
      // Update the current index
      _currentIndex = index;

      // **NEW: Save tab index when it changes**
      _saveCurrentTabIndex();
      notifyListeners();
    });
  }

  /// **NEW: Fallback method for when VideoManager is not available**
  void _handleIndexChangeFallback(int index) {
    // If we're leaving the video tab (index 0), pause videos immediately
    if (_currentIndex == 0) {


      // IMMEDIATE video pause
      _pauseVideosCallback?.call();


      // SINGLE safety delay to ensure videos are paused after state transition
      Future.delayed(const Duration(milliseconds: 150), () {
        if (_currentIndex != 0) {
          _pauseVideosCallback?.call();
        }
      });
    }

    // If we're entering the video tab, resume videos
    if (index == 0 && isAppInForeground) {

      _resumeVideosCallback?.call();
    }
  }

  void navigateToProfile() {
    _currentIndex = 4; // Profile index
    notifyListeners();
  }

  /// Mark media picker active/inactive and record return time
  void setMediaPickerActive(bool active) {
    _isMediaPickerActive = active;
    if (!active) {
      _lastPickerReturnAt = DateTime.now();
    }
    notifyListeners();
  }

  /// Cooldown check after picker returns to avoid autoplay leak
  bool get recentlyReturnedFromPicker {
    if (_lastPickerReturnAt == null) return false;
    return DateTime.now().difference(_lastPickerReturnAt!).inMilliseconds <
        1200;
  }

  void setAppInForeground(bool inForeground) {
    if (_isAppInForeground != inForeground) {
      _isAppInForeground = inForeground;


      // **SIMPLIFIED: App foreground state update (VideoManager removed)**

      notifyListeners();
    }
  }

  /// Check if the current screen is the video screen
  bool get isVideoScreen => _currentIndex == 0;

  /// Check if videos should be playing based on current state
  bool get shouldPlayVideos => _isAppInForeground && isVideoScreen;

  /// **SIMPLIFIED: Video tracking info (VideoManager removed)**
  Map<String, dynamic>? getVideoTrackingInfo() {
    return null; // VideoManager was removed
  }

  /// **SIMPLIFIED: Current visible video index (VideoManager removed)**
  int get currentVisibleVideoIndex {
    return 0; // VideoManager was removed
  }

  /// Register callback to pause videos
  void registerPauseVideosCallback(VoidCallback callback) {
    _pauseVideosCallback = callback;
  }

  /// Register callback to resume videos
  void registerResumeVideosCallback(VoidCallback callback) {
    _resumeVideosCallback = callback;
  }

  /// Unregister callbacks
  void unregisterCallbacks() {
    _pauseVideosCallback = null;
    _resumeVideosCallback = null;
  }

  /// Force pause all videos (called from external sources)
  void forcePauseVideos() {
    // **IMPROVED: Pause controllers instead of disposing for better UX**
    try {
      final sharedPool = SharedVideoControllerPool();
      sharedPool.pauseAllControllers();
      
      // ALSO pause VideoControllerManager (used by legacy components or direct feed)
      VideoControllerManager().forcePauseAllVideosSync();
    } catch (e) {
      // Ignore errors during pause
    }

    // **SIMPLIFIED: Use callback since VideoManager was removed**
    _pauseVideosCallback?.call();
  }

  /// Resume videos (called when app comes back to foreground)
  void resumeVideos() {


    // **SIMPLIFIED: Use callback since VideoManager was removed**
    _resumeVideosCallback?.call();
  }

  /// Check if videos should be paused based on current state
  bool get shouldPauseVideos => !isVideoScreen || !isAppInForeground;

  /// **NEW: Handle back button press with proper navigation lifecycle**
  /// Returns true if app should exit, false if navigation should continue
  bool handleBackPress() {
    // If we're not on the home tab (index 0), navigate back to home tab
    if (_currentIndex != 0) {

      changeIndex(0);
      return false; // Don't exit the app
    }

    // If we're on home tab (index 0), app should exit

    return true; // Exit the app
  }

  /// **NEW: Check if we're on the home tab (where app can exit)**
  bool get isOnHomeTab => _currentIndex == 0;

  /// Emergency stop all videos (for critical situations)
  void emergencyStopVideos() {


    // **SIMPLIFIED: Use callback since VideoManager was removed**
    _pauseVideosCallback?.call();

    // Multiple safety calls to ensure videos are stopped
    Future.delayed(const Duration(milliseconds: 50), () {
      _pauseVideosCallback?.call();
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      _pauseVideosCallback?.call();
    });
  }

  /// **NEW: Handle app backgrounding with immediate pause**
  void handleAppBackgrounded() {

    _isAppInForeground = false;
    forcePauseVideos();
    notifyListeners();
  }

  /// **NEW: Handle app foregrounding with delayed resume**
  void handleAppForegrounded() {

    _isAppInForeground = true;
    notifyListeners();

    // Only resume if on video tab
    if (isVideoScreen) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_isAppInForeground && isVideoScreen) {
          resumeVideos();
        }
      });
    }
  }

  /// **SIMPLIFIED: Update current video index (VideoManager removed)**
  void updateCurrentVideoIndex(int newIndex) {
    // VideoManager was removed
  }

  /// **SIMPLIFIED: Get comprehensive video state info (VideoManager removed)**
  Map<String, dynamic> getComprehensiveVideoState() {
    return <String, dynamic>{
      'currentIndex': _currentIndex,
      'isVideoScreen': isVideoScreen,
      'isAppInForeground': _isAppInForeground,
      'shouldPlayVideos': shouldPlayVideos,
      'shouldPauseVideos': shouldPauseVideos,
      'hasVideoManager': false, // VideoManager was removed
    };
  }

  /// **FIXED: Centralized logout method to clear all state**
  Future<void> performLogout({bool resetIndex = true}) async {
    try {


      // **FIXED: Reset main controller state**
      if (resetIndex) {
        _currentIndex = 0;
        await _saveCurrentTabIndex();
      }
      _isAppInForeground = true;
      _pauseVideosCallback = null;
      _resumeVideosCallback = null;


      notifyListeners();
    } catch (e) {

    }
  }

  /// **NEW: Save current tab index to SharedPreferences**
  Future<void> _saveCurrentTabIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastTabIndexKey, _currentIndex);
      await prefs.setInt(
          _lastTabTimestampKey, DateTime.now().millisecondsSinceEpoch);

    } catch (e) {

    }
  }

  /// **NEW: Restore last tab index from SharedPreferences**
  /// Returns the restored index, or 0 if no saved state or state is too old
  Future<int> restoreLastTabIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt(_lastTabIndexKey);
      final savedTimestamp = prefs.getInt(_lastTabTimestampKey);

      // If no saved state, return default (0)
      if (savedIndex == null || savedTimestamp == null) {

        return 0;
      }

      // Check if saved state is too old (more than 7 days)
      final savedTime = DateTime.fromMillisecondsSinceEpoch(savedTimestamp);
      final daysSinceSaved = DateTime.now().difference(savedTime).inDays;

      if (daysSinceSaved > 7) {

        // Clear old state
        await prefs.remove(_lastTabIndexKey);
        await prefs.remove(_lastTabTimestampKey);
        return 0;
      }

      // Validate index is within bounds
      if (savedIndex >= 0 && savedIndex < _routes.length) {

        _currentIndex = savedIndex;
        notifyListeners();
        return savedIndex;
      } else {

        return 0;
      }
    } catch (e) {

      return 0;
    }
  }

  /// **NEW: Save tab index when app goes to background**
  Future<void> saveStateForBackground() async {

    await _saveCurrentTabIndex();
  }

  /// **NEW: Public method to save current tab index (can be called from anywhere)**
  Future<void> saveCurrentTabIndex() async {
    await _saveCurrentTabIndex();
  }

}
