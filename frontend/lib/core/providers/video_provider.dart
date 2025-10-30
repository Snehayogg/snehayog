import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/core/enums/video_state.dart';
import 'package:vayu/core/constants/app_constants.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';
import 'package:vayu/core/managers/video_controller_manager.dart';

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
      print('⚠️ VideoProvider: Already loading videos, skipping request');
      return;
    }

    if (!_hasMore && !isInitialLoad) {
      print('⚠️ VideoProvider: No more videos to load');
      return;
    }

    // If videoType changed, reset pagination
    if (videoType != _currentVideoType) {
      _currentVideoType = videoType;
      _currentPage = AppConstants.initialPage;
      _videos.clear();
      _hasMore = true;
      print(
          '🔄 VideoProvider: VideoType changed to $videoType, resetting pagination');
    }

    _setLoadState(
        isInitialLoad ? VideoLoadState.loading : VideoLoadState.loadingMore);

    try {
      print(
          '🔄 VideoProvider: Loading videos, page: $_currentPage, videoType: $videoType');

      // 1) Try instant render from SmartCacheManager (cache-first on initial load)
      if (isInitialLoad) {
        try {
          final smartCache = SmartCacheManager();
          if (!smartCache.isInitialized) {
            await smartCache.initialize();
          }

          // Normalize yug->yog to match splash prefetch cache key
          final normalizedType =
              (videoType == 'yug') ? 'yog' : (videoType ?? 'yog');
          final cacheKey = 'videos_page_1_$normalizedType';

          final cached = await smartCache.get<Map<String, dynamic>>(
            cacheKey,
            // Do not fetch here; only return if present for instant UI
            fetchFn: () async => throw Exception('cache-only read'),
            cacheType: 'videos',
            maxAge: const Duration(minutes: 15),
            forceRefresh: false,
          );

          if (cached != null) {
            final List<VideoModel> cachedVideos =
                (cached['videos'] as List<dynamic>).cast<VideoModel>();
            if (cachedVideos.isNotEmpty) {
              print(
                  '⚡ VideoProvider: Instant render from cache: ${cachedVideos.length} videos');
              _videos = cachedVideos;
              _hasMore = cached['hasMore'] ?? true;
              notifyListeners();
              // Pre-create first controller for zero-wait playback
              try {
                final firstVideo = _videos.first;
                unawaited(
                    VideoControllerManager().preloadController(0, firstVideo));
                VideoControllerManager().pinIndices({0});
                print(
                    '🚀 VideoProvider: Precreating first VideoPlayerController');
              } catch (e) {
                print(
                    '⚠️ VideoProvider: Failed to precreate first controller: $e');
              }
              // Keep loadState as loading while fresh data fetches below
            }
          }
        } catch (e) {
          print(
              '⚠️ VideoProvider: Cache-first read failed (continuing with network): $e');
        }
      }

      // 2) Network fetch for fresh data
      final response = await _videoService.getVideos(
          page: _currentPage, videoType: videoType);
      final List<VideoModel> fetchedVideos = response['videos'];
      final bool hasMore = response['hasMore'];

      if (isInitialLoad) {
        _videos = fetchedVideos;
      } else {
        _videos.addAll(fetchedVideos);
      }

      _hasMore = hasMore;
      _currentPage++;
      _errorMessage = null;
      _setLoadState(VideoLoadState.loaded);
      print(
          '✅ VideoProvider: Successfully loaded ${fetchedVideos.length} videos');
    } catch (e) {
      print('❌ VideoProvider: Error loading videos: $e');
      _errorMessage = e.toString();
      _setLoadState(VideoLoadState.error);
    }
  }

  /// Refresh videos (reset and reload)
  Future<void> refreshVideos() async {
    print('🔄 VideoProvider: Refreshing videos from server...');
    _videos.clear();
    _currentPage = AppConstants.initialPage;
    _hasMore = true;
    _errorMessage = null;
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

  /// Add comment to a video
  Future<void> addComment(String videoId, String comment, String userId) async {
    try {
      final updatedComments =
          await _videoService.addComment(videoId, comment, userId);

      // Update the video in the list
      final index = _videos.indexWhere((v) => v.id == videoId);
      if (index != -1) {
        _videos[index].comments = updatedComments;
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
      print('🗑️ VideoProvider: Deleting video: $videoId');

      // Remove video from local list immediately for instant UI update
      final index = _videos.indexWhere((v) => v.id == videoId);
      if (index != -1) {
        _videos.removeAt(index);
        notifyListeners(); // Update UI immediately

        print('✅ VideoProvider: Video removed from local list, UI updated');
      }

      // Call backend to delete video
      await _videoService.deleteVideo(videoId);
      print('✅ VideoProvider: Video deleted from backend successfully');
    } catch (e) {
      print('❌ VideoProvider: Error deleting video: $e');

      // If backend deletion failed, restore the video in the list
      await refreshVideos();
      print('🔄 VideoProvider: Restored video list after deletion failure');

      _errorMessage = 'Failed to delete video: $e';
      notifyListeners();
    }
  }

  /// Bulk delete videos (for real-time updates)
  Future<void> bulkDeleteVideos(List<String> videoIds) async {
    try {
      print('🗑️ VideoProvider: Bulk deleting ${videoIds.length} videos');

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
      print('✅ VideoProvider: Videos removed from local list, UI updated');

      // Call backend to delete videos
      bool allDeleted = true;
      for (final videoId in videoIds) {
        try {
          final success = await _videoService.deleteVideo(videoId);
          if (!success) {
            allDeleted = false;
            print('❌ VideoProvider: Failed to delete video: $videoId');
          }
        } catch (e) {
          allDeleted = false;
          print('❌ VideoProvider: Error deleting video $videoId: $e');
        }
      }

      if (allDeleted) {
        print('✅ VideoProvider: Videos deleted from backend successfully');

        // **NEW: Invalidate SmartCacheManager cache to prevent deleted videos from showing**
        try {
          final cacheManager = SmartCacheManager();
          await cacheManager.invalidateVideoCache(videoType: _currentVideoType);
          print('🗑️ VideoProvider: Invalidated video cache after deletion');
        } catch (e) {
          print('⚠️ VideoProvider: Failed to invalidate cache: $e');
        }
      } else {
        throw Exception('Some videos failed to delete');
      }
    } catch (e) {
      print('❌ VideoProvider: Error bulk deleting videos: $e');

      // If backend deletion failed, restore the videos in the list
      await refreshVideos();
      print(
          '🔄 VideoProvider: Restored video list after bulk deletion failure');

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
      print('✅ VideoProvider: Video removed from list: $videoId');
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
      print('✅ VideoProvider: Removed $removedCount videos from list');
    }
  }

  /// Add video to list (for new uploads)
  void addVideo(VideoModel video) {
    _videos.insert(0, video); // Add at the beginning
    notifyListeners();
    print('✅ VideoProvider: Video added to list: ${video.videoName}');
  }

  /// Update video in list (for edits)
  void updateVideo(VideoModel video) {
    final index = _videos.indexWhere((v) => v.id == video.id);
    if (index != -1) {
      _videos[index] = video;
      notifyListeners();
      print('✅ VideoProvider: Video updated in list: ${video.videoName}');
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// **FIXED: Clear all videos and reset state on logout**
  void clearAllVideos() {
    print('🗑️ VideoProvider: Clearing all videos and resetting state...');
    _videos.clear();
    _currentPage = AppConstants.initialPage;
    _hasMore = true;
    _errorMessage = null;
    _loadState = VideoLoadState.initial;
    print('✅ VideoProvider: All videos cleared and state reset');
    notifyListeners();
  }

  /// Filter videos by type (yug/yog or sneha)
  Future<void> filterVideosByType(String videoType) async {
    // Accept 'yug' as app label; backend mapping handled by VideoService
    if (videoType != 'yug' && videoType != 'yog' && videoType != 'sneha') {
      print('⚠️ VideoProvider: Invalid videoType: $videoType');
      return;
    }

    print('🔍 VideoProvider: Filtering videos by type: $videoType');
    await loadVideos(isInitialLoad: true, videoType: videoType);
  }

  /// Get yug videos only (alias for legacy yog)
  Future<void> loadYugVideos() async {
    await filterVideosByType('yug');
  }

  /// Legacy alias maintained for compatibility
  Future<void> loadYogVideos() async {
    await filterVideosByType('yug');
  }

  /// Load all videos (no filter)
  Future<void> loadAllVideos() async {
    print('🔍 VideoProvider: Loading all videos (no filter)');
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
