import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:vayu/shared/models/video_model.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/shared/enums/video_state.dart';
import 'package:vayu/shared/constants/app_constants.dart';
import 'package:vayu/features/video/presentation/managers/video_controller_manager.dart';

// import 'package:hive_flutter/hive_flutter.dart';

class VideoProvider extends ChangeNotifier {
  final VideoService _videoService = VideoService();

  List<VideoModel> _videos = [];
  VideoLoadState _loadState = VideoLoadState.initial;
  int _currentPage = AppConstants.initialPage;
  bool _hasMore = true;
  String? _errorMessage;
  String? _currentVideoType; // Track current video type filter

  // Getters
  List<VideoModel> get videos => _videos;
  VideoLoadState get loadState => _loadState;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _loadState == VideoLoadState.loading;
  bool get isLoadingMore => _loadState == VideoLoadState.loadingMore;
  String? get currentVideoType => _currentVideoType;

  /// Load videos from API
  Future<void> loadVideos(
      {bool isInitialLoad = true, String? videoType}) async {
    // Prevent multiple simultaneous calls
    if (_loadState == VideoLoadState.loading ||
        _loadState == VideoLoadState.loadingMore) {

      return;
    }

    if (!_hasMore && !isInitialLoad) {

      return;
    }

    // If videoType changed, reset pagination
    if (videoType != _currentVideoType) {
      _currentVideoType = videoType;
      _currentPage = AppConstants.initialPage;
      _videos.clear();
      _hasMore = true;

    }

    // 0) **AGGRESSIVE CACHING REMOVED** - functionality replaced by AppInitializationManager in UI
    if (isInitialLoad && _videos.isEmpty) {
       // No-op
    }

    _setLoadState(
        isInitialLoad ? VideoLoadState.loading : VideoLoadState.loadingMore);

    try {
      // **OPTIMIZED: Always fetch fresh data via network**
      final result = await _videoService.getVideos(
        page: _currentPage,
        videoType: videoType,
      );

      if (result == null) {
        throw Exception('Failed to load videos');
      }

      final List<VideoModel> fetchedVideos = result['videos'] as List<VideoModel>;
      final bool hasMore = result['hasMore'] as bool? ?? false;

      if (isInitialLoad) {
        // Clear old videos and set new ones
        _videos = fetchedVideos;
        
        // Pre-initialize first video
        if (_videos.isNotEmpty) {
          try {
            final firstVideo = _videos.first;
            unawaited(
                VideoControllerManager().preloadController(0, firstVideo));
            VideoControllerManager().pinIndices({0});
          } catch (e) {}
        }
      } else {
        _videos.addAll(fetchedVideos);
      }

      _hasMore = hasMore;
      _currentPage++;
      _errorMessage = null;
      _setLoadState(VideoLoadState.loaded);

    } catch (e) {
      _errorMessage = e.toString();
      _setLoadState(VideoLoadState.error);
    }
  }

  /// **REMOVED: Stale video saving (Hive)**
  Future<void> saveStaleVideos() async {
    // No-op
  }

  /// Refresh videos (reset and reload)
  Future<void> refreshVideos() async {

    _videos.clear();
    _currentPage = AppConstants.initialPage;
    _hasMore = true;
    _errorMessage = null;
    await loadVideos(isInitialLoad: true, videoType: _currentVideoType);
  }

  /// Start over - reset pagination and reload from beginning
  /// This allows users to restart the feed after watching all videos
  Future<void> startOver() async {

    _videos.clear();
    _currentPage = AppConstants.initialPage;
    _hasMore = true;
    _errorMessage = null;
    _loadState = VideoLoadState.initial;

    await loadVideos(isInitialLoad: true, videoType: _currentVideoType);
  }

