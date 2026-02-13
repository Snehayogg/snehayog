import 'package:vayu/shared/models/video_model.dart';

/// Utility class to check and analyze video URLs
class VideoUrlChecker {
  /// Check if URL is from R2
  static bool isR2Url(String url) {
    final lower = url.toLowerCase();
    return lower.contains('r2.cloudflarestorage.com') ||
        lower.contains('r2.dev') ||
        lower.contains('cloudflare');
  }

  /// Check if URL is from Cloudinary
  static bool isCloudinaryUrl(String url) {
    return url.toLowerCase().contains('cloudinary.com');
  }

  /// Check if URL is HLS
  static bool isHLSUrl(String url) {
    return url.toLowerCase().contains('.m3u8') ||
        url.toLowerCase().contains('/hls/');
  }

  /// Check if URL is from CDN
  static bool isCDNUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('cdn.snehayog.site') ||
        lower.contains('cdn.') ||
        isR2Url(url);
  }

  /// Get URL source type
  static String getUrlSource(String url) {
    if (isR2Url(url)) return 'Cloudflare R2';
    if (isCDNUrl(url)) return 'CDN';
    if (isHLSUrl(url)) return 'HLS Streaming';
    if (isCloudinaryUrl(url)) return 'Cloudinary';
    return 'Unknown';
  }

  /// Get URL quality indicator
  static String getUrlQuality(String url) {
    if (isR2Url(url)) return '🟢 BEST (R2 CDN)';
    if (isCDNUrl(url)) return '🟢 GOOD (CDN)';
    if (isHLSUrl(url)) return '🟡 OK (HLS)';
    if (isCloudinaryUrl(url)) return '🔴 SLOW (Cloudinary)';
    return '⚪ UNKNOWN';
  }

  /// Analyze video URLs and print detailed report
  static void analyzeVideoUrls(VideoModel video) {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 VIDEO URL ANALYSIS');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('Video: ${video.videoName}');
    print('Video ID: ${video.id}');
    print('');

    // Main video URL
    print('1️⃣ Main Video URL:');
    print('   URL: ${video.videoUrl}');
    print('   Source: ${getUrlSource(video.videoUrl)}');
    print('   Quality: ${getUrlQuality(video.videoUrl)}');
    print('');

    // Low quality URL
    if (video.lowQualityUrl != null && video.lowQualityUrl!.isNotEmpty) {
      print('2️⃣ Low Quality URL (480p):');
      print('   URL: ${video.lowQualityUrl}');
      print('   Source: ${getUrlSource(video.lowQualityUrl!)}');
      print('   Quality: ${getUrlQuality(video.lowQualityUrl!)}');
      print('');
    }

    // HLS Master Playlist
    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      print('3️⃣ HLS Master Playlist:');
      print('   URL: ${video.hlsMasterPlaylistUrl}');
      print('   Source: ${getUrlSource(video.hlsMasterPlaylistUrl!)}');
      print('   Quality: ${getUrlQuality(video.hlsMasterPlaylistUrl!)}');
      print('');
    }

    // HLS Playlist
    if (video.hlsPlaylistUrl != null && video.hlsPlaylistUrl!.isNotEmpty) {
      print('4️⃣ HLS Playlist:');
      print('   URL: ${video.hlsPlaylistUrl}');
      print('   Source: ${getUrlSource(video.hlsPlaylistUrl!)}');
      print('   Quality: ${getUrlQuality(video.hlsPlaylistUrl!)}');
      print('');
    }

    // Summary
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📌 SUMMARY:');

    bool hasR2 = false;
    bool hasCloudinary = false;
    bool hasHLS = false;

    // Check all URLs
    final allUrls = [
      video.videoUrl,
      if (video.lowQualityUrl != null) video.lowQualityUrl!,
      if (video.hlsMasterPlaylistUrl != null) video.hlsMasterPlaylistUrl!,
      if (video.hlsPlaylistUrl != null) video.hlsPlaylistUrl!,
    ];

    for (final url in allUrls) {
      if (isR2Url(url)) hasR2 = true;
      if (isCloudinaryUrl(url)) hasCloudinary = true;
      if (isHLSUrl(url)) hasHLS = true;
    }

    print('   ✅ R2 URLs Available: ${hasR2 ? "YES 🟢" : "NO ❌"}');
    print('   📺 HLS Streaming: ${hasHLS ? "YES 🟢" : "NO"}');
    print(
        '   ⚠️  Cloudinary URLs: ${hasCloudinary ? "YES (Should avoid)" : "NO"}');

    // Recommendation
    print('');
    print('💡 RECOMMENDATION:');
    if (hasR2) {
      print('   🟢 This video has R2 URLs - EXCELLENT!');
      print('   Videos will play fast from Cloudflare CDN');
    } else if (hasHLS) {
      print('   🟡 This video has HLS streaming - GOOD');
      print('   Videos will stream adaptively');
    } else if (hasCloudinary) {
      print('   🔴 This video only has Cloudinary URLs - NEEDS MIGRATION');
      print('   Consider uploading to R2 for better performance');
    } else {
      print('   ⚪ Unknown source - check video upload service');
    }

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  /// Quick check - print just the essential info
  static void quickCheck(VideoModel video, String selectedUrl) {
    print('🎬 Playing: ${video.videoName}');
    print('   URL: $selectedUrl');
    print('   Source: ${getUrlSource(selectedUrl)}');
    print('   Quality: ${getUrlQuality(selectedUrl)}');

    if (isR2Url(selectedUrl)) {
      print('   ✅ Using R2 - BEST PERFORMANCE! 🚀');
    } else if (isCloudinaryUrl(selectedUrl)) {
      print('   ⚠️  Using Cloudinary - Consider R2 migration');
    }
    print('');
  }

  /// Get statistics for all videos
  static Map<String, int> getVideoUrlStatistics(List<VideoModel> videos) {
    int r2Count = 0;
    int cloudinaryCount = 0;
    int hlsCount = 0;
    int otherCount = 0;

    for (final video in videos) {
      final url = video.videoUrl;
      if (isR2Url(url)) {
        r2Count++;
      } else if (isCloudinaryUrl(url)) {
        cloudinaryCount++;
      } else if (isHLSUrl(url)) {
        hlsCount++;
      } else {
        otherCount++;
      }
    }

    return {
      'r2': r2Count,
      'cloudinary': cloudinaryCount,
      'hls': hlsCount,
      'other': otherCount,
      'total': videos.length,
    };
  }

  /// Print statistics
  static void printStatistics(List<VideoModel> videos) {
    final stats = getVideoUrlStatistics(videos);

    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 VIDEO URL STATISTICS');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('Total Videos: ${stats['total']}');
    print('');
    print(
        '🟢 R2 Videos: ${stats['r2']} (${((stats['r2']! / stats['total']!) * 100).toStringAsFixed(1)}%)');
    print(
        '🟡 HLS Videos: ${stats['hls']} (${((stats['hls']! / stats['total']!) * 100).toStringAsFixed(1)}%)');
    print(
        '🔴 Cloudinary: ${stats['cloudinary']} (${((stats['cloudinary']! / stats['total']!) * 100).toStringAsFixed(1)}%)');
    print(
        '⚪ Other: ${stats['other']} (${((stats['other']! / stats['total']!) * 100).toStringAsFixed(1)}%)');
    print('');

    final r2Percentage = (stats['r2']! / stats['total']!) * 100;
    if (r2Percentage >= 80) {
      print('✅ EXCELLENT: ${r2Percentage.toStringAsFixed(0)}% videos on R2!');
    } else if (r2Percentage >= 50) {
      print('🟡 GOOD: ${r2Percentage.toStringAsFixed(0)}% videos on R2');
    } else {
      print(
          '🔴 NEEDS WORK: Only ${r2Percentage.toStringAsFixed(0)}% videos on R2');
      print('   Consider migrating more videos to R2');
    }
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }
}
