import 'package:vayug/features/auth/data/usermodel.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/profile/search/data/models/search_suggestions.dart';

/// **CONTRACT LAYER — Do NOT change this interface.**
///
/// This is the "FFmpeg codec specification" for Search.
/// Any search backend (HTTP, AI, offline, mock) implements this.
///
/// Consumers (screens, widgets) depend on [ISearchService], never on a
/// concrete implementation — so swapping backends requires zero UI changes.
abstract class ISearchService {
  /// Full-text search for videos matching [query].
  Future<List<VideoModel>> searchVideos(String query, {int limit = 20});

  /// Full-text search for creators/users matching [query].
  Future<List<UserModel>> searchCreators(String query, {int limit = 20});

  /// Lightweight autocomplete — returns a small set of creators + videos.
  /// Called on every keystroke (debounced by the consumer).
  Future<SearchSuggestions> getSuggestions(String query);
}
