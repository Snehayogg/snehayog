import '../repositories/video_repository.dart';
import '../../../../core/exceptions/app_exceptions.dart';

/// Use case for fetching videos with pagination
/// This encapsulates the business logic for retrieving videos
class GetVideosUseCase {
  final VideoRepository _repository;

  const GetVideosUseCase(this._repository);

  /// Executes the use case to fetch videos
  ///
  /// Parameters:
  /// - page: The page number for pagination (starts from 1)
  /// - limit: The number of videos per page
  ///
  /// Returns:
  /// - A map containing the list of videos and pagination info
  /// - Throws [AppException] if the operation fails
  Future<Map<String, dynamic>> execute({
    int page = 1,
    int limit = 10,
  }) async {
    // Validate input parameters
    if (page < 1) {
      throw const ValidationException('Page number must be greater than 0');
    }

    if (limit < 1 || limit > 50) {
      throw const ValidationException('Limit must be between 1 and 50');
    }

    // Execute the repository method
    return await _repository.getVideos(page: page, limit: limit);
  }
}
