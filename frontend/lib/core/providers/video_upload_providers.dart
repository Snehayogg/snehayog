import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/interfaces/i_video_upload_service.dart';
import 'package:vayug/features/video/upload/data/services/video_upload_service_impl.dart';
import 'package:vayug/core/providers/video_providers.dart';
import 'package:vayug/features/video/upload/presentation/managers/upload_state_manager.dart';

/// The "FFmpeg" Injection Layer
/// This provider gives you the Video Upload Service contract.
/// You can swap 'VideoUploadService' with a 'MockUploadService' for testing
/// or a 'S3UploadService' in the future without changing any UI code.
final videoUploadServiceProvider = Provider<IVideoUploadService>((ref) {
  final videoService = ref.watch(videoServiceProvider);
  return VideoUploadService(videoService: videoService);
});

final uploadStateManagerProvider = ChangeNotifierProvider<UploadStateManager>((ref) {
  final uploadService = ref.watch(videoUploadServiceProvider);
  final videoService = ref.watch(videoServiceProvider);
  return UploadStateManager(
    uploadService: uploadService,
    videoService: videoService,
  );
});
