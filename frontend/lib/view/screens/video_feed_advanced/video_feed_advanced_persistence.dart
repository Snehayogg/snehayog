part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedPersistence on _VideoFeedAdvancedState {
  Future<void> _saveBackgroundState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSavedFeedIndexKey, _currentIndex);
      if (widget.videoType != null) {
        await prefs.setString(_kSavedFeedTypeKey, widget.videoType!);
      }
      // **NEW: Save current video ID for better restoration**
      if (_currentIndex >= 0 && _currentIndex < _videos.length) {
        await prefs.setString(_kSavedVideoIdKey, _videos[_currentIndex].id);
        AppLogger.log(
            '💾 Saved video ID: ${_videos[_currentIndex].id} at index $_currentIndex');
      }
      // **NEW: Save current page number**
      await prefs.setInt(_kSavedPageKey, _currentPage);
      // **NEW: Save timestamp for cache validation**
      await prefs.setInt(
          _kSavedStateTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      AppLogger.log('❌ Error saving background state: $e');
    }
  }

  void _restoreRetainedControllersAfterRefresh() {
    if (_retainedByVideoId.isEmpty) return;
    AppLogger.log('🔁 Restoring retained controllers after refresh...');
    final Map<String, int> idToIndex = {};
    for (int i = 0; i < _videos.length; i++) {
      idToIndex[_videos[i].id] = i;
    }
    _retainedByVideoId.forEach((videoId, controller) {
      final newIndex = idToIndex[videoId];
      if (newIndex != null) {
        _controllerPool[newIndex] = controller;
        _controllerStates[newIndex] = false;
        _preloadedVideos.add(newIndex);
        _firstFrameReady[newIndex] =
            ValueNotifier<bool>(true); // already had a frame
        AppLogger.log(
            '✅ Restored controller for video $videoId at index $newIndex');
      } else {
        try {
          controller.dispose();
          AppLogger.log(
              '🗑️ Disposed retained controller for old video $videoId');
        } catch (_) {}
      }
    });
    _retainedByVideoId.clear();
    _retainedIndices.clear();
  }

  Future<void> _restoreBackgroundStateIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt(_kSavedFeedIndexKey);
      final savedType = prefs.getString(_kSavedFeedTypeKey);
      final savedVideoId = prefs.getString(_kSavedVideoIdKey);
      final savedTimestamp = prefs.getInt(_kSavedStateTimestampKey);

      // **NEW: Check if saved state is too old (more than 24 hours)**
      if (savedTimestamp != null) {
        final savedTime = DateTime.fromMillisecondsSinceEpoch(savedTimestamp);
        final hoursSinceSaved = DateTime.now().difference(savedTime).inHours;
        if (hoursSinceSaved > 24) {
          AppLogger.log(
              'ℹ️ Saved state is too old ($hoursSinceSaved hours), ignoring');
          // Clear old state
          await prefs.remove(_kSavedFeedIndexKey);
          await prefs.remove(_kSavedFeedTypeKey);
          await prefs.remove(_kSavedVideoIdKey);
          await prefs.remove(_kSavedPageKey);
          await prefs.remove(_kSavedStateTimestampKey);
          return;
        }
      }

      // **NEW: Try to restore by video ID first (more reliable than index)**
      if (savedVideoId != null && _videos.isNotEmpty) {
        final videoIndex = _videos.indexWhere((v) => v.id == savedVideoId);
        if (videoIndex != -1) {
          AppLogger.log(
              '✅ Restored to video ID: $savedVideoId at index $videoIndex');
          _currentIndex = videoIndex;
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentIndex);
          }
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _tryAutoplayCurrent());
          return;
        }
      }

      // **FALLBACK: Restore by index if video ID not found**
      if (savedIndex != null &&
          savedIndex >= 0 &&
          savedIndex < _videos.length &&
          (savedType == null || savedType == widget.videoType)) {
        AppLogger.log('✅ Restored to index: $savedIndex');
        _currentIndex = savedIndex;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _tryAutoplayCurrent());
      }
    } catch (e) {
      AppLogger.log('❌ Error restoring background state: $e');
    }
  }

  /// **NEW: Persist seen video keys so reopened app doesn't re-show them at top**
  Future<void> _loadSeenVideoKeysFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedKeys = prefs.getStringList(_kSeenVideoKeysKey) ?? const [];
      if (storedKeys.isNotEmpty) {
        _seenVideoKeys.addAll(storedKeys);
        AppLogger.log(
          '✅ VideoFeedAdvanced: Loaded ${_seenVideoKeys.length} seen video keys from storage',
        );
      }
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Error loading seen video keys: $e');
    }
  }

  Future<void> _saveSeenVideoKeysToStorage() async {
    try {
      // Keep only a reasonable number of recent keys to avoid unbounded growth
      const maxKeys = 1000;
      final keys = _seenVideoKeys.toList();
      if (keys.length > maxKeys) {
        keys.removeRange(0, keys.length - maxKeys);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kSeenVideoKeysKey, keys);
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Error saving seen video keys: $e');
    }
  }
}
