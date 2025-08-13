import 'package:flutter/foundation.dart';
import '../../domain/entities/video_entity.dart';
import '../../domain/repositories/video_repository.dart';
import '../../domain/usecases/get_videos_usecase.dart';
import '../../domain/usecases/upload_video_usecase.dart';
import '../../../../core/exceptions/app_exceptions.dart';

/// Provider for managing video state and operations
/// This follows the ValueNotifier pattern for efficient state management
class VideoProvider extends ChangeNotifier {
  final GetVideosUseCase _getVideosUseCase;
  final UploadVideoUseCase _uploadVideoUseCase;

  VideoProvider({
    required VideoRepository repository,
  }) : _getVideosUseCase = GetVideosUseCase(repository),
       _uploadVideoUseCase = UploadVideoUseCase(repository);

  // State variables
  List<VideoEntity> _videos = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _error;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  // Getters
  List<VideoEntity> get videos => _videos;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  bool get isUploading => _isUploading;
  double get uploadProgress => _uploadProgress;
  String? get error => _error;

  /// Loads the initial set of videos
  Future<void> loadVideos({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _videos.clear();
      _hasMore = true;
    }

    if (_isLoading || !_hasMore) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final result = await _getVideosUseCase.execute(
        page: _currentPage,
        limit: 10,
      );

      final newVideos = result['videos'] as List<VideoEntity>;
      _hasMore = result['hasMore'] as bool;

      if (refresh) {
        _videos = newVideos;
      } else {
        _videos.addAll(newVideos);
      }

      _currentPage++;
    } catch (e) {
      _error = _getErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads more videos (pagination)
  Future<void> loadMoreVideos() async {
    await loadVideos();
  }

  /// Refreshes the video list
  Future<void> refreshVideos() async {
    await loadVideos(refresh: true);
  }

  /// Uploads a new video
  Future<bool> uploadVideo({
    required String videoPath,
    required String title,
    required String description,
    String? link,
  }) async {
    try {
      _isUploading = true;
      _uploadProgress = 0.0;
      _error = null;
      notifyListeners();

      final result = await _uploadVideoUseCase.execute(
        videoPath: videoPath,
        title: title,
        description: description,
        link: link,
        onProgress: (progress) {
          _uploadProgress = progress;
          notifyListeners();
        },
      );

      // Add the new video to the beginning of the list
      final newVideo = VideoEntity(
        id: result['id'],
        title: result['title'],
        description: result['description'],
        videoUrl: result['videoUrl'],
        thumbnailUrl: result['thumbnail'],
        originalVideoUrl: result['originalVideoUrl'],
        uploaderId: 'current_user', // This should come from auth
        uploaderName: result['uploader'],
        uploadTime: DateTime.now(),
        views: result['views'],
        likes: 0,
        shares: 0,
        comments: [],
        videoType: result['isLongVideo'] ? 'yog' : 'sneha',
        link: result['link'],
        isLongVideo: result['isLongVideo'],
      );

      _videos.insert(0, newVideo);
      
      return true;
    } catch (e) {
      _error = _getErrorMessage(e);
      return false;
    } finally {
      _isUploading = false;
      _uploadProgress = 0.0;
      notifyListeners();
    }
  }

  /// Toggles the like status of a video
  Future<void> toggleLike(String videoId, String userId) async {
    try {
      // Find the video in the list
      final videoIndex = _videos.indexWhere((video) => video.id == videoId);
      if (videoIndex == -1) return;

      final video = _videos[videoIndex];
      
      // Optimistically update the UI
      final updatedVideo = video.copyWith(
        likes: video.likes + 1, // This is a simplified approach
      );
      
      _videos[videoIndex] = updatedVideo;
      notifyListeners();

      // TODO: Implement actual like toggle through repository
      // For now, we'll just update the UI optimistically
    } catch (e) {
      _error = _getErrorMessage(e);
      notifyListeners();
    }
  }

  /// Adds a comment to a video
  Future<void> addComment({
    required String videoId,
    required String text,
    required String userId,
  }) async {
    try {
      // Find the video in the list
      final videoIndex = _videos.indexWhere((video) => video.id == videoId);
      if (videoIndex == -1) return;

      final video = _videos[videoIndex];
      
      // Create a new comment
      final newComment = CommentEntity(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        userId: userId,
        userName: 'Current User', // This should come from auth
        createdAt: DateTime.now(),
      );

      // Update the video with the new comment
      final updatedVideo = video.copyWith(
        comments: [...video.comments, newComment],
      );
      
      _videos[videoIndex] = updatedVideo;
      notifyListeners();

      // TODO: Implement actual comment addition through repository
      // For now, we'll just update the UI optimistically
    } catch (e) {
      _error = _getErrorMessage(e);
      notifyListeners();
    }
  }

  /// Clears any error messages
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Gets a user-friendly error message
  String _getErrorMessage(dynamic error) {
    if (error is AppException) {
      return error.message;
    } else if (error is Exception) {
      return error.toString();
    } else {
      return 'An unexpected error occurred';
    }
  }

  /// Disposes the provider
  @override
  void dispose() {
    super.dispose();
  }
}
