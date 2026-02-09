import 'dart:io';
import 'package:photo_manager/photo_manager.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/utils/app_logger.dart';

/// **LocalGalleryService: Manages retrieval of videos from the device's gallery**
/// This service handles permissions and maps native media assets to our [VideoModel].
class LocalGalleryService {
  static final LocalGalleryService _instance = LocalGalleryService._internal();
  factory LocalGalleryService() => _instance;
  LocalGalleryService._internal();

  /// Fetches videos from the user's gallery and converts them to [VideoModel]s.
  /// Used as an offline fallback when internet is unavailable.
  Future<List<VideoModel>> fetchGalleryVideos({int page = 0, int limit = 20}) async {
    try {
      // 1. Check/Request Permission
      AppLogger.log('🎞️ LocalGalleryService: Requesting permissions...');
      
      // photo_manager handles the underlying complex permission logic for different OS versions
      final PermissionState ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(),
      );
      
      AppLogger.log('🎞️ LocalGalleryService: Permission state: $ps');
      
      if (!ps.isAuth && ps != PermissionState.limited) {
        AppLogger.log('🚫 LocalGalleryService: Permission denied or restricted');
        // Handle the case where user permanently denied (should show settings dialog)
        if (ps == PermissionState.denied) {
           AppLogger.log('⚠️ LocalGalleryService: Permission permanently denied. User might need to enable it in settings.');
        }
        return [];
      }

      // 2. Fetch Assets (Videos only)
      final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: true,
      );

      if (paths.isEmpty) return [];

      final List<AssetEntity> entities = await paths.first.getAssetListPaged(
        page: page,
        size: limit,
      );

      // 3. Map Assets to VideoModels
      final List<VideoModel> galleryVideos = [];
      
      for (var asset in entities) {
        final videoModel = await _mapAssetToVideoModel(asset);
        if (videoModel != null) {
          galleryVideos.add(videoModel);
        }
      }

      return galleryVideos;
    } catch (e) {
      AppLogger.log('❌ LocalGalleryService: Error fetching videos: $e');
      return [];
    }
  }

  /// Maps a native [AssetEntity] to our internal [VideoModel].
  Future<VideoModel?> _mapAssetToVideoModel(AssetEntity asset) async {
    try {
      final File? file = await asset.file;
      if (file == null) return null;

      final String thumbnailUrl = '';

      // We use the file path as the video URL for local playback
      final String filePath = file.path;
      
      // Use asset ID as a persistent identifier
      final String id = 'local_${asset.id}';

      return VideoModel(
        id: id,
        videoName: asset.title ?? 'Gallery Video',
        videoUrl: filePath, // VideoPlayerController.file(File(videoUrl)) will be used
        thumbnailUrl: thumbnailUrl, // Using local thumb file path
        likes: 0,
        views: 0,
        shares: 0,
        uploader: Uploader(
          id: 'local_user',
          name: 'My Gallery',
          profilePic: '',
        ),
        uploadedAt: asset.createDateTime,
        likedBy: [],
        videoType: 'local_gallery', // Custom type to distinguish from server videos
        aspectRatio: asset.width / asset.height,
        duration: asset.videoDuration,
        processingStatus: 'completed',
      );
    } catch (e) {
      AppLogger.log('❌ LocalGalleryService: Error mapping asset: $e');
      return null;
    }
  }
}

final localGalleryService = LocalGalleryService();
