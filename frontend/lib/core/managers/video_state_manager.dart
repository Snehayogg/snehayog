import 'package:flutter/foundation.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

/// **VideoStateManager - Handles all video state management logic**
/// Separated from VideoScreen for better maintainability
class VideoStateManager extends ChangeNotifier {
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();

  // **Video state management**
  List<VideoModel> _videos = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _hasMore = true;
  int _page = 1;
  final int _limit = 10;

  // **Loading states**
  bool _isInitializingVideo = false;
  bool _isPreloadingVideos = false;
  String _loadingMessage = 'Loading videos...';
  double _loadingProgress = 0.0;

  // **Getters**
  List<VideoModel> get videos => List.unmodifiable(_videos);
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get hasMore => _hasMore;
  int get page => _page;
  int get limit => _limit;
  bool get isInitializingVideo => _isInitializingVideo;
  bool get isPreloadingVideos => _isPreloadingVideos;
  String get loadingMessage => _loadingMessage;
  double get loadingProgress => _loadingProgress;

  /// **Set videos**
  void setVideos(List<VideoModel> videos) {
    _videos = List.from(videos);
    notifyListeners();
  }

  /// **Add videos (for pagination)**
  void addVideos(List<VideoModel> newVideos) {
    _videos.addAll(newVideos);
    notifyListeners();
  }

  /// **Set current index**
  void setCurrentIndex(int index) {
    if (index >= 0 && index < _videos.length) {
      _currentIndex = index;
      notifyListeners();
    }
  }

  /// **Set loading state**
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// **Set refreshing state**
  void setRefreshing(bool refreshing) {
    _isRefreshing = refreshing;
    notifyListeners();
  }

  /// **Set has more flag**
  void setHasMore(bool hasMore) {
    _hasMore = hasMore;
    notifyListeners();
  }

  /// **Set page number**
  void setPage(int page) {
    _page = page;
    notifyListeners();
  }

  /// **Increment page**
  void incrementPage() {
    _page++;
    notifyListeners();
  }

  /// **Set video initialization state**
  void setVideoInitializing(bool initializing) {
    _isInitializingVideo = initializing;
    notifyListeners();
  }

  /// **Set preloading state**
  void setPreloading(bool preloading) {
    _isPreloadingVideos = preloading;
    notifyListeners();
  }

