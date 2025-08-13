import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';

/// Manages video state, pagination, and data loading
class VideoStateManager extends ChangeNotifier {
  // Video data
  List<VideoModel> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _activePage = 0;

  // Screen visibility
  bool _isScreenVisible = true;

  // Service
  final VideoService _videoService = VideoService();

  // Getters
  List<VideoModel> get videos => _videos;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  int get currentPage => _currentPage;
  int get activePage => _activePage;
  bool get isScreenVisible => _isScreenVisible;
  int get totalVideos => _videos.length;

  /// Initialize with provided videos
  void initializeWithVideos(List<VideoModel> videos, int initialIndex) {
    _videos = List<VideoModel>.from(videos);
    _activePage = initialIndex;
    _isLoading = false;
    _currentPage = 1;
    _hasMore = true;
    notifyListeners();
  }

  /// Load videos from API with pagination support
  Future<void> loadVideos({bool isInitialLoad = true}) async {
    if (!_hasMore || (_isLoadingMore && !isInitialLoad)) return;

    _setLoadingState(isInitialLoad, true);

    try {
      print(
          '🎬 VideoStateManager: Loading videos - Page: $_currentPage, Initial: $isInitialLoad');

      final stopwatch = Stopwatch()..start();
      final response = await _videoService.getVideos(page: _currentPage);
      stopwatch.stop();

      print(
          '📡 VideoStateManager: API response received in ${stopwatch.elapsedMilliseconds}ms');

      final List<VideoModel> fetchedVideos = response['videos'];
      final bool hasMore = response['hasMore'];

      print('🎥 VideoStateManager: Fetched ${fetchedVideos.length} videos');

      _videos.addAll(fetchedVideos);
      _hasMore = hasMore;
      _currentPage++;

      _setLoadingState(isInitialLoad, false);

      print('📱 VideoStateManager: Total videos now: ${_videos.length}');

      notifyListeners();
    } catch (e) {
      print("❌ VideoStateManager: Error loading videos: $e");
      _setLoadingState(isInitialLoad, false);
    }
  }

  /// Load more videos for infinite scroll
  Future<void> loadMoreVideos() async {
    if (!_hasMore || _isLoadingMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      print('🔄 VideoStateManager: Loading more videos - Page: $_currentPage');

      final response = await _videoService.getVideos(page: _currentPage);
      final List<VideoModel> fetchedVideos = response['videos'];
      final bool hasMore = response['hasMore'];

      _videos.addAll(fetchedVideos);
      _hasMore = hasMore;
      _currentPage++;
      _isLoadingMore = false;

      print(
          '✅ VideoStateManager: Loaded ${fetchedVideos.length} more videos. Total: ${_videos.length}');

      notifyListeners();
    } catch (e) {
      print('❌ VideoStateManager: Error loading more videos: $e');
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Check if we need to load more videos for infinite scroll
  void checkAndLoadMoreVideos(int currentIndex) {
    if (_hasMore && !_isLoadingMore && currentIndex >= _videos.length - 3) {
      print(
          '🔄 VideoStateManager: Triggering infinite scroll load at index $currentIndex');
      loadMoreVideos();
    }
  }

  /// Update active page
  void updateActivePage(int newPage) {
    if (newPage != _activePage && newPage >= 0 && newPage < _videos.length) {
      print(
          '🔄 VideoStateManager: Updating active page from $_activePage to $newPage');
      _activePage = newPage;
      notifyListeners();
    }
  }

  /// Update screen visibility
  void updateScreenVisibility(bool visible) {
    if (_isScreenVisible != visible) {
      print('👁️ VideoStateManager: Screen visibility changed to: $visible');
      _isScreenVisible = visible;
      notifyListeners();
    }
  }

  /// Refresh videos
  Future<void> refreshVideos() async {
    print('🔄 VideoStateManager: Refreshing videos');

    _videos.clear();
    _currentPage = 1;
    _hasMore = true;
    _isLoading = true;
    _activePage = 0;

    notifyListeners();

    await loadVideos(isInitialLoad: true);
  }

  /// Update video like status
  void updateVideoLike(int index, String userId) {
    if (index >= 0 && index < _videos.length) {
      final video = _videos[index];
      final isCurrentlyLiked = video.likedBy.contains(userId);

      if (isCurrentlyLiked) {
        video.likedBy.remove(userId);
        video.likes--;
      } else {
        video.likedBy.add(userId);
        video.likes++;
      }

      notifyListeners();
    }
  }

  /// Update video comments
  void updateVideoComments(int index, List<Comment> comments) {
    if (index >= 0 && index < _videos.length) {
      _videos[index].comments = comments;
      notifyListeners();
    }
  }

  /// Get current video
  VideoModel? getCurrentVideo() {
    if (_videos.isNotEmpty && _activePage < _videos.length) {
      return _videos[_activePage];
    }
    return null;
  }

  /// Get video at specific index
  VideoModel? getVideoAt(int index) {
    if (index >= 0 && index < _videos.length) {
      return _videos[index];
    }
    return null;
  }

  /// Check if video has external link
  bool hasExternalLink(int index) {
    final video = getVideoAt(index);
    return video?.link != null && video!.link!.isNotEmpty;
  }

  /// Set loading state
  void _setLoadingState(bool isInitialLoad, bool loading) {
    if (isInitialLoad) {
      _isLoading = loading;
    } else {
      _isLoadingMore = loading;
    }
    notifyListeners();
  }

  /// Reset state
  void reset() {
    _videos.clear();
    _isLoading = true;
    _isLoadingMore = false;
    _hasMore = true;
    _currentPage = 1;
    _activePage = 0;
    _isScreenVisible = true;
    notifyListeners();
  }

  /// Dispose
  @override
  void dispose() {
    _videos.clear();
    super.dispose();
  }
}
