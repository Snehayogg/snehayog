import 'package:flutter/foundation.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/core/enums/video_state.dart';
import 'package:snehayog/core/constants/app_constants.dart';

class VideoProvider extends ChangeNotifier {
  final VideoService _videoService = VideoService();

  List<VideoModel> _videos = [];
  VideoLoadState _loadState = VideoLoadState.initial;
  int _currentPage = AppConstants.initialPage;
  bool _hasMore = true;
  String? _errorMessage;

  // Getters
  List<VideoModel> get videos => _videos;
  VideoLoadState get loadState => _loadState;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _loadState == VideoLoadState.loading;
  bool get isLoadingMore => _loadState == VideoLoadState.loadingMore;

  /// Load videos from API
  Future<void> loadVideos({bool isInitialLoad = true}) async {
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

    _setLoadState(
        isInitialLoad ? VideoLoadState.loading : VideoLoadState.loadingMore);

    try {
      print('🔄 VideoProvider: Loading videos, page: $_currentPage');
      final response = await _videoService.getVideos(page: _currentPage);
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
    _videos.clear();
    _currentPage = AppConstants.initialPage;
    _hasMore = true;
    _errorMessage = null;
    await loadVideos(isInitialLoad: true);
  }

  /// Toggle like for a video
  Future<void> toggleLike(String videoId, String userId) async {
    try {
      final updatedVideo = await _videoService.toggleLike(videoId, userId);

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
      await _videoService.deleteVideos(videoIds);
      print('✅ VideoProvider: Videos deleted from backend successfully');
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