  /// **Update loading progress**
  void updateLoadingProgress(String message, double progress) {
    _loadingMessage = message;
    _loadingProgress = progress.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// **Handle like functionality**
  Future<void> handleLike(int index) async {
    if (index < 0 || index >= _videos.length || _videos.isEmpty) {
      print('⚠️ VideoStateManager: Invalid index for like handling: $index');
      return;
    }

    try {
      final video = _videos[index];
      final userData = await _authService.getUserData();

      // **FIXED: Backend expects googleId as userId**
      String? userId =
          userData?['googleId'] ?? userData?['id'] ?? userData?['_id'];

      if (userId == null) {
        throw Exception('Please sign in to like videos');
      }

      print(
          '🔍 VideoStateManager: Handling like for video $index, user: $userId');

      // Optimistic update
      _updateVideoLikeState(index, userId, true);

      // API call with proper error handling
      try {
        await _videoService.toggleLike(video.id);
        print('✅ VideoStateManager: Like toggled successfully');
      } catch (apiError) {
        print('❌ VideoStateManager: API error in like toggle: $apiError');

        // Revert optimistic update on API failure
        _updateVideoLikeState(index, userId, false);
        rethrow;
      }
    } catch (e) {
      print('❌ VideoStateManager: Error handling like: $e');
      rethrow;
    }
  }

  /// **Update video like state (optimistic update)**
  void _updateVideoLikeState(int index, String userId, bool isAdding) {
    if (index < 0 || index >= _videos.length) return;

    final video = _videos[index];
    if (isAdding) {
      if (!video.likedBy.contains(userId)) {
        video.likedBy.add(userId);
        video.likes++;
      }
    } else {
      if (video.likedBy.contains(userId)) {
        video.likedBy.remove(userId);
        video.likes = (video.likes - 1).clamp(0, double.infinity).toInt();
      }
    }
    notifyListeners(); // **CRITICAL: Notify listeners to update UI**
  }

  /// **Handle comment functionality**
  void handleComment(VideoModel video) {
    // Show comments sheet or navigate to comments screen
    print(
        '💬 VideoStateManager: Comment requested for video: ${video.videoName}');
  }

  /// **Handle share functionality**
  Future<void> handleShare(VideoModel video) async {
    try {
      print(
          '📤 VideoStateManager: Share requested for video: ${video.videoName}');

      // Create deep link URLs
      final deepLinkUrl = 'snehayog://video?id=${video.id}';
      final webFallbackUrl = 'https://snehayog.app/video/${video.id}';

      // Create share text with video information
      final shareText = '''
🎬 Check out this video on Snehayog!

📹 ${video.videoName}
👤 by ${video.uploader.name}

${video.description?.isNotEmpty == true ? '📝 ${video.description}' : ''}

🔗 Watch on Snehayog: $deepLinkUrl
🌐 Web version: $webFallbackUrl

#Snehayog #Video #${video.uploader.name.replaceAll(' ', '')}
''';

      // Share the video
      await Share.share(
        shareText,
        subject: '${video.videoName} - Snehayog Video',
      );

      print(
          '✅ VideoStateManager: Video shared successfully with deep link: $deepLinkUrl');
    } catch (e) {
      print('❌ VideoStateManager: Error sharing video: $e');
      rethrow;
    }
  }

  /// **Handle profile tap**
  void handleProfileTap(VideoModel video) {
    print('👤 VideoStateManager: Profile tap for user: ${video.uploader.name}');
  }

  /// **Handle visit now button**
  void handleVisitNow(VideoModel video) async {
    final raw = (video.link ?? '').trim();
    if (raw.isEmpty) {
      print('🔗 VideoStateManager: No link available for ${video.videoName}');
      return;
    }

    final urlStr = raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : 'https://$raw';
    final uri = Uri.tryParse(urlStr);
    if (uri == null) {
      print('❌ VideoStateManager: Invalid URL: $raw');
      return;
    }
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        print('❌ VideoStateManager: Failed to launch $uri');
      }
    } catch (e) {
      print('❌ VideoStateManager: Error launching $uri: $e');
    }
  }

  /// **Get video by index**
  VideoModel? getVideoByIndex(int index) {
    if (index >= 0 && index < _videos.length) {
      return _videos[index];
    }
    return null;
  }

  /// **Get current video**
  VideoModel? get currentVideo {
    if (_currentIndex >= 0 && _currentIndex < _videos.length) {
      return _videos[_currentIndex];
    }
    return null;
  }

  /// **Check if index is valid**
  bool isValidIndex(int index) {
    return index >= 0 && index < _videos.length;
  }

  /// **Get video count**
  int get videoCount => _videos.length;

  /// **Check if videos list is empty**
  bool get isEmpty => _videos.isEmpty;

  /// **Get state statistics**
  Map<String, dynamic> getStateStats() {
    return {
      'totalVideos': _videos.length,
      'currentIndex': _currentIndex,
      'isLoading': _isLoading,
      'isRefreshing': _isRefreshing,
      'hasMore': _hasMore,
      'page': _page,
      'isInitializingVideo': _isInitializingVideo,
      'isPreloadingVideos': _isPreloadingVideos,
      'loadingProgress': _loadingProgress,
      'loadingMessage': _loadingMessage,
    };
  }

  /// **Clear all state**
  void clearState() {
    _videos.clear();
    _currentIndex = 0;
    _isLoading = true;
    _isRefreshing = false;
    _hasMore = true;
    _page = 1;
    _isInitializingVideo = false;
    _isPreloadingVideos = false;
    _loadingMessage = 'Loading videos...';
    _loadingProgress = 0.0;
    print('🗑️ VideoStateManager: State cleared');
  }
}
