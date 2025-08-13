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
    if (!_hasMore || (isLoadingMore && !isInitialLoad)) return;

    _setLoadState(
        isInitialLoad ? VideoLoadState.loading : VideoLoadState.loadingMore);

    try {
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
    } catch (e) {
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
