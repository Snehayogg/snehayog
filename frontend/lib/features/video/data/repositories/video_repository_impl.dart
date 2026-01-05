import 'dart:io';
import '../datasources/video_remote_datasource.dart';
import '../../domain/repositories/video_repository.dart';
import '../../domain/entities/video_entity.dart';
import '../../../../model/video_model.dart';
// import '../models/comment_model.dart'; // Not needed - we only work with entities

/// Implementation of the VideoRepository interface
/// This class coordinates between different data sources
class VideoRepositoryImpl implements VideoRepository {
  final VideoRemoteDataSource _remoteDataSource;

  VideoRepositoryImpl({VideoRemoteDataSource? remoteDataSource})
      : _remoteDataSource = remoteDataSource ?? VideoRemoteDataSource();

  @override
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int limit = 10,
    bool clearSession = false,
  }) async {
    try {
      final result = await _remoteDataSource.getVideos(
        page: page,
        limit: limit,
        clearSession: clearSession,
      );

      // Convert VideoModel to VideoEntity
      final videos = (result['videos'] as List<dynamic>)
          .cast<VideoModel>()
          .map((model) => VideoEntity(
                id: model.id,
                title: model.videoName,
                description: model.description ?? '',
                videoUrl: model.videoUrl,
                thumbnailUrl: model.thumbnailUrl,
                originalVideoUrl: model.videoUrl,
                uploaderId: model.uploader.id,
                uploaderName: model.uploader.name,
                uploadTime: model.uploadedAt,
                views: model.views,
                likes: model.likes,
                shares: model.shares,
                comments: model.comments
                    .map((c) => CommentEntity(
                          id: c.id,
                          text: c.text,
                          userId: c.userId,
                          userName: c.userName,
                          createdAt: c.createdAt,
                        ))
                    .toList(),
                videoType: model.videoType,
                link: model.link,
                isLongVideo: model.videoType == 'yog',
              ))
          .toList();

      return {
        'videos': videos,
        'hasMore': result['hasMore'] ?? false,
      };
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<VideoEntity> getVideoById(String id) async {
    try {
      final videoModel = await _remoteDataSource.getVideoById(id);
      return VideoEntity(
        id: videoModel.id,
        title: videoModel.videoName,
        description: videoModel.description ?? '',
        videoUrl: videoModel.videoUrl,
        thumbnailUrl: videoModel.thumbnailUrl,
        originalVideoUrl: videoModel.videoUrl,
        uploaderId: videoModel.uploader.id,
        uploaderName: videoModel.uploader.name,
        uploadTime: videoModel.uploadedAt,
        views: videoModel.views,
        likes: videoModel.likes,
        shares: videoModel.shares,
        comments: videoModel.comments
            .map((c) => CommentEntity(
                  id: c.id,
                  text: c.text,
                  userId: c.userId,
                  userName: c.userName,
                  createdAt: c.createdAt,
                ))
            .toList(),
        videoType: videoModel.videoType,
        link: videoModel.link,
        isLongVideo: videoModel.videoType == 'yug',
      );
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<VideoEntity>> getUserVideos(String userId) async {
    try {
      final videoModels = await _remoteDataSource.getUserVideos(userId);
      return videoModels
          .map((model) => VideoEntity(
                id: model.id,
                title: model.videoName,
                description: model.description ?? '',
                videoUrl: model.videoUrl,
                thumbnailUrl: model.thumbnailUrl,
                originalVideoUrl: model.videoUrl,
                uploaderId: model.uploader.id,
                uploaderName: model.uploader.name,
                uploadTime: model.uploadedAt,
                views: model.views,
                likes: model.likes,
                shares: model.shares,
                comments: model.comments
                    .map((c) => CommentEntity(
                          id: c.id,
                          text: c.text,
                          userId: c.userId,
                          userName: c.userName,
                          createdAt: c.createdAt,
                        ))
                    .toList(),
                videoType: model.videoType,
                link: model.link,
                isLongVideo: model.videoType == 'yog',
              ))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> uploadVideo({
    required String videoPath,
    required String title,
    required String description,
    String? link,
    Function(double)? onProgress,
  }) async {
    try {
      return await _remoteDataSource.uploadVideo(
        videoPath: videoPath,
        title: title,
        description: description,
        link: link,
        onProgress: onProgress,
      );
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<VideoEntity> toggleLike(String videoId, String userId) async {
    try {
      final videoModel = await _remoteDataSource.toggleLike(videoId, userId);
      return VideoEntity(
        id: videoModel.id,
        title: videoModel.videoName,
        description: videoModel.description ?? '',
        videoUrl: videoModel.videoUrl,
        thumbnailUrl: videoModel.thumbnailUrl,
        originalVideoUrl: videoModel.videoUrl,
        uploaderId: videoModel.uploader.id,
        uploaderName: videoModel.uploader.name,
        uploadTime: videoModel.uploadedAt,
        views: videoModel.views,
        likes: videoModel.likes,
        shares: videoModel.shares,
        comments: videoModel.comments
            .map((c) => CommentEntity(
                  id: c.id,
                  text: c.text,
                  userId: c.userId,
                  userName: c.userName,
                  createdAt: c.createdAt,
                ))
            .toList(),
        videoType: videoModel.videoType,
        link: videoModel.link,
        isLongVideo: videoModel.videoType == 'yug',
      );
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<CommentEntity>> addComment({
    required String videoId,
    required String text,
    required String userId,
  }) async {
    try {
      final commentModels = await _remoteDataSource.addComment(
        videoId: videoId,
        text: text,
        userId: userId,
      );
      return commentModels.map((model) => model.toEntity()).toList();
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<VideoEntity> shareVideo({
    required String videoId,
    required String videoUrl,
    required String description,
  }) async {
    try {
      // For now, we'll return a mock response since the share functionality
      // might need to be implemented differently
      throw UnimplementedError('Share functionality not yet implemented');
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<bool> deleteVideo(String videoId) async {
    try {
      // This would need to be implemented in the remote data source
      throw UnimplementedError('Delete functionality not yet implemented');
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<bool> checkServerHealth() async {
    try {
      return await _remoteDataSource.checkServerHealth();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> isLongVideo(String videoPath) async {
    try {
      // This would need to be implemented as a public method in the data source
      // For now, we'll use a simple file size check as a fallback
      final file = File(videoPath);
      if (await file.exists()) {
        // Assume videos larger than 50MB are long videos
        final size = await file.length();
        return size > 50 * 1024 * 1024;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
