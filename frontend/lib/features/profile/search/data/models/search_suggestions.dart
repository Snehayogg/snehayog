import 'package:vayug/features/auth/data/usermodel.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';

/// **DATA MODEL — Typed result for search suggestions (autocomplete).**
///
/// Replaces the old `Map<String, dynamic>` return type from [SearchService.getSuggestions].
/// Using a typed class means the compiler catches missing fields — no more silent runtime bugs.
///
/// Usage:
/// ```dart
/// final SearchSuggestions s = await searchService.getSuggestions('yoga');
/// s.creators  // List<UserModel>
/// s.videos    // List<VideoModel>
/// ```
class SearchSuggestions {
  final List<UserModel> creators;
  final List<VideoModel> videos;

  const SearchSuggestions({
    required this.creators,
    required this.videos,
  });

  /// Convenience: an empty result (no network call needed).
  static const empty = SearchSuggestions(creators: [], videos: []);

  /// Convenience: copy with overrides.
  SearchSuggestions copyWith({
    List<UserModel>? creators,
    List<VideoModel>? videos,
  }) {
    return SearchSuggestions(
      creators: creators ?? this.creators,
      videos: videos ?? this.videos,
    );
  }
}
