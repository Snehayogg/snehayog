import '../../features/video/data/datasources/video_remote_datasource.dart';
import '../../features/video/data/repositories/video_repository_impl.dart';
import '../../features/video/domain/repositories/video_repository.dart';
import '../providers/video_provider.dart';

/// Simple service locator for dependency injection
/// This provides a lightweight alternative to external DI libraries
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  // Core services
  VideoRemoteDataSource? _videoRemoteDataSource;
  VideoRepository? _videoRepository;

  // Getters
  VideoRemoteDataSource get videoRemoteDataSource =>
      _videoRemoteDataSource ??= VideoRemoteDataSource();
  VideoRepository get videoRepository => _videoRepository ??=
      VideoRepositoryImpl(remoteDataSource: videoRemoteDataSource);

  /// Creates a new VideoProvider instance
  VideoProvider createVideoProvider() {
    return VideoProvider();
  }

  /// Cleans up all dependencies
  void dispose() {
    _videoRemoteDataSource = null;
    _videoRepository = null;
  }
}

/// Global service locator instance
final serviceLocator = ServiceLocator();
