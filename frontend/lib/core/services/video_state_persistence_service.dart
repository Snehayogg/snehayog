import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snehayog/model/video_model.dart';

/// **NEW: Service to preserve video state across navigation and app lifecycle**
/// This solves the issues:
/// 1. Video restart instead of resume
/// 2. Unnecessary API calls
/// 3. App lifecycle state preservation
class VideoStatePersistenceService {
  static const String _videoStateKey = 'video_screen_state';
  static const String _videoPositionKey = 'video_positions';
  static const String _playbackStateKey = 'playback_state';
  static const String _lastActiveIndexKey = 'last_active_index';
  static const String _lastActiveTimeKey = 'last_active_time';
  static const String _cachedVideosKey = 'cached_videos_data';

  /// **NEW: Save complete video screen state**
  static Future<void> saveVideoScreenState({
    required int activeIndex,
    required List<VideoModel> videos,
    required Map<int, double> videoPositions,
    required Map<int, bool> playbackStates,
    required bool isPlaying,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save current active index
      await prefs.setInt(_lastActiveIndexKey, activeIndex);
      await prefs.setString(
          _lastActiveTimeKey, DateTime.now().toIso8601String());

      // Save video positions (where user left off)
      final positionMap =
          videoPositions.map((key, value) => MapEntry(key.toString(), value));
      await prefs.setString(_videoPositionKey, jsonEncode(positionMap));

      // Save playback states (playing/paused)
      final playbackMap =
          playbackStates.map((key, value) => MapEntry(key.toString(), value));
      await prefs.setString(_playbackStateKey, jsonEncode(playbackMap));

      // Save current playback state
      await prefs.setBool('is_playing', isPlaying);

      // Save video data to prevent unnecessary API calls
      await _saveCachedVideos(videos);

      print('✅ VideoStatePersistenceService: State saved successfully');
      print('   Active Index: $activeIndex');
      print('   Video Positions: $videoPositions');
      print('   Playback States: $playbackStates');
      print('   Is Playing: $isPlaying');
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error saving state: $e');
    }
  }

  /// **NEW: Restore complete video screen state**
  static Future<Map<String, dynamic>> restoreVideoScreenState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get last active index
      final lastActiveIndex = prefs.getInt(_lastActiveIndexKey) ?? 0;

      // Get video positions
      final positionJson = prefs.getString(_videoPositionKey) ?? '{}';
      final positionMap = Map<String, dynamic>.from(jsonDecode(positionJson));
      final videoPositions = positionMap.map(
          (key, value) => MapEntry(int.parse(key), (value as num).toDouble()));

      // Get playback states
      final playbackJson = prefs.getString(_playbackStateKey) ?? '{}';
      final playbackMap = Map<String, dynamic>.from(jsonDecode(playbackJson));
      final playbackStates = playbackMap
          .map((key, value) => MapEntry(int.parse(key), value as bool));

      // Get current playback state
      final isPlaying = prefs.getBool('is_playing') ?? false;

      // Get cached videos
      final cachedVideos = await _getCachedVideos();

      // Check if state is still valid (not too old)
      final lastActiveTime = prefs.getString(_lastActiveTimeKey);
      final isStateValid = _isStateValid(lastActiveTime);

      final state = {
        'activeIndex': lastActiveIndex,
        'videoPositions': videoPositions,
        'playbackStates': playbackStates,
        'isPlaying': isPlaying,
        'cachedVideos': cachedVideos,
        'isStateValid': isStateValid,
        'lastActiveTime': lastActiveTime,
      };

      print('✅ VideoStatePersistenceService: State restored successfully');
      print('   Active Index: $lastActiveIndex');
      print('   Video Positions: $videoPositions');
      print('   Playback States: $playbackStates');
      print('   Is Playing: $isPlaying');
      print('   State Valid: $isStateValid');

