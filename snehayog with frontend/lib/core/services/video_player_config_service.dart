import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing video player configuration and preferences
class VideoPlayerConfigService {
  static const String _autoPlayKey = 'video_auto_play';
  static const String _loopKey = 'video_loop';
  static const String _qualityKey = 'video_quality';
  static const String _volumeKey = 'video_volume';
  static const String _playbackSpeedKey = 'video_playback_speed';
  static const String _enableHLSKey = 'video_enable_hls';
  static const String _enableAdsKey = 'video_enable_ads';
  static const String _cacheSizeKey = 'video_cache_size';

  /// Get auto-play preference
  static Future<bool> getAutoPlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoPlayKey) ?? true;
  }

  /// Set auto-play preference
  static Future<void> setAutoPlay(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPlayKey, value);
  }

  /// Get loop preference
  static Future<bool> getLoop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loopKey) ?? true;
  }

  /// Set loop preference
  static Future<void> setLoop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loopKey, value);
  }

  /// Get video quality preference
  static Future<String> getVideoQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_qualityKey) ?? 'auto';
  }

  /// Set video quality preference
  static Future<void> setVideoQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_qualityKey, quality);
  }

  /// Get volume preference
  static Future<double> getVolume() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_volumeKey) ?? 1.0;
  }

  /// Set volume preference
  static Future<void> setVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, volume);
  }

  /// Get playback speed preference
  static Future<double> getPlaybackSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_playbackSpeedKey) ?? 1.0;
  }

  /// Set playback speed preference
  static Future<void> setPlaybackSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_playbackSpeedKey, speed);
  }

  /// Get HLS enable preference
  static Future<bool> getEnableHLS() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enableHLSKey) ?? true;
  }

  /// Set HLS enable preference
  static Future<void> setEnableHLS(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableHLSKey, value);
  }

  /// Get ads enable preference
  static Future<bool> getEnableAds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enableAdsKey) ?? true;
  }

  /// Set ads enable preference
  static Future<void> setEnableAds(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableAdsKey, value);
  }

  /// Get cache size preference (in MB)
  static Future<int> getCacheSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cacheSizeKey) ?? 100;
  }

  /// Set cache size preference (in MB)
  static Future<void> setCacheSize(int sizeMB) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cacheSizeKey, sizeMB);
  }

  /// Reset all preferences to default values
  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Get all current preferences as a map
  static Future<Map<String, dynamic>> getAllPreferences() async {
    return {
      'autoPlay': await getAutoPlay(),
      'loop': await getLoop(),
      'quality': await getVideoQuality(),
      'volume': await getVolume(),
      'playbackSpeed': await getPlaybackSpeed(),
      'enableHLS': await getEnableHLS(),
      'enableAds': await getEnableAds(),
      'cacheSize': await getCacheSize(),
    };
  }
}
