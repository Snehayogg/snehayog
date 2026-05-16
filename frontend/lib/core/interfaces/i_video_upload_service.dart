import 'dart:io';

abstract class IVideoUploadService {
  /// Stream of upload progress (0.0 to 1.0)
  Stream<double> get uploadProgress;

  /// Validates the video file before processing
  Future<bool> validateVideo(File videoFile);

  /// Generates a thumbnail for the video
  Future<File?> generateThumbnail(File videoFile);

  /// Performs the actual upload to the server
  /// Returns the URL of the uploaded video or null on failure
  Future<String?> uploadVideo({
    required File videoFile,
    File? thumbnailFile,
    required String title,
    required String description,
    Map<String, dynamic>? metadata,
  });

  /// Cancels any ongoing upload
  void cancelUpload();
}