      return state;
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error restoring state: $e');
      return {
        'activeIndex': 0,
        'videoPositions': <int, double>{},
        'playbackStates': <int, bool>{},
        'isPlaying': false,
        'cachedVideos': <VideoModel>[],
        'isStateValid': false,
        'lastActiveTime': null,
      };
    }
  }

  /// **NEW: Save video data to prevent unnecessary API calls**
  static Future<void> _saveCachedVideos(List<VideoModel> videos) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Convert videos to JSON for storage
      final videosJson = videos.map((video) => video.toJson()).toList();
      await prefs.setString(_cachedVideosKey, jsonEncode(videosJson));

      print('✅ VideoStatePersistenceService: Cached ${videos.length} videos');
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error caching videos: $e');
    }
  }

  /// **NEW: Get cached videos to avoid API calls**
  static Future<List<VideoModel>> _getCachedVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final videosJson = prefs.getString(_cachedVideosKey);

      if (videosJson != null) {
        final videosList = jsonDecode(videosJson) as List<dynamic>;
        final videos =
            videosList.map((json) => VideoModel.fromJson(json)).toList();
        print(
            '✅ VideoStatePersistenceService: Retrieved ${videos.length} cached videos');
        return videos;
      }
    } catch (e) {
      print(
          '❌ VideoStatePersistenceService: Error retrieving cached videos: $e');
    }

    return <VideoModel>[];
  }

  /// **NEW: Check if saved state is still valid (not too old)**
  static bool _isStateValid(String? lastActiveTime) {
    if (lastActiveTime == null) return false;

    try {
      final lastTime = DateTime.parse(lastActiveTime);
      final now = DateTime.now();
      final difference = now.difference(lastTime);

      // State is valid if it's less than 30 minutes old
      const maxAge = Duration(minutes: 30);
      return difference < maxAge;
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error parsing time: $e');
      return false;
    }
  }

  /// **NEW: Save current video position for a specific video**
  static Future<void> saveVideoPosition(int videoIndex, double position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final positionJson = prefs.getString(_videoPositionKey) ?? '{}';
      final positionMap = Map<String, dynamic>.from(jsonDecode(positionJson));

      positionMap[videoIndex.toString()] = position;

      await prefs.setString(_videoPositionKey, jsonEncode(positionMap));
      print(
          '✅ VideoStatePersistenceService: Saved position for video $videoIndex: $position');
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error saving position: $e');
    }
  }

  /// **NEW: Get saved position for a specific video**
  static Future<double> getVideoPosition(int videoIndex) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final positionJson = prefs.getString(_videoPositionKey) ?? '{}';
      final positionMap = Map<String, dynamic>.from(jsonDecode(positionJson));

      final position = positionMap[videoIndex.toString()];
      if (position != null) {
        print(
            '✅ VideoStatePersistenceService: Retrieved position for video $videoIndex: $position');
        return (position as num).toDouble();
      }
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error getting position: $e');
    }

    return 0.0; // Default to beginning
  }

  /// **NEW: Save playback state for a specific video**
  static Future<void> savePlaybackState(int videoIndex, bool isPlaying) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final playbackJson = prefs.getString(_playbackStateKey) ?? '{}';
      final playbackMap = Map<String, dynamic>.from(jsonDecode(playbackJson));

      playbackMap[videoIndex.toString()] = isPlaying;

      await prefs.setString(_playbackStateKey, jsonEncode(playbackMap));
      print(
          '✅ VideoStatePersistenceService: Saved playback state for video $videoIndex: $isPlaying');
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error saving playback state: $e');
    }
  }

  /// **NEW: Get saved playback state for a specific video**
  static Future<bool> getPlaybackState(int videoIndex) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final playbackJson = prefs.getString(_playbackStateKey) ?? '{}';
      final playbackMap = Map<String, dynamic>.from(jsonDecode(playbackJson));

      final isPlaying = playbackMap[videoIndex.toString()];
      if (isPlaying != null) {
        print(
            '✅ VideoStatePersistenceService: Retrieved playback state for video $videoIndex: $isPlaying');
        return isPlaying as bool;
      }
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error getting playback state: $e');
    }

    return false; // Default to paused
  }

  /// **NEW: Clear all saved state (useful for logout or reset)**
  static Future<void> clearAllState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_videoStateKey);
      await prefs.remove(_videoPositionKey);
      await prefs.remove(_playbackStateKey);
      await prefs.remove(_lastActiveIndexKey);
      await prefs.remove(_lastActiveTimeKey);
      await prefs.remove(_cachedVideosKey);
      await prefs.remove('is_playing');

      print('✅ VideoStatePersistenceService: All state cleared');
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error clearing state: $e');
    }
  }

  /// **NEW: Check if there's valid cached state available**
  static Future<bool> hasValidCachedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActiveTime = prefs.getString(_lastActiveTimeKey);
      final hasCachedVideos = prefs.getString(_cachedVideosKey) != null;

      return _isStateValid(lastActiveTime) && hasCachedVideos;
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error checking cached state: $e');
      return false;
    }
  }

  /// **NEW: Get summary of current state for debugging**
  static Future<Map<String, dynamic>> getStateSummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      return {
        'lastActiveIndex': prefs.getInt(_lastActiveIndexKey),
        'lastActiveTime': prefs.getString(_lastActiveTimeKey),
        'hasCachedVideos': prefs.getString(_cachedVideosKey) != null,
        'hasVideoPositions': prefs.getString(_videoPositionKey) != null,
        'hasPlaybackStates': prefs.getString(_playbackStateKey) != null,
        'isPlaying': prefs.getBool('is_playing'),
        'isStateValid': _isStateValid(prefs.getString(_lastActiveTimeKey)),
      };
    } catch (e) {
      print('❌ VideoStatePersistenceService: Error getting state summary: $e');
      return {};
    }
  }
}