  /// Toggle like for a video
  Future<void> toggleLike(String videoId, String userId) async {
    try {
      final updatedVideo = await _videoService.toggleLike(videoId);

      // Update the video in the list
      final index = _videos.indexWhere((v) => v.id == videoId);
      if (index != -1) {
        _videos[index] = VideoModel.fromJson(updatedVideo.toJson());
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }


  /// Get video by index
  VideoModel? getVideoByIndex(int index) {
    if (index >= 0 && index < _videos.length) {
      return _videos[index];
    }
    return null;
  }

  /// Get video by ID
  VideoModel? getVideoById(String id) {
    try {
      return _videos.firstWhere((video) => video.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Update video at index
  void updateVideoAtIndex(int index, VideoModel video) {
    if (index >= 0 && index < _videos.length) {
      _videos[index] = video;
      notifyListeners();
    }
  }

  /// Delete video by ID (for real-time updates)
  Future<void> deleteVideo(String videoId) async {
    try {


      // Remove video from local list immediately for instant UI update
      final index = _videos.indexWhere((v) => v.id == videoId);
      if (index != -1) {
        _videos.removeAt(index);
        notifyListeners(); // Update UI immediately


      }

      // Call backend to delete video
      await _videoService.deleteVideo(videoId);

    } catch (e) {


      // If backend deletion failed, restore the video in the list
      await refreshVideos();


      _errorMessage = 'Failed to delete video: $e';
      notifyListeners();
    }
  }

  /// Bulk delete videos (for real-time updates)
  Future<void> bulkDeleteVideos(List<String> videoIds) async {
    try {


      // Remove videos from local list immediately for instant UI update
      final videosToRemove = <VideoModel>[];
      for (final videoId in videoIds) {
        final index = _videos.indexWhere((v) => v.id == videoId);
        if (index != -1) {
          videosToRemove.add(_videos[index]);
          _videos.removeAt(index);
        }
      }

      notifyListeners(); // Update UI immediately


      // Call backend to delete videos
      bool allDeleted = true;
      for (final videoId in videoIds) {
        try {
          final success = await _videoService.deleteVideo(videoId);
          if (!success) {
            allDeleted = false;

          }
        } catch (e) {
          allDeleted = false;

        }
      }

      if (allDeleted) {


        // Network cache is gone, no need to invalidate
      } else {
        throw Exception('Some videos failed to delete');
      }
    } catch (e) {


      // If backend deletion failed, restore the videos in the list
      await refreshVideos();


      _errorMessage = 'Failed to delete videos: $e';
      notifyListeners();
    }
  }

  /// Remove video by ID without backend call (for UI updates only)
  void removeVideoFromList(String videoId) {
    final index = _videos.indexWhere((v) => v.id == videoId);
    if (index != -1) {
      _videos.removeAt(index);
      notifyListeners();

    }
  }

  /// Remove multiple videos from list (for UI updates only)
  void removeVideosFromList(List<String> videoIds) {
    int removedCount = 0;
    for (final videoId in videoIds) {
      final index = _videos.indexWhere((v) => v.id == videoId);
      if (index != -1) {
        _videos.removeAt(index);
        removedCount++;
      }
    }
    if (removedCount > 0) {
      notifyListeners();

    }
  }

  /// Add video to list (for new uploads)
  void addVideo(VideoModel video) {
    _videos.insert(0, video); // Add at the beginning
    notifyListeners();

  }

  /// Update video in list (for edits)
  void updateVideo(VideoModel video) {
    final index = _videos.indexWhere((v) => v.id == video.id);
    if (index != -1) {
      _videos[index] = video;
      notifyListeners();

    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// **FIXED: Clear all videos and reset state on logout**
  void clearAllVideos() {

    _videos.clear();
    _currentPage = AppConstants.initialPage;
    _hasMore = true;
    _errorMessage = null;
    _loadState = VideoLoadState.initial;

    notifyListeners();
  }

  /// Filter videos by type (yug/vayu)
  Future<void> filterVideosByType(String videoType) async {
    if (videoType != 'yog' && videoType != 'vayu') {

      return;
    }


    await loadVideos(isInitialLoad: true, videoType: videoType);
  }

  /// Get yug videos only (alias for legacy yog)
  Future<void> loadYugVideos() async {
    await filterVideosByType('yog');
  }

  /// Legacy alias maintained for compatibility
  Future<void> loadYogVideos() async {
    await filterVideosByType('yog');
  }

  /// Load all videos (no filter)
  Future<void> loadAllVideos() async {

    await loadVideos(isInitialLoad: true, videoType: null);
  }



  void _setLoadState(VideoLoadState state) {
    _loadState = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _videos.clear();
    super.dispose();
  }
}
