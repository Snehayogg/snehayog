import 'dart:io';
import '../repositories/video_repository.dart';
import '../../../../core/exceptions/app_exceptions.dart';
import '../../../../core/network/network_helper.dart';

/// Use case for uploading videos
/// This encapsulates the business logic for video uploads
class UploadVideoUseCase {
  final VideoRepository _repository;

  const UploadVideoUseCase(this._repository);

  /// Executes the use case to upload a video
  /// 
  /// Parameters:
  /// - videoPath: The local path to the video file
  /// - title: The title of the video
  /// - description: The description of the video
  /// - link: Optional link associated with the video
  /// - onProgress: Optional callback for upload progress
  /// 
  /// Returns:
  /// - A map containing the uploaded video's data
  /// - Throws [AppException] if the operation fails
  Future<Map<String, dynamic>> execute({
    required String videoPath,
    required String title,
    required String description,
    String? link,
    Function(double)? onProgress,
  }) async {
    // Validate input parameters
    _validateInputs(videoPath, title, description);
    
    // Check if video file exists
    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      throw const FileException('Video file not found');
    }

    // Check file size
    final fileSize = await videoFile.length();
    if (fileSize > NetworkHelper.maxVideoFileSize) {
      throw FileSizeException(
        'File too large. Maximum size is ${NetworkHelper.formatFileSize(NetworkHelper.maxVideoFileSize)}',
        details: {'fileSize': fileSize, 'maxSize': NetworkHelper.maxVideoFileSize},
      );
    }

    // Check file extension
    final extension = videoPath.split('.').last.toLowerCase();
    if (!NetworkHelper.isValidVideoExtension(extension)) {
      throw FileTypeException(
        'Invalid file type. Please upload a video file (${NetworkHelper.validVideoExtensions.join(', ')})',
        details: {'extension': extension},
      );
    }

    // Validate title and description
    if (title.trim().isEmpty) {
      throw const ValidationException('Video title cannot be empty');
    }
    
    if (title.length > 100) {
      throw const ValidationException('Video title cannot exceed 100 characters');
    }
    
    if (description.length > 500) {
      throw const ValidationException('Video description cannot exceed 500 characters');
    }

    // Check server health before upload
    final isHealthy = await _repository.checkServerHealth();
    if (!isHealthy) {
      throw const ServerException(
        'Server is not responding. Please check your connection and try again.',
      );
    }

    // Execute the repository method
    return await _repository.uploadVideo(
      videoPath: videoPath,
      title: title.trim(),
      description: description.trim(),
      link: link?.trim(),
      onProgress: onProgress,
    );
  }

  /// Validates the input parameters
  void _validateInputs(String videoPath, String title, String description) {
    if (videoPath.isEmpty) {
      throw const ValidationException('Video path cannot be empty');
    }
    
    if (title.isEmpty) {
      throw const ValidationException('Video title cannot be empty');
    }
    
    if (description.isEmpty) {
      throw const ValidationException('Video description cannot be empty');
    }
  }
}
