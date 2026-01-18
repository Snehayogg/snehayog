import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/core/enums/video_state.dart';
import 'package:vayu/core/constants/app_constants.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';
import 'package:vayu/core/managers/video_controller_manager.dart';
import 'package:vayu/services/platform_id_service.dart';

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
      // 1) Try instant render from SmartCacheManager (cache-first on initial load)
      final smartCache = SmartCacheManager();
      if (!smartCache.isInitialized) {
        await smartCache.initialize();
      }

      // **FIX: Include platformId in cache key for personalized feeds**
      // This ensures each user gets their own cached personalized feed
      final platformIdService = PlatformIdService();
      final platformId = await platformIdService.getPlatformId();
      final normalizedType = (videoType ?? 'all').toLowerCase();
      final cacheKey =
          'videos_page_${_currentPage}_${normalizedType}_$platformId';

      bool cachedMarkedAsEnd = false;

      // Note: SmartCacheManager is Memory-Only now, so it won't help on restart.
      // We rely on the Hive block above for restart caching.
      
      if (isInitialLoad) {
          // ... (Existing SmartCacheManager logic kept for in-session navigation) ...
        try {
          final cached = await smartCache.peek<Map<String, dynamic>>(
            cacheKey,
            cacheType: 'videos',
          );

          if (cached != null) {
             // ... existing logic ...
            final cachedVideos = _deserializeVideoList(cached['videos']);
            if (cachedVideos.isNotEmpty) {
              _videos = cachedVideos;
              final cachedHasMore = cached['hasMore'] as bool? ?? true;
              cachedMarkedAsEnd = !cachedHasMore;
              _hasMore = cachedHasMore;
              notifyListeners();
             
              try {
                final firstVideo = _videos.first;
                unawaited(
                    VideoControllerManager().preloadController(0, firstVideo));
                VideoControllerManager().pinIndices({0});
              } catch (e) {}
            }
          }
        } catch (e) {}
      }

      // 2) Network fetch for fresh data
      final response = await smartCache.get<Map<String, dynamic>>(
        cacheKey,
        cacheType: 'videos',
        maxAge: const Duration(minutes: 15),
        forceRefresh: !isInitialLoad || cachedMarkedAsEnd, // Removed forceRefresh on initial if we want cache, but standard logic
        fetchFn: () async {
          final result = await _videoService.getVideos(
            page: _currentPage,
            videoType: videoType,
          );

          final videos = (result['videos'] as List<VideoModel>)
              .map((video) => video.toJson())
              .toList();

          return {
            ...result,
            'videos': videos,
          };
        },
      );

      if (response == null) {
        throw Exception('Failed to load videos');
      }

      final fetchedVideos = _deserializeVideoList(response['videos']);
      final bool hasMore = response['hasMore'] as bool? ?? false;

      if (isInitialLoad) {
        // Replace stale videos with fresh ones
        _videos = fetchedVideos;
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

    // Invalidate cache to get fresh videos
    try {
      final cacheManager = SmartCacheManager();
      await cacheManager.invalidateVideoCache(videoType: _currentVideoType);

    } catch (e) {

    }

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


        // **NEW: Invalidate SmartCacheManager cache to prevent deleted videos from showing**
        try {
          final cacheManager = SmartCacheManager();
          await cacheManager.invalidateVideoCache(videoType: _currentVideoType);

        } catch (e) {

        }
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

  List<VideoModel> _deserializeVideoList(dynamic rawVideos) {
    if (rawVideos == null) {
      return <VideoModel>[];
    }

    if (rawVideos is List<VideoModel>) {
      return rawVideos;
    }

    if (rawVideos is List) {
      final parsedVideos = <VideoModel>[];

      for (final item in rawVideos) {
        if (item is VideoModel) {
          parsedVideos.add(item);
        } else if (item is Map<String, dynamic>) {
          try {
            parsedVideos.add(VideoModel.fromJson(item));
          } catch (e) {

          }
        } else if (item is Map) {
          try {
            parsedVideos
                .add(VideoModel.fromJson(Map<String, dynamic>.from(item)));
          } catch (e) {

          }
        }
      }

      return parsedVideos;
    }

    return <VideoModel>[];
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
