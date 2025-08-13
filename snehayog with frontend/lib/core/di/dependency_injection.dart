import 'package:http/http.dart' as http;
import '../../features/video/data/datasources/video_remote_datasource.dart';
import '../../features/video/data/repositories/video_repository_impl.dart';
import '../../features/video/domain/repositories/video_repository.dart';
import '../../features/video/presentation/providers/video_provider.dart';

/// Simple service locator for dependency injection
/// This provides a lightweight alternative to external DI libraries
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  // Core services
  http.Client? _httpClient;
  VideoRemoteDataSource? _videoRemoteDataSource;
  VideoRepository? _videoRepository;

  // Getters
  http.Client get httpClient => _httpClient ??= http.Client();
  VideoRemoteDataSource get videoRemoteDataSource => 
      _videoRemoteDataSource ??= VideoRemoteDataSource(httpClient: httpClient);
  VideoRepository get videoRepository => 
      _videoRepository ??= VideoRepositoryImpl(remoteDataSource: videoRemoteDataSource);

  /// Creates a new VideoProvider instance
  VideoProvider createVideoProvider() {
    return VideoProvider(repository: videoRepository);
  }

  /// Cleans up all dependencies
  void dispose() {
    _httpClient?.close();
    _httpClient = null;
    _videoRemoteDataSource = null;
    _videoRepository = null;
  }
}

/// Global service locator instance
final serviceLocator = ServiceLocator();
