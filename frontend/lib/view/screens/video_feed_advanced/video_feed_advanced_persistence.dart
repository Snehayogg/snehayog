part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedPersistence on _VideoFeedAdvancedState {
  Future<void> _saveBackgroundState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSavedFeedIndexKey, _currentIndex);
      if (widget.videoType != null) {
        await prefs.setString(_kSavedFeedTypeKey, widget.videoType!);
      }
    } catch (_) {}
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

      if (savedIndex != null &&
          savedIndex >= 0 &&
          savedIndex < _videos.length &&
          (savedType == null || savedType == widget.videoType)) {
        _currentIndex = savedIndex;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _tryAutoplayCurrent());
      }
    } catch (_) {}
  }
}
